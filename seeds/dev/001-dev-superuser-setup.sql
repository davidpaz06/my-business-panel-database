-- ============================================================
-- DEV SEED 001 — SUPERUSER SETUP
-- Equivalente SQL de: my-business-panel-backend/test/setup/superuser-setup.http
-- ============================================================
-- PREREQUISITOS:
--   1. bootstrap.sql / database_backup.sql ejecutado
--   2. Todos los seeds de catalog/ ejecutados (segmentos, tasas, monedas,
--      métodos de pago, condiciones de venta, etc.)
--   3. Extensión pgcrypto disponible (para hashing de contraseña)
-- ============================================================
-- UUIDs fijos para reproducibilidad:
--   Tenant       : a0000001-0000-0000-0000-000000000001
--   Branch       : a0000001-0000-0000-0000-000000000002
--   User         : a0000001-0000-0000-0000-000000000003
--   Customer     : a0000001-0000-0000-0000-000000000004
--   CashRegister : a0000001-0000-0000-0000-000000000005
--   CashRegSess  : a0000001-0000-0000-0000-000000000006
--   Variant 1    : a0000001-0000-0000-0000-000000000007
--   Variant 2    : a0000001-0000-0000-0000-000000000008
--   Variant 3    : a0000001-0000-0000-0000-000000000009
--   Warehouse    : a0000001-0000-0000-0000-000000000010
--   Supplier     : a0000001-0000-0000-0000-000000000011
--   PurchaseOrder: a0000001-0000-0000-0000-000000000012
--   Promotion    : a0000001-0000-0000-0000-000000000013
--   LoyalProgram : a0000001-0000-0000-0000-000000000014
--   Sale         : a0000001-0000-0000-0000-000000000015
--   SaleItem     : a0000001-0000-0000-0000-000000000016
--   Payment      : a0000001-0000-0000-0000-000000000017
--   Invoice      : a0000001-0000-0000-0000-000000000018
--   Return       : a0000001-0000-0000-0000-000000000019
--   Paysheet     : a0000001-0000-0000-0000-000000000020
-- ============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_tenant_id        UUID := 'a0000001-0000-0000-0000-000000000001';
  v_branch_id        UUID := 'a0000001-0000-0000-0000-000000000002';
  v_user_id          UUID := 'a0000001-0000-0000-0000-000000000003';
  v_customer_id      UUID := 'a0000001-0000-0000-0000-000000000004';
  v_cash_reg_id      UUID := 'a0000001-0000-0000-0000-000000000005';
  v_cash_reg_sess_id UUID := 'a0000001-0000-0000-0000-000000000006';
  v_variant1_id      UUID := 'a0000001-0000-0000-0000-000000000007';
  v_variant2_id      UUID := 'a0000001-0000-0000-0000-000000000008';
  v_variant3_id      UUID := 'a0000001-0000-0000-0000-000000000009';
  v_warehouse_id     UUID := 'a0000001-0000-0000-0000-000000000010';
  v_supplier_id      UUID := 'a0000001-0000-0000-0000-000000000011';
  v_purchase_id      UUID := 'a0000001-0000-0000-0000-000000000012';
  v_promotion_id     UUID := 'a0000001-0000-0000-0000-000000000013';
  v_loyalty_id       UUID := 'a0000001-0000-0000-0000-000000000014';
  v_sale_id          UUID := 'a0000001-0000-0000-0000-000000000015';
  v_sale_item_id     UUID := 'a0000001-0000-0000-0000-000000000016';
  v_payment_id       UUID := 'a0000001-0000-0000-0000-000000000017';
  v_invoice_id       UUID := 'a0000001-0000-0000-0000-000000000018';
  v_return_id        UUID := 'a0000001-0000-0000-0000-000000000019';
  v_paysheet_id      UUID := 'a0000001-0000-0000-0000-000000000020';

  v_employee_id UUID;
  v_turn_id     INTEGER;
BEGIN

  -- ─────────────────────────────────────────────────────────────
  -- FASE 1 — TENANT
  -- ─────────────────────────────────────────────────────────────
  -- region_id 1 = Costa Rica (seed catalog/general)
  INSERT INTO general_schema.tenant
    (tenant_id, tenant_name, region_id, identification,
     econ_activity, sign, contact_email, is_subscribed)
  VALUES
    (v_tenant_id, 'Distribuidora Demo S.A.', 1, '3101234567',
     '742101', 'DDS', 'demo@distribuidora.cr', true)
  ON CONFLICT (tenant_id) DO NOTHING;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 2 — SUCURSAL
  -- ─────────────────────────────────────────────────────────────
  INSERT INTO general_schema.branch
    (branch_id, tenant_id, branch_name, branch_address,
     branch_number, contact_email, is_main_branch)
  VALUES
    (v_branch_id, v_tenant_id, 'Sucursal Central', 'San José, Costa Rica',
     '001', 'central@distribuidora.cr', true)
  ON CONFLICT (branch_id) DO NOTHING;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 3 — TURNO DE TRABAJO
  -- ─────────────────────────────────────────────────────────────
  SELECT turn_id INTO v_turn_id
  FROM hr_schema.turn
  WHERE branch_id = v_branch_id
  LIMIT 1;

  IF v_turn_id IS NULL THEN
    INSERT INTO hr_schema.turn (branch_id, entry, out)
    VALUES (v_branch_id, '08:00'::TIME, '17:00'::TIME)
    RETURNING turn_id INTO v_turn_id;
  END IF;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 4 — USUARIO ADMINISTRADOR Y EMPLEADO
  -- ─────────────────────────────────────────────────────────────
  -- role_id 1 = admin (seed catalog/general)
  INSERT INTO general_schema.users
    (user_id, tenant_id, email, password_hash, role_id)
  VALUES
    (v_user_id, v_tenant_id, 'admin@distribuidora.cr',
     crypt('Admin1234!', gen_salt('bf', 10)), 1)
  ON CONFLICT (user_id) DO NOTHING;

  -- Crear empleado sólo si aún no existe para este usuario
  SELECT employee_id INTO v_employee_id
  FROM hr_schema.employee
  WHERE user_id = v_user_id
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    -- hr_schema.create_new_employee(
    --   p_start_date, p_end_date, p_hours, p_base_salary, p_duties,
    --   p_turn_type, p_turn_id, p_user_id, p_tenant_id,
    --   p_first_name, p_last_name, p_doc_number, p_phone, p_email,
    --   p_payment_schedule_id, p_branch_id
    -- ) RETURNS UUID
    -- payment_schedule_id 1 = quincenal/mensual (seed catalog/hr)
    v_employee_id := hr_schema.create_new_employee(
      '2025-01-01'::DATE,
      '2026-01-01'::DATE,
      40,
      500000,
      'Administración general',
      1,
      v_turn_id,
      v_user_id,
      v_tenant_id,
      'Carlos',
      'Mora Solano',
      '106780000',
      '60001111',
      'admin@distribuidora.cr',
      1,
      v_branch_id
    );
  END IF;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 5 — CAJA REGISTRADORA
  -- ─────────────────────────────────────────────────────────────
  INSERT INTO pos_schema.cash_register
    (cash_register_id, branch_id, register_name, is_active)
  VALUES
    (v_cash_reg_id, v_branch_id, 'Caja Principal', true)
  ON CONFLICT (cash_register_id) DO NOTHING;

  INSERT INTO pos_schema.cash_register_session
    (cash_register_session_id, cash_register_id, user_id,
     opening_amount, opened_at, is_active)
  VALUES
    (v_cash_reg_sess_id, v_cash_reg_id, v_user_id,
     100000.00, '2025-06-01 08:00:00'::TIMESTAMP, true)
  ON CONFLICT (cash_register_session_id) DO NOTHING;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 6 — CLIENTE
  -- ─────────────────────────────────────────────────────────────
  -- identification_type_id 1 = Cédula Física (seed catalog/general)
  INSERT INTO general_schema.tenant_customer
    (tenant_customer_id, tenant_id, first_name, last_name,
     identification_type_id, document_number, econ_activity,
     email, phone, address, is_tenant)
  VALUES
    (v_customer_id, v_tenant_id, 'María', 'Rodríguez Vega',
     1, '106780001', '742101',
     'maria.rodriguez@gmail.com', '60001234',
     'San José, Escazú, Costa Rica', false)
  ON CONFLICT (tenant_customer_id) DO NOTHING;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 7 — PRODUCTOS (variantes sin CABYS para demo básico)
  -- ─────────────────────────────────────────────────────────────
  INSERT INTO general_schema.product_variant
    (tenant_id, product_variant_id, sku, variant_name, unit_price, is_active)
  VALUES
    (v_tenant_id, v_variant1_id, 'PROD-001', 'Cuaderno universitario 100 hojas', 1500.00, true),
    (v_tenant_id, v_variant2_id, 'PROD-002', 'Lapicero azul BIC',                 350.00, true),
    (v_tenant_id, v_variant3_id, 'PROD-003', 'Resma papel carta 500 hojas',       8900.00, true)
  ON CONFLICT (tenant_id, product_variant_id) DO NOTHING;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 8 — BODEGA E INVENTARIO
  -- ─────────────────────────────────────────────────────────────
  INSERT INTO inventory_schema.warehouse
    (warehouse_id, branch_id, warehouse_name, warehouse_address, is_branch)
  VALUES
    (v_warehouse_id, v_branch_id, 'Bodega Principal',
     'San José, La Uruca, Costa Rica', false)
  ON CONFLICT (warehouse_id) DO NOTHING;

  -- Agregar stock del primer producto (PROD-001)
  IF NOT EXISTS (
    SELECT 1 FROM inventory_schema.inventory
    WHERE tenant_id = v_tenant_id
      AND product_variant_id = v_variant1_id
      AND warehouse_id = v_warehouse_id
  ) THEN
    INSERT INTO inventory_schema.inventory
      (tenant_id, product_variant_id, warehouse_id, stock, expiration_date)
    VALUES
      (v_tenant_id, v_variant1_id, v_warehouse_id, 200, '2026-12-31');
  END IF;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 9 — PROVEEDOR Y ORDEN DE COMPRA
  -- ─────────────────────────────────────────────────────────────
  -- added_by referencia general_schema.tenant (no el usuario)
  INSERT INTO purchase_schema.supplier
    (supplier_id, supplier_name, supplier_contact_info,
     supplier_address, supplier_notes, added_by)
  VALUES
    (v_supplier_id, 'Papelería Nacional S.A.',
     'ventas@papnacional.cr | +506 2222-3333',
     'Barrio Amón, San José, Costa Rica',
     'Proveedor preferido para artículos de oficina',
     v_tenant_id)
  ON CONFLICT (supplier_id) DO NOTHING;

  -- purchase_order_status_id 1 = Pendiente (seed catalog/purchase)
  INSERT INTO purchase_schema.purchase_order
    (purchase_order_id, supplier_id, warehouse_id,
     expected_delivery_date, purchase_order_status_id)
  VALUES
    (v_purchase_id, v_supplier_id, v_warehouse_id, '2025-07-15', 1)
  ON CONFLICT (purchase_order_id) DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM purchase_schema.purchase_order_item
    WHERE purchase_order_id = v_purchase_id
      AND tenant_id = v_tenant_id
      AND product_variant_id = v_variant1_id
  ) THEN
    INSERT INTO purchase_schema.purchase_order_item
      (purchase_order_id, tenant_id, product_variant_id,
       quantity_ordered, unit_price)
    VALUES
      (v_purchase_id, v_tenant_id, v_variant1_id, 100, 1200.000);
  END IF;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 10 — SEGMENTO, MARGEN, PROMOCIÓN Y LEALTAD
  -- ─────────────────────────────────────────────────────────────
  -- Segmento personalizado (los segmentos 1-4 son de catálogo)
  INSERT INTO general_schema.customer_segment
    (segment_name, segment_hierarchy)
  VALUES ('VIP Corporativo', 1)
  ON CONFLICT (segment_name) DO NOTHING;

  -- Margen para el segmento 1 del catálogo
  -- customer_segment_margin_type_id 1 (seed catalog/general)
  IF NOT EXISTS (
    SELECT 1 FROM general_schema.customer_segment_margin
    WHERE tenant_id = v_tenant_id
      AND customer_segment_id = 1
  ) THEN
    INSERT INTO general_schema.customer_segment_margin
      (tenant_id, customer_segment_id, customer_segment_margin_type_id,
       spending_threshold, seniority_months, frequency_per_month)
    VALUES
      (v_tenant_id, 1, 1, 50000.00, 6, 4);
  END IF;

  -- Promoción
  -- promotion_type_id 1 = Porcentaje (seed catalog/pos)
  INSERT INTO pos_schema.promotion
    (promotion_id, tenant_id, promotion_name, promotion_code,
     promotion_description, promotion_type_id, customer_segment_id,
     promotion_start_date, promotion_end_date, is_active)
  VALUES
    (v_promotion_id, v_tenant_id, 'Descuento Verano 10%', 'VERANO10',
     '10% de descuento en compras durante el verano',
     1, 1, '2025-06-01', '2025-08-31', true)
  ON CONFLICT (promotion_id) DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM pos_schema.promotion_rule
    WHERE promotion_id = v_promotion_id
  ) THEN
    INSERT INTO pos_schema.promotion_rule
      (promotion_id, discount_percentage, min_purchase_amount)
    VALUES
      (v_promotion_id, 10.00, 5000.00);
  END IF;

  -- Programa de lealtad
  INSERT INTO pos_schema.loyalty_program
    (loyalty_program_id, tenant_id, points_earned_per_currency_unit,
     points_redeemed_per_currency_unit, minimum_purchase_for_points)
  VALUES
    (v_loyalty_id, v_tenant_id, 1.00, 100.00, 1000.00)
  ON CONFLICT (loyalty_program_id) DO NOTHING;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 11 — VENTA
  -- ─────────────────────────────────────────────────────────────
  -- sale_condition '01' = Contado (seed catalog/pos)
  -- currency_id   1    = CRC (seed catalog/general)
  -- 2x PROD-001 (1500) = subtotal 3000, IVA 13% = 390, total 3390
  INSERT INTO pos_schema.sale
    (sale_id, branch_id, tenant_customer_id, sale_condition, sale_date,
     currency_id, subtotal_amount, tax_amount, total_amount,
     is_completed, has_electronic_invoice)
  VALUES
    (v_sale_id, v_branch_id, v_customer_id, '01',
     '2025-06-01 10:30:00'::TIMESTAMP,
     1, 3000.00, 390.00, 3390.00, true, false)
  ON CONFLICT (sale_id) DO NOTHING;

  INSERT INTO pos_schema.sale_item
    (sale_item_id, sale_id, tenant_id, product_variant_id,
     quantity, unit_price, total_price)
  VALUES
    (v_sale_item_id, v_sale_id, v_tenant_id, v_variant1_id,
     2, 1500.00, 3000.00)
  ON CONFLICT (sale_item_id) DO NOTHING;

  -- payment_method_id 1 = Efectivo (seed catalog/general)
  INSERT INTO pos_schema.customer_payment
    (customer_payment_id, tenant_customer_id, sale_id, payment_method_id,
     is_points_redemption, points_redeemed, points_to_currency_rate,
     payment_amount, payment_date, currency_id, verified)
  VALUES
    (v_payment_id, v_customer_id, v_sale_id, 1,
     false, 0, 0, 3390.00,
     '2025-06-01 10:30:00'::TIMESTAMP, 1, true)
  ON CONFLICT (customer_payment_id) DO NOTHING;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 12 — FACTURA DIGITAL
  -- La factura digital es creada por el servicio al completar la venta.
  -- Aquí se inserta directamente para el seed.
  -- ─────────────────────────────────────────────────────────────
  INSERT INTO pos_schema.digital_sale_invoice
    (digital_sale_invoice_id, tenant_customer_id, sale_id, currency_id,
     subtotal_amount, tax_amount, total_amount,
     invoice_number, amount_paid, change_amount)
  VALUES
    (v_invoice_id, v_customer_id, v_sale_id, 1,
     3000.00, 390.00, 3390.00,
     'F-0001', 3390.00, 0.00)
  ON CONFLICT (digital_sale_invoice_id) DO NOTHING;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 13 — DEVOLUCIÓN PARCIAL
  -- ─────────────────────────────────────────────────────────────
  -- return_status_id 1 (seed catalog/pos)
  -- refund_method   1 = Efectivo (seed catalog/general)
  INSERT INTO pos_schema.return_transaction
    (return_transaction_id, digital_sale_invoice_id, tenant_customer_id,
     total_refund_amount, refund_method, return_status_id, return_date)
  VALUES
    (v_return_id, v_invoice_id, v_customer_id,
     1695.00, 1, 1, '2025-06-02 09:00:00'::TIMESTAMP)
  ON CONFLICT (return_transaction_id) DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM pos_schema.return_product
    WHERE return_transaction_id = v_return_id
      AND sale_item_id = v_sale_item_id
  ) THEN
    INSERT INTO pos_schema.return_product
      (return_transaction_id, sale_item_id, quantity, unit_price, total_price)
    VALUES
      (v_return_id, v_sale_item_id, 1, 1500.00, 1500.00);
  END IF;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 14 — CIERRE DE CAJA
  -- ─────────────────────────────────────────────────────────────
  UPDATE pos_schema.cash_register_session
  SET closed_at      = '2025-06-01 18:00:00'::TIMESTAMP,
      closing_amount = 101695.00,
      is_active      = false,
      updated_at     = NOW()
  WHERE cash_register_session_id = v_cash_reg_sess_id
    AND closed_at IS NULL;


  -- ─────────────────────────────────────────────────────────────
  -- FASE 15 — RECURSOS HUMANOS
  -- ─────────────────────────────────────────────────────────────

  -- 15a. Concepto de nómina (deducción CCSS empleado)
  -- type: 'earning' | 'deduction'
  -- calculation_method: 'fixed' | 'percentage' | 'formula' | 'manual'
  IF NOT EXISTS (
    SELECT 1 FROM hr_schema.payroll_concept
    WHERE tenant_id = v_tenant_id AND code = 'CCSS-EMP'
  ) THEN
    INSERT INTO hr_schema.payroll_concept
      (tenant_id, name, type, calculation_method,
       is_taxable, base_value, code)
    VALUES
      (v_tenant_id, 'CCSS Empleado', 'deduction', 'percentage',
       false, 0.1067, 'CCSS-EMP'); -- fraccion: 0.1067 = 10.67% (PercentageStrategy hace base * valor)
  END IF;

  -- 15b. Marcado de asistencia (entrada + salida en un solo registro)
  IF NOT EXISTS (
    SELECT 1 FROM hr_schema.clocking
    WHERE employee_id = v_employee_id
      AND clock_in = '2025-06-01 08:05:00'::TIMESTAMP
  ) THEN
    INSERT INTO hr_schema.clocking
      (employee_id, branch_id, clock_in, clock_out, turn_hours)
    VALUES
      (v_employee_id, v_branch_id,
       '2025-06-01 08:05:00'::TIMESTAMP,
       '2025-06-01 17:02:00'::TIMESTAMP,
       8.95);
  END IF;

  -- 15c. Incapacidad
  IF NOT EXISTS (
    SELECT 1 FROM hr_schema.incapacity
    WHERE employee_id = v_employee_id
      AND period_start = '2025-06-10'
  ) THEN
    INSERT INTO hr_schema.incapacity
      (employee_id, branch_id, type,
       period_start, period_end, days_paying, percentage_to_pay)
    VALUES
      (v_employee_id, v_branch_id, 'CCSS',
       '2025-06-10', '2025-06-15', 6, 60.00);
  END IF;

  -- 15d. Amonestación (foul) — identificator es UNIQUE
  IF NOT EXISTS (
    SELECT 1 FROM hr_schema.foul WHERE identificator = 'FOUL-001'
  ) THEN
    INSERT INTO hr_schema.foul
      (employee_id, branch_id, identificator,
       foul_date, foul_hour, description)
    VALUES
      (v_employee_id, v_branch_id, 'FOUL-001',
       '2025-06-05', '09:30'::TIME,
       'Llegada tardía sin justificación');
  END IF;

  -- 15e. Suspensión
  IF NOT EXISTS (
    SELECT 1 FROM hr_schema.suspention
    WHERE employee_id = v_employee_id
      AND suspention_start = '2025-06-20'
  ) THEN
    INSERT INTO hr_schema.suspention
      (employee_id, branch_id, suspention_start, suspention_end, reason)
    VALUES
      (v_employee_id, v_branch_id,
       '2025-06-20', '2025-06-22',
       'Incumplimiento de reglamento interno');
  END IF;

  -- 15f. Planilla del período
  -- status_id 1 = Pending (seed catalog/hr — 002-insert-paysheet-status.sql)
  -- total_deductions = 10.67% de 500000 = 53350
  INSERT INTO hr_schema.paysheet
    (paysheet_id, tenant_id, branch_id, period_start, period_end,
     total_earnings, total_deductions, net_total, status_id)
  VALUES
    (v_paysheet_id, v_tenant_id, v_branch_id,
     '2025-06-01', '2025-06-30',
     500000.0000, 53350.0000, 446650.0000, 1)
  ON CONFLICT (paysheet_id) DO NOTHING;

END $$;

COMMIT;
