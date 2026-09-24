-- Migration: 001-purchase-usd-base-currency-and-ve-tax-default
-- What: Switch Compras' implicit base currency defaults from Costa Rica
--       leftovers to Venezuela: supplier_invoice.tax_rate default moves from
--       13.00 (CR IVA) to 16.00 (VE IVA General, seeded in
--       migrations/general/027-migrate-tax-rates-to-ve.sql), and
--       purchase_order_payment.currency_id default moves from 1 (VES) to 2
--       (USD), since Compras/CxP now operates in USD as the base currency
--       (VES stays as a secondary, tasa-converted display). Also updates the
--       hardcoded fallback inside create_purchase_order() that resolves
--       tax_rate when a tenant has no region/tax_rate row.
-- Why:  MBP_Cambios_CR_a_Venezuela.md seccion 3 (Modulo de Compras):
--       "Cuentas pendientes por pagar: Visualizacion en dolares (USD)".
--       Costo/precio de producto ya opera en USD (modulo General); Compras
--       debe alinearse. IVA unico VE es 16%, no el 13% de Costa Rica.
-- Context: Fase 1 del plan de migracion del modulo de Compras. Toca la
--       funcion central create_purchase_order() (unico punto de creacion de
--       purchase_order/purchase_order_item/supplier_invoice); las Fases 2 y 3
--       la vuelven a tocar en migraciones subsiguientes (001, 002, 003) --
--       cada una reemplaza el cuerpo completo via CREATE OR REPLACE FUNCTION,
--       nunca se edita esta migracion tras mergear.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE purchase_schema.supplier_invoice
    ALTER COLUMN tax_rate SET DEFAULT 16.00;

ALTER TABLE purchase_schema.purchase_order_payment
    ALTER COLUMN currency_id SET DEFAULT 2;

CREATE OR REPLACE FUNCTION purchase_schema.create_purchase_order(p_supplier_id uuid, p_warehouse_id uuid, p_expected_delivery_date date, p_items jsonb default '[]'::jsonb, p_has_invoice BOOLEAN default true, p_payment_condition VARCHAR(10) default 'CREDIT') returns uuid as $$
declare
    v_purchase_order_id uuid;
    v_supplier_invoice_id uuid;
    v_item jsonb;
    v_tenant_id uuid;
    v_product_id uuid;
    v_qty INTEGER;
    v_unit numeric(12,3);
    v_subtotal numeric(12,3);
    v_tax_rate numeric(5,2);
    v_tax_amount numeric(12,3);
    v_account_payable_id uuid;
    v_account_payable_type_id int;
    v_due_date date;
BEGIN
    -- Obtener tenant_id desde la relación supplier -> supplier_branch -> branch
    select s.added_by into v_tenant_id
    from purchase_schema.supplier s
    where s.supplier_id = p_supplier_id
    limit 1;

    if v_tenant_id is null then
        raise exception 'Cannot determine tenant_id for supplier %', p_supplier_id;
    end if;

    -- Crear la orden de compra
    INSERT INTO purchase_schema.purchase_order(
        supplier_id,
        warehouse_id,
        expected_delivery_date,
        purchase_order_status_id
    ) VALUES (
        p_supplier_id,
        p_warehouse_id,
        p_expected_delivery_date,
        1  -- Pending
    ) returning purchase_order_id into v_purchase_order_id;

    -- Insertar items si se proporcionaron
    if p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
        for v_item in select value from jsonb_array_elements(p_items)
        loop
            v_product_id := (v_item ->> 'product_variant_id')::uuid;
            v_qty := coalesce((v_item ->> 'quantity_ordered')::int, 0);
            v_unit := coalesce((v_item ->> 'unit_price')::numeric, 0);

            INSERT INTO purchase_schema.purchase_order_item(
                purchase_order_id,
                tenant_id,
                product_variant_id,
                quantity_ordered,
                unit_price
            ) VALUES (
                v_purchase_order_id,
                v_tenant_id,
                v_product_id,
                v_qty,
                v_unit
            );
        end loop;

        -- ✅ MC1: Actualizar supplier_id en product_variant si no tiene proveedor asignado
        UPDATE general_schema.product_variant
        SET
            supplier_id = p_supplier_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE
            tenant_id = v_tenant_id
            AND product_variant_id IN (
                SELECT (value ->> 'product_variant_id')::uuid
                FROM jsonb_array_elements(p_items)
            )
            AND supplier_id IS NULL;

        -- ✅ MC1 (Extended): Si el producto es compuesto, heredar supplier_id a componentes
        UPDATE general_schema.product_variant child
        SET
            supplier_id = p_supplier_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE
            child.tenant_id = v_tenant_id
            AND child.supplier_id IS NULL
            AND child.product_variant_id IN (
                SELECT pvc.child_product_variant_id
                FROM general_schema.product_variant_composition pvc
                WHERE pvc.tenant_id = v_tenant_id
                  AND pvc.parent_product_variant_id IN (
                      SELECT (value ->> 'product_variant_id')::uuid
                      FROM jsonb_array_elements(p_items)
                  )
            );
    end if;

    -- Calcular subtotal de la orden
    v_subtotal := coalesce(purchase_schema.calculate_purchase_order_total(v_purchase_order_id), 0);

    -- Obtener tasa de impuesto del tenant (fallback: IVA General VE 16%)
    select coalesce(tr.rate_percentage, 16.00) into v_tax_rate
    from general_schema.tenant t
    left join general_schema.tax_rate tr on tr.region_id = t.region_id
    where t.tenant_id = v_tenant_id
    limit 1;

    -- Calcular impuesto
    v_tax_amount := round(v_subtotal * (v_tax_rate / 100.0), 3);

    -- Calcular fecha de vencimiento (30 días por defecto)
    v_due_date := (current_date + interval '30 days')::date;

    -- Obtener el ID del tipo de cuenta por pagar 'goods_purchase'
    select account_payable_type_id into v_account_payable_type_id
    from general_schema.account_payable_type
    where type_name = 'goods_purchase'
    limit 1;

    if v_account_payable_type_id is null then
        raise exception 'Account payable type "goods_purchase" not found';
    end if;

    -- ✅ PASO 1: Crear registro en la tabla PADRE (general_schema.account_payable)
    INSERT INTO general_schema.account_payable(
        account_payable_type_id,
        has_invoice,
        has_tax,
        subtotal,
        amount_paid,
        is_paid,
        due_date
    ) VALUES (
        v_account_payable_type_id,
        p_has_invoice,
        true,
        v_subtotal,
        0,
        false,
        v_due_date
    ) returning account_payable_id into v_account_payable_id;

    -- ✅ PASO 2: Crear registro en la tabla HIJA (purchase_account_payable)
    INSERT INTO purchase_schema.purchase_account_payable(
        account_payable_id,
        purchase_order_id,
        tax_amount,
        account_payable_status
    ) VALUES (
        v_account_payable_id,
        v_purchase_order_id,
        v_tax_amount,
        1  -- Pending
    );

    -- Crear factura si se requiere
    if p_has_invoice then
        INSERT INTO purchase_schema.supplier_invoice(
            purchase_order_id,
            invoice_number,
            invoice_date,
            payment_condition,
            due_date,
            subtotal_amount,
            tax_rate
        ) VALUES (
            v_purchase_order_id,
            'INV-' || to_char(current_timestamp, 'YYYYMMDD-HH24MISS') || '-' || substring(v_purchase_order_id::text, 1, 8),
            current_timestamp,
            p_payment_condition,
            v_due_date,
            v_subtotal,
            v_tax_rate
        ) returning supplier_invoice_id into v_supplier_invoice_id;

        -- Crear items de factura desde los items de la orden
        INSERT INTO purchase_schema.supplier_invoice_item(
            supplier_invoice_id,
            tenant_id,
            product_variant_id,
            quantity_billed,
            unit_price
        )
        select
            v_supplier_invoice_id,
            tenant_id,
            product_variant_id,
            quantity_ordered,
            unit_price
        from purchase_schema.purchase_order_item
        where purchase_order_id = v_purchase_order_id;
    end if;

    return v_purchase_order_id;
end;
$$ language plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- ALTER TABLE purchase_schema.supplier_invoice ALTER COLUMN tax_rate SET DEFAULT 13.00;
-- ALTER TABLE purchase_schema.purchase_order_payment ALTER COLUMN currency_id SET DEFAULT 1;
-- (restaurar create_purchase_order() a la version anterior: fallback tax_rate 13.00,
--  ver git history de functions/purchase/purchase_functions.sql previo a esta migracion)
