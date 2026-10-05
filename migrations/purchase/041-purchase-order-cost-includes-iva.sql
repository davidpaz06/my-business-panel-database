-- Migration: 041-purchase-order-cost-includes-iva
-- What: create_purchase_order() deja de sumar IVA sobre el costo del producto.
--       El costo (general_schema.product_variant.cost_price) ya incluye IVA, asi
--       que ahora el total de la orden es la suma de costos tal cual y el IVA
--       se desglosa: base (account_payable.subtotal) = bruto / (1 + tasa),
--       iva (purchase_account_payable.tax_amount) = bruto - base.
--       supplier_invoice.subtotal_amount guarda la misma base.
--       Ademas, la tasa se elige de forma determinista (la mayor de la region
--       del tenant, descartando Exento 0%); antes el limit 1 sin ORDER BY podia
--       tomar cualquier fila de tax_rate de la region.
-- Why:  Reporte de cliente: las compras cobraban el IVA dos veces (13% -> ~26%
--       efectivo) porque se sumaba IVA a un costo que ya lo traia incluido.
-- Context: Solo aplica a ordenes creadas despues de esta migracion; las ordenes
--       existentes no se recalculan. Ultima modificacion previa de la funcion:
--       003-purchase-order-item-cost-from-product.sql.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION purchase_schema.create_purchase_order(p_supplier_id uuid, p_warehouse_id uuid, p_expected_delivery_date date, p_items jsonb default '[]'::jsonb, p_has_invoice BOOLEAN default true, p_payment_condition VARCHAR(10) default 'CREDIT', p_payment_due_date date default null) returns uuid as $$
declare
    v_purchase_order_id uuid;
    v_supplier_invoice_id uuid;
    v_item jsonb;
    v_tenant_id uuid;
    v_product_id uuid;
    v_qty INTEGER;
    v_unit numeric(12,3);
    v_gross numeric(12,3);
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

    if p_payment_condition = 'CREDIT' and p_payment_due_date is null then
        raise exception 'payment_due_date is required when payment_condition is CREDIT';
    end if;

    -- Crear la orden de compra
    INSERT INTO purchase_schema.purchase_order(
        supplier_id,
        warehouse_id,
        expected_delivery_date,
        purchase_order_status_id,
        payment_due_date
    ) VALUES (
        p_supplier_id,
        p_warehouse_id,
        p_expected_delivery_date,
        1,  -- Pending
        p_payment_due_date
    ) returning purchase_order_id into v_purchase_order_id;

    -- Insertar items si se proporcionaron
    if p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
        for v_item in select value from jsonb_array_elements(p_items)
        loop
            v_product_id := (v_item ->> 'product_variant_id')::uuid;
            v_qty := coalesce((v_item ->> 'quantity_ordered')::int, 0);

            -- Costo resuelto server-side desde el catalogo (ignora cualquier
            -- unit_price que venga en el payload del cliente).
            select cost_price into v_unit
            from general_schema.product_variant
            where tenant_id = v_tenant_id
              and product_variant_id = v_product_id;

            if v_unit is null then
                raise exception 'product_variant % not found for tenant %', v_product_id, v_tenant_id;
            end if;

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
        -- Para cada product_variant que se está comprando y que no tiene supplier_id,
        -- asignar el supplier_id de esta orden de compra
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
        -- Para cada producto compuesto que recibió supplier_id, asignar el mismo supplier_id
        -- a todos sus componentes que no tengan proveedor asignado
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

    -- El costo del producto (product_variant.cost_price) ya incluye IVA, por lo
    -- que el total de la orden es la suma de costos tal cual. El IVA se
    -- desglosa, no se suma: base = bruto / (1 + tasa), iva = bruto - base.
    v_gross := coalesce(purchase_schema.calculate_purchase_order_total(v_purchase_order_id), 0);

    -- Tasa general del tenant: la mayor de su region (descarta la tarifa
    -- Exento 0%; sin ORDER BY el limit 1 elegia una fila arbitraria).
    -- Fallback: IVA General VE 16%.
    select coalesce(tr.rate_percentage, 16.00) into v_tax_rate
    from general_schema.tenant t
    left join general_schema.tax_rate tr on tr.region_id = t.region_id
    where t.tenant_id = v_tenant_id
    order by tr.rate_percentage desc nulls last
    limit 1;

    v_subtotal := round(v_gross / (1 + v_tax_rate / 100.0), 3);
    v_tax_amount := v_gross - v_subtotal;

    -- Fecha de vencimiento: la capturada en la orden si es CREDIT; pago de
    -- una vez (IN_FULL) vence el mismo dia.
    if p_payment_condition = 'CREDIT' then
        v_due_date := p_payment_due_date;
    else
        v_due_date := current_date;
    end if;

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
        true,  -- Las órdenes de suministro siempre tienen impuesto
        v_subtotal,
        0,  -- Inicial
        false,  -- Inicial
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
-- (restaurar create_purchase_order() a la version de
--  003-purchase-order-item-cost-from-product.sql, que sumaba el IVA sobre el
--  costo: v_subtotal = suma de costos y v_tax_amount = v_subtotal * tasa)
