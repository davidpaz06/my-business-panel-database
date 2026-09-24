-- Migration: 002-add-payment-due-date
-- What: Adds purchase_order.payment_due_date (nullable date). When the order
--       is created with payment_condition = 'CREDIT', create_purchase_order()
--       now requires p_payment_due_date and uses it (instead of the old
--       hardcoded current_date + 30 days) for both
--       general_schema.account_payable.due_date and
--       purchase_schema.supplier_invoice.due_date. IN_FULL orders settle
--       immediately, so their due_date becomes current_date.
-- Why:  MBP_Cambios_CR_a_Venezuela.md seccion 3: "Fecha limite de pago (nueva
--       orden): Campo obligatorio de fecha limite de pago cuando la condicion
--       de pago sea 'credito'".
-- Context: Fase 2 del plan de migracion del modulo de Compras. Column check
--       de obligatoriedad se deja a backend/frontend (no CHECK a nivel DB)
--       para no bloquear datos legados sin este campo.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE purchase_schema.purchase_order
    ADD COLUMN IF NOT EXISTS payment_due_date date;

COMMENT ON COLUMN purchase_schema.purchase_order.payment_due_date IS
    'Fecha limite de pago capturada en la creacion de la orden. Obligatoria cuando payment_condition = CREDIT (validado en backend/frontend, no via CHECK para no romper datos legados). Ignorada/NULL para IN_FULL.';

CREATE OR REPLACE FUNCTION purchase_schema.create_purchase_order(p_supplier_id uuid, p_warehouse_id uuid, p_expected_delivery_date date, p_items jsonb default '[]'::jsonb, p_has_invoice BOOLEAN default true, p_payment_condition VARCHAR(10) default 'CREDIT', p_payment_due_date date default null) returns uuid as $$
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

    v_subtotal := coalesce(purchase_schema.calculate_purchase_order_total(v_purchase_order_id), 0);

    select coalesce(tr.rate_percentage, 16.00) into v_tax_rate
    from general_schema.tenant t
    left join general_schema.tax_rate tr on tr.region_id = t.region_id
    where t.tenant_id = v_tenant_id
    limit 1;

    v_tax_amount := round(v_subtotal * (v_tax_rate / 100.0), 3);

    -- Fecha de vencimiento: la capturada en la orden si es CREDIT; pago de
    -- una vez (IN_FULL) vence el mismo dia.
    if p_payment_condition = 'CREDIT' then
        v_due_date := p_payment_due_date;
    else
        v_due_date := current_date;
    end if;

    select account_payable_type_id into v_account_payable_type_id
    from general_schema.account_payable_type
    where type_name = 'goods_purchase'
    limit 1;

    if v_account_payable_type_id is null then
        raise exception 'Account payable type "goods_purchase" not found';
    end if;

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
-- ALTER TABLE purchase_schema.purchase_order DROP COLUMN IF EXISTS payment_due_date;
-- (restaurar create_purchase_order() a la version de 001-purchase-usd-base-currency-and-ve-tax-default.sql)
