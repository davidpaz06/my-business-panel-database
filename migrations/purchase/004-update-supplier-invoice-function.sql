-- Migration: 004-update-supplier-invoice-function
-- What: New function purchase_schema.update_supplier_invoice(p_supplier_invoice_id,
--       p_items, p_tenant_id) that replaces a supplier_invoice's items and
--       recalculates subtotal_amount, but only while the associated
--       purchase_order is in status 2 (Shipped / "enviada"). Raises if the
--       order is in any other status (in particular 3 / Delivered / "entregada").
-- Why:  MBP_Cambios_CR_a_Venezuela.md seccion 3: "Edicion de facturas de
--       compra: Editable mientras la orden esta en estado 'enviada'; se
--       bloquea la edicion al marcarse como 'entregada'."
-- Context: Fase 4 del plan de migracion del modulo de Compras. Reusa
--       purchase_order_status existente (no crea status nuevo en
--       supplier_invoice), decision confirmada con el usuario.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION purchase_schema.update_supplier_invoice(p_supplier_invoice_id uuid, p_items jsonb, p_tenant_id uuid) returns void as $$
declare
    v_purchase_order_id uuid;
    v_status_id int;
    v_item jsonb;
    v_product_id uuid;
    v_qty INTEGER;
    v_unit numeric(12,3);
    v_subtotal numeric(12,3);
begin
    select si.purchase_order_id, po.purchase_order_status_id
      into v_purchase_order_id, v_status_id
    from purchase_schema.supplier_invoice si
    join purchase_schema.purchase_order po on po.purchase_order_id = si.purchase_order_id
    where si.supplier_invoice_id = p_supplier_invoice_id;

    if v_purchase_order_id is null then
        raise exception 'supplier_invoice % not found', p_supplier_invoice_id;
    end if;

    if v_status_id is distinct from 2 then
        raise exception 'supplier_invoice % cannot be edited: purchase_order_status_id is %, only status 2 (Shipped/enviada) allows edits', p_supplier_invoice_id, v_status_id;
    end if;

    delete from purchase_schema.supplier_invoice_item
    where supplier_invoice_id = p_supplier_invoice_id;

    if p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
        for v_item in select value from jsonb_array_elements(p_items)
        loop
            v_product_id := (v_item ->> 'product_variant_id')::uuid;
            v_qty := coalesce((v_item ->> 'quantity_billed')::int, 0);
            v_unit := coalesce((v_item ->> 'unit_price')::numeric, 0);

            INSERT INTO purchase_schema.supplier_invoice_item(
                supplier_invoice_id,
                tenant_id,
                product_variant_id,
                quantity_billed,
                unit_price
            ) VALUES (
                p_supplier_invoice_id,
                p_tenant_id,
                v_product_id,
                v_qty,
                v_unit
            );
        end loop;
    end if;

    select coalesce(sum(quantity_billed * unit_price), 0)
      into v_subtotal
    from purchase_schema.supplier_invoice_item
    where supplier_invoice_id = p_supplier_invoice_id;

    update purchase_schema.supplier_invoice
       set subtotal_amount = round(v_subtotal::numeric, 3),
           updated_at = current_timestamp
     where supplier_invoice_id = p_supplier_invoice_id;
end;
$$ language plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP FUNCTION IF EXISTS purchase_schema.update_supplier_invoice(uuid, jsonb, uuid);
