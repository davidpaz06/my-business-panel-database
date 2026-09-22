-- ============================================================
-- Migration: 031-reconcile-ar-on-return
-- Schema: pos
-- Date: 2026-09-22
-- Author: Claude (session work)
--
-- Why: auditoria de ventas a credito (readaptacion Venezuela) encontro que
-- devolver mercancia de una venta a credito/apartado NUNCA ajustaba
-- general_schema.account_receivable -- ni el trigger update_on_return
-- (reembolso parcial, via return_product) ni processFullRefund (reembolso
-- total, via sale.is_refunded) tocaban la cuenta por cobrar. Un cliente que
-- compraba a credito y devolvia mercancia seguia debiendo el monto
-- original completo indefinidamente, sin forma de reconciliar salvo a
-- mano en la DB.
--
-- What:
-- 1. update_on_return() (CREATE OR REPLACE, ya existe) gana un bloque que,
--    si la venta tiene una cuenta por cobrar asociada, recalcula
--    account_receivable.subtotal y sale_account_receivable.tax_amount a
--    partir de los mismos totales recien recalculados de la venta
--    (_sale_subtotal_after / _sale_tax_after), y llama a la funcion ya
--    existente check_account_receivable_completion() para que is_paid y
--    el status sigan el mismo camino que usa el trigger de cobros.
-- 2. Trigger nuevo cancel_ar_on_full_refund_trigger sobre
--    pos_schema.sale: cuando is_refunded pasa a TRUE (reembolso total,
--    processFullRefund no inserta return_product por lo que (1) nunca se
--    dispara), cierra la cuenta por cobrar dejando subtotal = amount_paid
--    (saldo en cero) via el mismo check_account_receivable_completion().
--    No se agrega un status "cancelada" nuevo -- se reusa is_paid=TRUE
--    para no expandir el catalogo de status a mitad de esta migracion;
--    revisar si hace falta distinguir "pagada" de "anulada" en una
--    iteracion futura si el negocio lo pide.
--
-- Bug adicional encontrado al verificar esta migracion: update_on_return()
-- seguia en su version PRE-rename (Costa Rica -> Venezuela), referenciando
-- digital_sale_invoice/digital_sale_invoice_item -- tablas eliminadas por
-- migrations/pos/021-rename-digital-invoice-to-invoice.sql. El archivo
-- fuente (functions/pos/pos_functions.sql) ya tenia la version corregida,
-- pero nunca se habia re-aplicado a esta base -- toda devolucion parcial
-- fallaba con "relation pos_schema.digital_sale_invoice does not exist".
-- El CREATE OR REPLACE de abajo, con los nombres de tabla ya correctos,
-- corrige tambien esto de paso.
--
-- IMPORTANTE: funciones y triggers estan explicitamente calificados con
-- pos_schema. -- correr este archivo suelto (fuera de
-- functions/pos/pos_functions.sql, que sí trae `set search_path = pos_schema`
-- en su cabecera) sin el prefijo deja las funciones en `public`, no en
-- pos_schema, y el trigger real (ligado a pos_schema.update_on_return)
-- queda intacto en su version vieja. Aprendido en carne propia corriendo
-- esta misma migracion.
-- ============================================================

SET search_path = pos_schema;

CREATE OR REPLACE FUNCTION pos_schema.update_on_return()
returns trigger as $$
declare
    _sale_item_record record;
    _invoice_id uuid;
    _sale_id uuid;
    _total_returned numeric(10,2) := 0;
    _new_subtotal numeric(10,2);
    _new_tax numeric(10,2);
    _new_total numeric(10,2);
    _quantity_remaining INTEGER;
    _sale_subtotal_after numeric(10,2);
    _sale_tax_after numeric(10,2);
    _ar_id uuid;
BEGIN
    select
        si.sale_item_id,
        si.sale_id,
        si.quantity,
        si.unit_price,
        si.total_price,
        si.product_variant_id,
        si.tenant_id
    into _sale_item_record
    from pos_schema.sale_item si
    where si.sale_item_id = new.sale_item_id;

    if not found then
        raise exception 'Sale item not found: %', new.sale_item_id;
    end if;

    _sale_id := _sale_item_record.sale_id;

    -- get invoice for sale
    select invoice_id into _invoice_id from pos_schema.invoice where sale_id = _sale_id limit 1;
    if _invoice_id is null then
        raise exception 'Invoice not found for sale: %', _sale_id;
    end if;

    raise notice 'Invoice ID: %', _invoice_id;
    raise notice 'Original sale item: qty=% unit=$% total=$%', _sale_item_record.quantity, _sale_item_record.unit_price, _sale_item_record.total_price;

    if new.quantity > _sale_item_record.quantity then
        raise exception 'Cannot return more items than purchased. Purchased: %, Attempting to return: %',
            _sale_item_record.quantity, new.quantity;
    end if;

    _quantity_remaining := _sale_item_record.quantity - new.quantity;
    raise notice 'Return quantity: %  Remaining qty: %', new.quantity, _quantity_remaining;

    -- Update or remove sale_item (CASCADE deletes invoice_item if qty = 0)
    if _quantity_remaining = 0 then
        -- First, explicitly delete the corresponding invoice_item to ensure clean state
        delete from pos_schema.invoice_item
        where invoice_id = _invoice_id
        and sale_item_id = _sale_item_record.sale_item_id;

        delete from pos_schema.sale_item where sale_item_id = _sale_item_record.sale_item_id;
        raise notice 'Sale item removed (quantity = 0)';
    else
        update pos_schema.sale_item
        set quantity = _quantity_remaining,
            total_price = _quantity_remaining * unit_price,
            updated_at = current_timestamp
        where sale_item_id = _sale_item_record.sale_item_id;
        raise notice 'Sale item quantity updated from % to %', _sale_item_record.quantity, _quantity_remaining;

        -- Update corresponding invoice_item with correct tax rate
        -- Resolve tax_rate the same way as create_invoice
        update pos_schema.invoice_item dii
        set quantity = _quantity_remaining,
            subtotal = _quantity_remaining * dii.unit_price,
            tax_rate_percentage = COALESCE(tr.rate_percentage, 0),
            tax_amount = ROUND((_quantity_remaining * dii.unit_price) * COALESCE(tr.rate_percentage, 0) / 100, 2),
            total_price = (_quantity_remaining * dii.unit_price)
                + ROUND((_quantity_remaining * dii.unit_price) * COALESCE(tr.rate_percentage, 0) / 100, 2),
            updated_at = current_timestamp
        from general_schema.product_variant pv
        left join general_schema.product p ON pv.product_id = p.product_id
        left join general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
        where dii.invoice_id = _invoice_id
        and dii.sale_item_id = _sale_item_record.sale_item_id
        and dii.tenant_id = pv.tenant_id
        and dii.product_variant_id = pv.product_variant_id;
    end if;

    -- Recalculate invoice totals from remaining items
    SELECT
        COALESCE(SUM(ii.subtotal), 0),
        COALESCE(SUM(ii.tax_amount), 0),
        COALESCE(SUM(ii.total_price), 0)
    INTO _new_subtotal, _new_tax, _new_total
    FROM pos_schema.invoice_item ii
    WHERE ii.invoice_id = _invoice_id;

    update pos_schema.invoice
    set subtotal_amount = _new_subtotal,
        tax_amount = _new_tax,
        total_amount = _new_total,
        updated_at = current_timestamp
    where invoice_id = _invoice_id;

    raise notice 'Invoice updated: subtotal $% tax $% total $%', _new_subtotal, _new_tax, _new_total;

    -- Recalculate sale totals from remaining sale_items with per-item tax
    SELECT
        COALESCE(SUM(si.total_price), 0),
        COALESCE(SUM(ROUND(si.total_price * COALESCE(tr.rate_percentage, 0) / 100, 2)), 0)
    INTO _sale_subtotal_after, _sale_tax_after
    FROM pos_schema.sale_item si
    JOIN general_schema.product_variant pv
        ON si.tenant_id = pv.tenant_id AND si.product_variant_id = pv.product_variant_id
    LEFT JOIN general_schema.product p ON pv.product_id = p.product_id
    LEFT JOIN general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
    WHERE si.sale_id = _sale_id;

    _new_total := _sale_subtotal_after + _sale_tax_after;

    update pos_schema.sale
    set subtotal_amount = _sale_subtotal_after,
        tax_amount = _sale_tax_after,
        total_amount = _new_total,
        updated_at = current_timestamp
    where sale_id = _sale_id;

    raise notice 'Sale updated: subtotal $% tax $% total $%', _sale_subtotal_after, _sale_tax_after, _new_total;

    -- ── Reconciliar cuenta por cobrar (Bug #3, auditoria VE) ──────────────
    -- Si la venta es a credito/apartado y tiene una cuenta por cobrar
    -- abierta, la devolucion debe reducir lo que el cliente todavia debe,
    -- no solo el total de la factura/venta.
    select ar.account_receivable_id into _ar_id
    from general_schema.account_receivable ar
    join pos_schema.sale_account_receivable sar
        on sar.account_receivable_id = ar.account_receivable_id
    where sar.sale_id = _sale_id;

    if _ar_id is not null then
        update general_schema.account_receivable
        set subtotal = _sale_subtotal_after,
            updated_at = current_timestamp
        where account_receivable_id = _ar_id;

        update pos_schema.sale_account_receivable
        set tax_amount = _sale_tax_after,
            updated_at = current_timestamp
        where account_receivable_id = _ar_id;

        perform pos_schema.check_account_receivable_completion(_ar_id);

        raise notice 'Account receivable % reconciled after return: new subtotal $%, new tax $%', _ar_id, _sale_subtotal_after, _sale_tax_after;
    end if;

    return new;
end;
$$ language plpgsql;

-- update_on_return_trigger ya existe (creado en pos_functions.sql original);
-- CREATE OR REPLACE de la funcion es suficiente, no hace falta recrear el trigger.

-- ── Reembolso total: processFullRefund no inserta return_product, por lo
-- que el trigger de arriba nunca se dispara. Se cierra la cuenta por
-- cobrar directamente cuando sale.is_refunded pasa a TRUE.
CREATE OR REPLACE FUNCTION pos_schema.cancel_account_receivable_on_full_refund()
RETURNS TRIGGER AS $$
DECLARE
    _ar_id uuid;
BEGIN
    IF NEW.is_refunded = TRUE AND (OLD.is_refunded IS DISTINCT FROM TRUE) THEN
        SELECT ar.account_receivable_id INTO _ar_id
        FROM general_schema.account_receivable ar
        JOIN pos_schema.sale_account_receivable sar
            ON sar.account_receivable_id = ar.account_receivable_id
        WHERE sar.sale_id = NEW.sale_id;

        IF _ar_id IS NOT NULL THEN
            UPDATE general_schema.account_receivable
            SET subtotal = amount_paid,
                updated_at = CURRENT_TIMESTAMP
            WHERE account_receivable_id = _ar_id;

            UPDATE pos_schema.sale_account_receivable
            SET tax_amount = 0,
                updated_at = CURRENT_TIMESTAMP
            WHERE account_receivable_id = _ar_id;

            PERFORM pos_schema.check_account_receivable_completion(_ar_id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS cancel_ar_on_full_refund_trigger ON pos_schema.sale;
CREATE TRIGGER cancel_ar_on_full_refund_trigger
AFTER UPDATE OF is_refunded ON pos_schema.sale
FOR EACH ROW
EXECUTE FUNCTION pos_schema.cancel_account_receivable_on_full_refund();

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP TRIGGER IF EXISTS cancel_ar_on_full_refund_trigger ON pos_schema.sale;
-- DROP FUNCTION IF EXISTS cancel_account_receivable_on_full_refund();
-- Restaurar update_on_return() a la version sin el bloque de reconciliacion
-- de account_receivable (ver functions/pos/pos_functions.sql en el commit
-- anterior a esta migracion).
