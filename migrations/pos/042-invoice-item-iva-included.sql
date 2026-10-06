-- Migration: 042-invoice-item-iva-included
-- What: las lineas de factura (pos_schema.invoice_item) respetan
--       product_variant.includes_iva. Si el precio de venta ya incluye IVA, la
--       linea desglosa el impuesto (base = total / (1 + tasa), iva = total - base,
--       total = el precio cobrado) en lugar de sumarlo encima. Antes la linea
--       siempre calculaba total + total * tasa, asi que un producto con IVA
--       incluido se facturaba con el IVA doble aunque la venta lo cobrara bien.
--       * Nueva funcion pos_schema.invoice_item_amounts(): unica formula del
--         desglose, usada por las tres rutas que escriben lineas de factura.
--       * pos_schema.create_invoice(): ruta de respaldo del trigger de venta.
--       * pos_schema.update_on_return(): recalculo de la linea tras una
--         devolucion, y recalculo del IVA de la venta (el IVA de venta solo se
--         suma encima en items sin IVA incluido, igual que el POS).
--       * La ruta principal (INSERT desde sale.service via pos.queries.ts
--         createItemsFromSale) usa la misma funcion; backend y esta migracion
--         se despliegan juntos y la migracion va primero.
-- Why:  Hallazgo al revisar el IVA de GIN TONIC (includes_iva = true): venta y
--       POS cobraban 2 x 1.000 = 2.000 pero la factura salia con IVA encima.
-- Context: Solo afecta facturas y devoluciones nuevas; las facturas existentes
--       no se recalculan (sin backfill). Ultimas versiones previas:
--       040-invoice-number-and-required-customer.sql (create_invoice) y
--       031-reconcile-ar-on-return.sql (update_on_return).

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

SET SEARCH_PATH TO pos_schema;

-- Desglose de IVA de una linea de factura. p_includes_iva = true: el monto ya
-- trae el IVA (product_variant.includes_iva), asi que se desglosa:
-- base = monto / (1 + tasa), iva = monto - base, y base + iva = monto.
-- false: el IVA se suma encima: base = monto, iva = monto * tasa.
CREATE OR REPLACE FUNCTION pos_schema.invoice_item_amounts(p_amount numeric, p_rate numeric, p_includes_iva boolean)
RETURNS TABLE(item_subtotal numeric, item_tax_amount numeric, item_total numeric) AS $$
    SELECT b.base, b.tax, b.base + b.tax
    FROM (
        SELECT
            CASE WHEN COALESCE(p_includes_iva, false)
                 THEN ROUND(p_amount / (1 + COALESCE(p_rate, 0) / 100.0), 2)
                 ELSE p_amount END AS base,
            CASE WHEN COALESCE(p_includes_iva, false)
                 THEN p_amount - ROUND(p_amount / (1 + COALESCE(p_rate, 0) / 100.0), 2)
                 ELSE ROUND(p_amount * COALESCE(p_rate, 0) / 100.0, 2) END AS tax
    ) b;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION pos_schema.create_invoice()
returns trigger as $$
declare
    _invoice_id uuid;
    _tenant_customer_id uuid;
    _currency_id INTEGER;
    _subtotal numeric(10,2);
    _tax numeric(10,2);
    _total numeric(10,2);
    _payment_ids uuid[];
    _cash_register_session_id uuid;
    _items_count int;
BEGIN
        raise notice 'Creating invoice for sale: %', new.sale_id;

        if exists(
            select 1 from pos_schema.invoice
            where sale_id = new.sale_id
        ) then
            raise notice 'Invoice already exists for sale: %', new.sale_id;
            return new;
        end if;

        -- Cliente desde la venta; el pago solo sirve de respaldo para ventas
        -- pendientes historicas que se crearon sin cliente.
        _tenant_customer_id := COALESCE(
            new.tenant_customer_id,
            (
                select tenant_customer_id
                from pos_schema.customer_payment
                where sale_id = new.sale_id
                  and tenant_customer_id is not null
                limit 1
            )
        );

        _currency_id := new.currency_id;

        -- Resolve active cash register session in the branch
        SELECT crs.cash_register_session_id INTO _cash_register_session_id
        FROM pos_schema.cash_register_session crs
        JOIN pos_schema.cash_register cr ON crs.cash_register_id = cr.cash_register_id
        WHERE cr.branch_id = new.branch_id
        AND crs.is_active = true
        LIMIT 1;

        -- Insert invoice with placeholder totals (will be updated from items).
        -- trg_invoice_require_customer rechaza cliente nulo y
        -- trg_invoice_assign_number asigna tenant_id e invoice_number.
        INSERT INTO pos_schema.invoice (
            sale_id,
            tenant_customer_id,
            currency_id,
            subtotal_amount,
            tax_amount,
            total_amount,
            cash_register_session_id
        ) VALUES (
            new.sale_id,
            _tenant_customer_id,
            _currency_id,
            0,
            0,
            0,
            _cash_register_session_id
        ) returning invoice_id into _invoice_id;

        raise notice '   Invoice created: %', _invoice_id;
        raise notice '   Cash Register Session: %', _cash_register_session_id;

        INSERT INTO pos_schema.invoice_item (
            invoice_id,
            sale_item_id,
            tenant_id,
            product_variant_id,
            tax_rate_id,
            description,
            quantity,
            unit_price,
            subtotal,
            tax_rate_percentage,
            tax_amount,
            total_price
        )
        SELECT
            _invoice_id,
            si.sale_item_id,
            si.tenant_id,
            si.product_variant_id,
            p.tax_rate_id,
            COALESCE(pv.variant_name, p.product_name, 'Product'),
            si.quantity,
            si.unit_price,
            amt.item_subtotal,
            COALESCE(tr.rate_percentage, 0),
            amt.item_tax_amount,
            amt.item_total
        FROM pos_schema.sale_item si
        JOIN general_schema.product_variant pv
            ON si.tenant_id = pv.tenant_id AND si.product_variant_id = pv.product_variant_id
        LEFT JOIN general_schema.product p ON pv.product_id = p.product_id
        LEFT JOIN general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
        CROSS JOIN LATERAL pos_schema.invoice_item_amounts(
            si.total_price, COALESCE(tr.rate_percentage, 0), pv.includes_iva
        ) amt
        WHERE si.sale_id = new.sale_id;

        GET DIAGNOSTICS _items_count = ROW_COUNT;
        raise notice '   % invoice item(s) created', _items_count;

        -- Update invoice totals from items (per-item tax)
        SELECT
            COALESCE(SUM(ii.subtotal), 0),
            COALESCE(SUM(ii.tax_amount), 0)
        INTO _subtotal, _tax
        FROM pos_schema.invoice_item ii
        WHERE ii.invoice_id = _invoice_id;

        _total := _subtotal + _tax;

        UPDATE pos_schema.invoice
        SET subtotal_amount = _subtotal,
            tax_amount = _tax,
            total_amount = _total
        WHERE invoice_id = _invoice_id;

        raise notice '   Subtotal: $%', _subtotal;
        raise notice '   Tax (per-item): $%', _tax;
        raise notice '   Total: $%', _total;

        -- Link verified payments
        select array_agg(customer_payment_id) into _payment_ids
        from pos_schema.customer_payment
        where sale_id = new.sale_id
        and verified = true;

        INSERT INTO pos_schema.invoice_payment(invoice_id, customer_payment_id, payment_amount)
        select
            _invoice_id,
            customer_payment_id,
            payment_amount
        from pos_schema.customer_payment
        where customer_payment_id = any(_payment_ids);

        raise notice '   % payment(s) linked to invoice', array_length(_payment_ids, 1);
        raise notice '';
        raise notice 'Invoice creation completed successfully';
        raise notice '   Invoice ID: %', _invoice_id;
        raise notice '   Sale ID: %', new.sale_id;

        return new;
end;
$$ language plpgsql;

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
            subtotal = amt.item_subtotal,
            tax_rate_percentage = COALESCE(tr.rate_percentage, 0),
            tax_amount = amt.item_tax_amount,
            total_price = amt.item_total,
            updated_at = current_timestamp
        from general_schema.product_variant pv
        left join general_schema.product p ON pv.product_id = p.product_id
        left join general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
        cross join lateral pos_schema.invoice_item_amounts(
            _quantity_remaining * _sale_item_record.unit_price,
            COALESCE(tr.rate_percentage, 0),
            pv.includes_iva
        ) amt
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
        COALESCE(SUM(
            CASE WHEN pv.includes_iva THEN 0
                 ELSE ROUND(si.total_price * COALESCE(tr.rate_percentage, 0) / 100, 2) END
        ), 0)
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

    -- Reconciliar cuenta por cobrar (Bug #3, auditoria VE): si la venta es
    -- a credito/apartado y tiene una cuenta por cobrar abierta, la
    -- devolucion debe reducir lo que el cliente todavia debe, no solo el
    -- total de la factura/venta.
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

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- (restaurar pos_schema.create_invoice() a la version de
--  040-invoice-number-and-required-customer.sql y pos_schema.update_on_return()
--  a la de 031-reconcile-ar-on-return.sql, que calculaban el IVA de la linea
--  como total * tasa sin mirar includes_iva; despues:)
-- DROP FUNCTION IF EXISTS pos_schema.invoice_item_amounts(numeric, numeric, boolean);
