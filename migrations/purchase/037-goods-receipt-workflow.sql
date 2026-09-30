-- ============================================================
-- Migration: 037-goods-receipt-workflow
-- Schema: purchase
-- Date: 2026-09-29
-- Author: Claude (session work)
--
-- Why: reporte de cliente -- "falta activar edicion de articulos luego de
-- ENVIAR la factura antes de RECIBIR la mercancia (si el proveedor envia
-- mal la mercancia debe haber manera de editar la lista de productos que
-- se reciben)". Causa raiz encontrada: create_goods_receipt() copiaba
-- goods_receipt_item directo de purchase_order_item en el mismo instante
-- en que la orden pasaba a status 3 (Delivered), sin ningun paso humano
-- de por medio -- por construccion, la cantidad recibida siempre coincidia
-- con la cantidad pedida, y el three-way matching (three_way_matching /
-- purchase_dispute, ya existentes en el schema) nunca podia detectar una
-- discrepancia de cantidad real.
--
-- Fix: separa "recepcion" en dos pasos explicitos en vez de un side-effect
-- automatico de un UPDATE de status arbitrario:
--   1. start_goods_receipt()        -- orden en status 2 (Shipped/enviada):
--                                       crea goods_receipt PENDING +
--                                       goods_receipt_item precargado desde
--                                       purchase_order_item como checklist.
--   2. update_goods_receipt_items() -- mientras PENDING: corrige cantidad y
--                                       productos contra lo que realmente
--                                       llego. Doble candado backend+DB
--                                       (mismo criterio que update_supplier_invoice).
--   3. confirm_goods_receipt()      -- bloquea edicion, aplica inventario
--                                       desde los items ya corregidos, corre
--                                       three-way matching, abre
--                                       purchase_dispute automaticamente si
--                                       hay discrepancia, y recien ahi mueve
--                                       la orden a status 3 (Delivered).
--
-- purchase_order_item nunca se reescribe: sigue siendo el registro
-- inmutable de lo que se pidio originalmente (trazabilidad orden vs
-- recepcion vs factura). Un guard trigger bloquea cualquier UPDATE que
-- ponga purchase_order_status_id = 3 fuera de confirm_goods_receipt().
-- ============================================================

ALTER TABLE purchase_schema.goods_receipt
    ADD COLUMN IF NOT EXISTS status VARCHAR(10) NOT NULL DEFAULT 'PENDING',
    ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMP;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'goods_receipt_status_check'
          AND conrelid = 'purchase_schema.goods_receipt'::regclass
    ) THEN
        ALTER TABLE purchase_schema.goods_receipt
            ADD CONSTRAINT goods_receipt_status_check CHECK (status IN ('PENDING', 'CONFIRMED'));
    END IF;
END $$;

-- apply_inventory_on_delivery: firma cambia de (purchase_order_id) a
-- (purchase_order_id, goods_receipt_id); lee de goods_receipt_item en vez
-- de purchase_order_item.
DROP FUNCTION IF EXISTS purchase_schema.apply_inventory_on_delivery(UUID);

CREATE OR REPLACE FUNCTION purchase_schema.apply_inventory_on_delivery(p_purchase_order_id UUID, p_goods_receipt_id UUID) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_warehouse_id UUID;
    v_log_in_type_id INTEGER;
    v_item RECORD;
    v_component RECORD;
    v_is_composite BOOLEAN;
    v_total_qty INTEGER;
    v_target_is_branch BOOLEAN;
BEGIN
    SELECT po.warehouse_id INTO v_warehouse_id
    FROM purchase_schema.purchase_order po
    WHERE po.purchase_order_id = p_purchase_order_id;

    IF v_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'apply_inventory_on_delivery: warehouse not found for PO %', p_purchase_order_id;
    END IF;

    SELECT w.is_branch INTO v_target_is_branch
    FROM inventory_schema.warehouse w
    WHERE w.warehouse_id = v_warehouse_id;

    SELECT inventory_log_type_id INTO v_log_in_type_id
    FROM inventory_schema.inventory_log_type
    WHERE inventory_log_type_name = 'IN'
    LIMIT 1;

    FOR v_item IN
        SELECT gri.tenant_id, gri.product_variant_id, gri.quantity_received
        FROM purchase_schema.goods_receipt_item gri
        WHERE gri.goods_receipt_id = p_goods_receipt_id
    LOOP
        SELECT pv.is_composite INTO v_is_composite
        FROM general_schema.product_variant pv
        WHERE pv.tenant_id = v_item.tenant_id
          AND pv.product_variant_id = v_item.product_variant_id;

        IF v_is_composite IS TRUE AND v_target_is_branch IS TRUE THEN
            FOR v_component IN
                SELECT pvc.child_product_variant_id, pvc.quantity AS component_qty
                FROM general_schema.product_variant_composition pvc
                WHERE pvc.tenant_id = v_item.tenant_id
                  AND pvc.parent_product_variant_id = v_item.product_variant_id
            LOOP
                v_total_qty := v_item.quantity_received * v_component.component_qty;

                PERFORM purchase_schema.upsert_inventory_stock(
                    v_item.tenant_id,
                    v_component.child_product_variant_id,
                    v_warehouse_id,
                    v_total_qty,
                    v_log_in_type_id
                );
            END LOOP;
        ELSE
            PERFORM purchase_schema.upsert_inventory_stock(
                v_item.tenant_id,
                v_item.product_variant_id,
                v_warehouse_id,
                v_item.quantity_received,
                v_log_in_type_id
            );
        END IF;
    END LOOP;
END;
$$;


CREATE OR REPLACE FUNCTION purchase_schema.start_goods_receipt(p_purchase_order_id uuid) RETURNS uuid AS $$
DECLARE
    v_status_id int;
    v_goods_receipt_id uuid;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
BEGIN
    SELECT purchase_order_status_id INTO v_status_id
    FROM purchase_schema.purchase_order
    WHERE purchase_order_id = p_purchase_order_id;

    IF v_status_id IS NULL THEN
        RAISE EXCEPTION 'purchase_order % not found', p_purchase_order_id;
    END IF;

    IF v_status_id IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'purchase_order % cannot start a goods receipt: purchase_order_status_id is %, only status 2 (Shipped/enviada) allows it', p_purchase_order_id, v_status_id;
    END IF;

    SELECT goods_receipt_id INTO v_goods_receipt_id
    FROM purchase_schema.goods_receipt
    WHERE purchase_order_id = p_purchase_order_id;

    IF v_goods_receipt_id IS NOT NULL THEN
        IF (SELECT status FROM purchase_schema.goods_receipt WHERE goods_receipt_id = v_goods_receipt_id) = 'CONFIRMED' THEN
            RAISE EXCEPTION 'purchase_order % already has a confirmed goods receipt', p_purchase_order_id;
        END IF;
        RETURN v_goods_receipt_id;
    END IF;

    SELECT ap.subtotal, sap.tax_amount
    INTO v_subtotal, v_tax_amount
    FROM general_schema.account_payable ap
    JOIN purchase_schema.purchase_account_payable sap
        ON ap.account_payable_id = sap.account_payable_id
    WHERE sap.purchase_order_id = p_purchase_order_id;

    INSERT INTO purchase_schema.goods_receipt(
        purchase_order_id, received_date, status, subtotal_amount, tax_amount
    ) VALUES (
        p_purchase_order_id, current_timestamp, 'PENDING', coalesce(v_subtotal, 0), coalesce(v_tax_amount, 0)
    ) RETURNING goods_receipt_id INTO v_goods_receipt_id;

    INSERT INTO purchase_schema.goods_receipt_item(
        goods_receipt_id, tenant_id, product_variant_id, quantity_received
    )
    SELECT v_goods_receipt_id, poi.tenant_id, poi.product_variant_id, poi.quantity_ordered
    FROM purchase_schema.purchase_order_item poi
    WHERE poi.purchase_order_id = p_purchase_order_id;

    RETURN v_goods_receipt_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION purchase_schema.update_goods_receipt_items(p_goods_receipt_id uuid, p_items jsonb, p_tenant_id uuid) RETURNS VOID AS $$
DECLARE
    v_status VARCHAR(10);
    v_item jsonb;
    v_product_id uuid;
    v_qty INTEGER;
BEGIN
    SELECT status INTO v_status
    FROM purchase_schema.goods_receipt
    WHERE goods_receipt_id = p_goods_receipt_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'goods_receipt % not found', p_goods_receipt_id;
    END IF;

    IF v_status IS DISTINCT FROM 'PENDING' THEN
        RAISE EXCEPTION 'goods_receipt % cannot be edited: status is %, only PENDING allows edits', p_goods_receipt_id, v_status;
    END IF;

    DELETE FROM purchase_schema.goods_receipt_item
    WHERE goods_receipt_id = p_goods_receipt_id;

    IF p_items IS NOT NULL AND jsonb_typeof(p_items) = 'array' THEN
        FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
        LOOP
            v_product_id := (v_item ->> 'product_variant_id')::uuid;
            v_qty := coalesce((v_item ->> 'quantity_received')::int, 0);

            INSERT INTO purchase_schema.goods_receipt_item(
                goods_receipt_id, tenant_id, product_variant_id, quantity_received
            ) VALUES (
                p_goods_receipt_id, p_tenant_id, v_product_id, v_qty
            );
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION purchase_schema.confirm_goods_receipt(p_goods_receipt_id uuid) RETURNS VOID AS $$
DECLARE
    v_status VARCHAR(10);
    v_purchase_order_id uuid;
    v_tenant_id uuid;
    v_supplier_invoice_id uuid;
    v_item_count int;
    v_matching RECORD;
BEGIN
    SELECT status, purchase_order_id INTO v_status, v_purchase_order_id
    FROM purchase_schema.goods_receipt
    WHERE goods_receipt_id = p_goods_receipt_id;

    IF v_purchase_order_id IS NULL THEN
        RAISE EXCEPTION 'goods_receipt % not found', p_goods_receipt_id;
    END IF;

    IF v_status IS DISTINCT FROM 'PENDING' THEN
        RAISE EXCEPTION 'goods_receipt % cannot be confirmed: status is %, only PENDING allows confirmation', p_goods_receipt_id, v_status;
    END IF;

    SELECT count(*) INTO v_item_count
    FROM purchase_schema.goods_receipt_item
    WHERE goods_receipt_id = p_goods_receipt_id;

    IF v_item_count = 0 THEN
        RAISE EXCEPTION 'goods_receipt % cannot be confirmed with zero items', p_goods_receipt_id;
    END IF;

    UPDATE purchase_schema.goods_receipt
    SET status = 'CONFIRMED', confirmed_at = current_timestamp, updated_at = current_timestamp
    WHERE goods_receipt_id = p_goods_receipt_id;

    PERFORM set_config('purchase.allow_delivery_transition', 'true', true);

    UPDATE purchase_schema.purchase_order
    SET purchase_order_status_id = 3
    WHERE purchase_order_id = v_purchase_order_id;

    PERFORM purchase_schema.apply_inventory_on_delivery(v_purchase_order_id, p_goods_receipt_id);

    PERFORM purchase_schema.execute_three_way_matching(v_purchase_order_id, p_goods_receipt_id);

    SELECT amounts_matched, quantities_matched INTO v_matching
    FROM purchase_schema.three_way_matching
    WHERE goods_receipt_id = p_goods_receipt_id;

    IF v_matching IS NOT NULL AND (v_matching.amounts_matched IS FALSE OR v_matching.quantities_matched IS FALSE) THEN
        SELECT s.added_by INTO v_tenant_id
        FROM purchase_schema.purchase_order po
        JOIN purchase_schema.supplier s ON s.supplier_id = po.supplier_id
        WHERE po.purchase_order_id = v_purchase_order_id;

        SELECT supplier_invoice_id INTO v_supplier_invoice_id
        FROM purchase_schema.supplier_invoice
        WHERE purchase_order_id = v_purchase_order_id;

        IF v_matching.quantities_matched IS FALSE AND NOT EXISTS(
            SELECT 1 FROM purchase_schema.purchase_dispute
            WHERE purchase_order_id = v_purchase_order_id AND dispute_type = 'MISSING_GOODS' AND status = 'OPEN'
        ) THEN
            INSERT INTO purchase_schema.purchase_dispute(
                purchase_order_id, supplier_invoice_id, tenant_id, dispute_type, description
            ) VALUES (
                v_purchase_order_id, v_supplier_invoice_id, v_tenant_id, 'MISSING_GOODS',
                'Discrepancia de cantidad detectada automaticamente por el three-way matching al confirmar la recepcion.'
            );
        END IF;

        IF v_matching.amounts_matched IS FALSE AND NOT EXISTS(
            SELECT 1 FROM purchase_schema.purchase_dispute
            WHERE purchase_order_id = v_purchase_order_id AND dispute_type = 'PRICE_MISMATCH' AND status = 'OPEN'
        ) THEN
            INSERT INTO purchase_schema.purchase_dispute(
                purchase_order_id, supplier_invoice_id, tenant_id, dispute_type, description
            ) VALUES (
                v_purchase_order_id, v_supplier_invoice_id, v_tenant_id, 'PRICE_MISMATCH',
                'Discrepancia de monto detectada automaticamente por el three-way matching al confirmar la recepcion.'
            );
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION purchase_schema.guard_purchase_order_delivery_transition() RETURNS trigger AS $$
BEGIN
    IF new.purchase_order_status_id = 3
       AND old.purchase_order_status_id IS DISTINCT FROM 3
       AND coalesce(current_setting('purchase.allow_delivery_transition', true), '') IS DISTINCT FROM 'true'
    THEN
        RAISE EXCEPTION 'purchase_order_status_id cannot be set to 3 (Delivered) directly; use purchase_schema.confirm_goods_receipt()';
    END IF;
    RETURN new;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS create_goods_receipt_trigger ON purchase_schema.purchase_order;
DROP FUNCTION IF EXISTS purchase_schema.create_goods_receipt();

DROP TRIGGER IF EXISTS guard_purchase_order_delivery_transition_trigger ON purchase_schema.purchase_order;

CREATE TRIGGER guard_purchase_order_delivery_transition_trigger BEFORE
UPDATE OF purchase_order_status_id ON purchase_schema.purchase_order
FOR EACH ROW EXECUTE FUNCTION purchase_schema.guard_purchase_order_delivery_transition();

-- ============================================================
-- Rollback (documentacion, no se ejecuta automaticamente):
--
-- DROP TRIGGER IF EXISTS guard_purchase_order_delivery_transition_trigger ON purchase_schema.purchase_order;
-- DROP FUNCTION IF EXISTS purchase_schema.guard_purchase_order_delivery_transition();
-- DROP FUNCTION IF EXISTS purchase_schema.confirm_goods_receipt(uuid);
-- DROP FUNCTION IF EXISTS purchase_schema.update_goods_receipt_items(uuid, jsonb, uuid);
-- DROP FUNCTION IF EXISTS purchase_schema.start_goods_receipt(uuid);
-- DROP FUNCTION IF EXISTS purchase_schema.apply_inventory_on_delivery(UUID, UUID);
-- -- recrear apply_inventory_on_delivery(UUID) con la firma vieja y
-- -- create_goods_receipt_trigger si se revierte, ver version pre-037 en
-- -- migrations/purchase/ para el codigo exacto.
-- ALTER TABLE purchase_schema.goods_receipt DROP CONSTRAINT IF EXISTS goods_receipt_status_check;
-- ALTER TABLE purchase_schema.goods_receipt DROP COLUMN IF EXISTS confirmed_at;
-- ALTER TABLE purchase_schema.goods_receipt DROP COLUMN IF EXISTS status;
-- ============================================================
