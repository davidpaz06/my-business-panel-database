-- Migration: 043-supplier-invoice-edit-iva-included
-- What: purchase_schema.update_supplier_invoice() deja de sumar IVA sobre el
--       costo al editar la factura del proveedor. Los items de la factura
--       cargan unit_price con el costo (que ya incluye IVA), pero
--       supplier_invoice.subtotal_amount es la BASE: tax_amount y total_amount
--       son columnas generadas que suman el IVA encima. La funcion guardaba
--       subtotal_amount = suma de items (bruto), asi que la factura editada
--       quedaba con bruto * (1 + tasa) y el three-way matching abria una
--       disputa de monto falsa. Ahora subtotal_amount = bruto / (1 + tasa de la
--       factura), igual que create_purchase_order() (migracion 041).
-- Why:  Misma causa que la 041 (IVA doble en compras), en la ruta de edicion de
--       factura que la 041 no cubria.
-- Context: Solo aplica a ediciones posteriores; las facturas ya editadas no se
--       recalculan. Version previa: 004-update-supplier-invoice-function.sql.

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
    v_tax_rate numeric(5,2);
begin
    select si.purchase_order_id, po.purchase_order_status_id, si.tax_rate
      into v_purchase_order_id, v_status_id, v_tax_rate
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

    -- unit_price es el costo con IVA incluido (igual que en la orden), asi que
    -- subtotal_amount guarda la base: tax_amount y total_amount son columnas
    -- generadas que suman el IVA sobre subtotal_amount.
    update purchase_schema.supplier_invoice
       set subtotal_amount = round(v_subtotal::numeric / (1 + v_tax_rate / 100.0), 3),
           updated_at = current_timestamp
     where supplier_invoice_id = p_supplier_invoice_id;
end;
$$ language plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- (restaurar update_supplier_invoice() a la version de
--  004-update-supplier-invoice-function.sql: subtotal_amount =
--  round(v_subtotal::numeric, 3) sin dividir entre (1 + tasa))
