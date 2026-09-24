-- Migration: 006-auto-create-payment-alert-on-invoice
-- What: New trigger AFTER INSERT ON supplier_invoice that automatically
--       creates an initial "Upcoming Due Date" payment alert when a CREDIT
--       invoice is emitted, using the tenant's configured
--       warning_days_before_due (or a 7-day fallback if the tenant has no
--       purchase_order_payment_alert_config row yet). IN_FULL invoices don't
--       generate an alert (nothing to chase). generate_payment_alerts()
--       (manual/batch) is untouched and stays available for reprocessing.
-- Why:  MBP_Cambios_CR_a_Venezuela.md seccion 3: "Alerta / calendario de
--       factura: Se genera automaticamente en el calendario de facturas
--       apenas se emite la factura."
-- Context: Fase 7 del plan de migracion del modulo de Compras. Tenant se
--       resuelve via purchase_order -> warehouse -> branch -> tenant, mismo
--       patron usado por el backend (getAccessById en purchase.service.ts).

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION purchase_schema.create_initial_payment_alert() returns trigger as $$
declare
    v_tenant_id uuid;
    v_purchase_account_payable_id uuid;
    v_warning_days int;
    v_alert_type_id int;
    v_alert_date timestamp;
begin
    if NEW.payment_condition is distinct from 'CREDIT' then
        return NEW;
    end if;

    select b.tenant_id into v_tenant_id
    from purchase_schema.purchase_order po
    join inventory_schema.warehouse w on w.warehouse_id = po.warehouse_id
    join general_schema.branch b on b.branch_id = w.branch_id
    where po.purchase_order_id = NEW.purchase_order_id;

    if v_tenant_id is null then
        return NEW;
    end if;

    select pap.purchase_account_payable_id into v_purchase_account_payable_id
    from purchase_schema.purchase_account_payable pap
    where pap.purchase_order_id = NEW.purchase_order_id;

    if v_purchase_account_payable_id is null then
        return NEW;
    end if;

    select coalesce(c.warning_days_before_due, 7) into v_warning_days
    from purchase_schema.purchase_order_payment_alert_config c
    where c.tenant_id = v_tenant_id;

    if v_warning_days is null then
        v_warning_days := 7;
    end if;

    select payment_alert_type_id into v_alert_type_id
    from purchase_schema.purchase_order_payment_alert_type
    where payment_alert_type_name = 'Upcoming Due Date'
    limit 1;

    if v_alert_type_id is null then
        return NEW;
    end if;

    v_alert_date := coalesce(NEW.due_date, current_date) - (v_warning_days || ' days')::interval;

    INSERT INTO purchase_schema.purchase_order_payment_alert(
        purchase_account_payable_id,
        payment_alert_type_id,
        alert_date,
        is_resolved
    ) VALUES (
        v_purchase_account_payable_id,
        v_alert_type_id,
        v_alert_date,
        false
    );

    return NEW;
end;
$$ language plpgsql;

DROP TRIGGER IF EXISTS create_initial_payment_alert_trigger ON purchase_schema.supplier_invoice;
CREATE TRIGGER create_initial_payment_alert_trigger
AFTER INSERT ON purchase_schema.supplier_invoice
FOR EACH ROW EXECUTE FUNCTION purchase_schema.create_initial_payment_alert();

COMMENT ON FUNCTION purchase_schema.create_initial_payment_alert() IS
    'Crea automaticamente la alerta inicial de pago (Upcoming Due Date) al emitir una factura CREDIT. No reemplaza generate_payment_alerts(), que sigue disponible para reproceso/backfill manual.';

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP TRIGGER IF EXISTS create_initial_payment_alert_trigger ON purchase_schema.supplier_invoice;
-- DROP FUNCTION IF EXISTS purchase_schema.create_initial_payment_alert();
