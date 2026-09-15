-- =====================================================
-- TEST: FACTURA UNIFICADA (invoice)
-- =====================================================
-- Este script prueba el flujo unico de factura post CR->VE:
-- 1. Configuracion inicial (tenant VE, producto, variante, cliente)
-- 2. Creacion de venta y pago
-- 3. Verificacion del pago (dispara la cascada de creacion de factura)
-- 4. Verificacion de pos_schema.invoice / invoice_item / invoice_payment
-- 5. Puntos de lealtad otorgados via invoice_payment
-- 6. Devolucion parcial y reconciliacion de totales (invoice + sale)
--
-- No hay factura electronica ni CABYS en este flujo: fueron removidos por la
-- migracion CR->VE (ver docs/pos/Invoice.md).
-- =====================================================

-- ========================================
-- SECCION 0: Limpieza inicial
-- ========================================
DO $section_0$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'SECCION 0: Limpieza inicial';
    RAISE NOTICE '========================================';

    DELETE FROM pos_schema.return_product
    WHERE return_transaction_id IN (
        SELECT rt.return_transaction_id FROM pos_schema.return_transaction rt
        JOIN pos_schema.invoice inv ON inv.invoice_id = rt.invoice_id
        JOIN pos_schema.sale s ON s.sale_id = inv.sale_id
        JOIN general_schema.branch b ON b.branch_id = s.branch_id
        WHERE b.tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE')
    );

    DELETE FROM pos_schema.return_transaction
    WHERE invoice_id IN (
        SELECT inv.invoice_id FROM pos_schema.invoice inv
        JOIN pos_schema.sale s ON s.sale_id = inv.sale_id
        JOIN general_schema.branch b ON b.branch_id = s.branch_id
        WHERE b.tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE')
    );

    DELETE FROM pos_schema.score_transaction
    WHERE tenant_customer_id IN (
        SELECT tenant_customer_id FROM general_schema.tenant_customer
        WHERE email = 'cliente.factura@email.com'
    );

    DELETE FROM pos_schema.tenant_customer_score
    WHERE tenant_customer_id IN (
        SELECT tenant_customer_id FROM general_schema.tenant_customer
        WHERE email = 'cliente.factura@email.com'
    );

    DELETE FROM pos_schema.invoice_payment
    WHERE invoice_id IN (
        SELECT inv.invoice_id FROM pos_schema.invoice inv
        JOIN pos_schema.sale s ON s.sale_id = inv.sale_id
        JOIN general_schema.branch b ON b.branch_id = s.branch_id
        WHERE b.tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE')
    );

    DELETE FROM pos_schema.invoice_item
    WHERE invoice_id IN (
        SELECT inv.invoice_id FROM pos_schema.invoice inv
        JOIN pos_schema.sale s ON s.sale_id = inv.sale_id
        JOIN general_schema.branch b ON b.branch_id = s.branch_id
        WHERE b.tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE')
    );

    DELETE FROM pos_schema.invoice
    WHERE sale_id IN (
        SELECT s.sale_id FROM pos_schema.sale s
        JOIN general_schema.branch b ON b.branch_id = s.branch_id
        WHERE b.tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE')
    );

    DELETE FROM pos_schema.customer_payment
    WHERE tenant_customer_id IN (
        SELECT tenant_customer_id FROM general_schema.tenant_customer
        WHERE email = 'cliente.factura@email.com'
    );

    DELETE FROM pos_schema.cash_register_sale
    WHERE sale_id IN (
        SELECT s.sale_id FROM pos_schema.sale s
        JOIN general_schema.branch b ON b.branch_id = s.branch_id
        WHERE b.tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE')
    );

    DELETE FROM pos_schema.sale_item
    WHERE sale_id IN (
        SELECT s.sale_id FROM pos_schema.sale s
        JOIN general_schema.branch b ON b.branch_id = s.branch_id
        WHERE b.tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE')
    );

    DELETE FROM pos_schema.sale
    WHERE branch_id IN (
        SELECT branch_id FROM general_schema.branch
        WHERE tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE')
    );

    DELETE FROM pos_schema.cash_register_session
    WHERE cash_register_id IN (
        SELECT cash_register_id FROM pos_schema.cash_register
        WHERE branch_id IN (
            SELECT branch_id FROM general_schema.branch
            WHERE tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE')
        )
    );

    DELETE FROM pos_schema.cash_register
    WHERE branch_id IN (
        SELECT branch_id FROM general_schema.branch
        WHERE tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE')
    );

    DELETE FROM pos_schema.loyalty_program
    WHERE tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE');

    DELETE FROM general_schema.tenant_customer
    WHERE tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE');

    DELETE FROM general_schema.product_variant
    WHERE tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE');

    DELETE FROM general_schema.product WHERE product_name = 'Producto de prueba factura VE';

    DELETE FROM general_schema.tax_rate WHERE rate_code = 'IVA-16-TEST';

    DELETE FROM general_schema.users
    WHERE tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE');

    DELETE FROM general_schema.branch
    WHERE tenant_id IN (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE');

    DELETE FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE';

    RAISE NOTICE 'Limpieza completada';
END $section_0$;


-- ========================================
-- SECCION 1: Configuracion inicial
-- ========================================
DO $section_1$
DECLARE
    v_tenant_id UUID;
    v_branch_id UUID;
    v_user_id UUID;
    v_customer_id UUID;
    v_product_id UUID;
    v_variant_id UUID;
    v_cash_register_id UUID;
    v_tax_rate_id INTEGER;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'SECCION 1: Configuracion inicial';
    RAISE NOTICE '========================================';

    INSERT INTO general_schema.tenant (tenant_name, region_id, contact_email, is_subscribed)
    VALUES ('Factura Unificada VE', (SELECT region_id FROM general_schema.region WHERE region_name = 'Venezuela'), 'admin@facturave.com', true)
    RETURNING tenant_id INTO v_tenant_id;

    INSERT INTO general_schema.branch (tenant_id, branch_name, branch_address, is_main_branch)
    VALUES (v_tenant_id, 'Sucursal Caracas', 'Av. Francisco de Miranda', true)
    RETURNING branch_id INTO v_branch_id;

    INSERT INTO general_schema.users (tenant_id, email, password_hash, role_id)
    VALUES (v_tenant_id, 'cajero@facturave.com', 'hash_test', 1)
    RETURNING user_id INTO v_user_id;

    INSERT INTO general_schema.tenant_customer (
        tenant_id, first_name, last_name, document_number,
        email, phone, customer_segment_id
    )
    VALUES (
        v_tenant_id, 'Maria', 'Perez', 'V-12345678',
        'cliente.factura@email.com', '+58-414-7771234', 3
    )
    RETURNING tenant_customer_id INTO v_customer_id;

    -- Tasa IVA 16% (SENIAT) — sin CABYS: el producto no lleva codigo de catalogo.
    INSERT INTO general_schema.tax_rate (rate_percentage, rate_code, rate_name)
    VALUES (16.00, 'IVA-16-TEST', 'IVA 16% (Test Factura VE)')
    RETURNING tax_rate_id INTO v_tax_rate_id;

    INSERT INTO general_schema.product (product_name, tax_rate_id)
    VALUES ('Producto de prueba factura VE', v_tax_rate_id)
    RETURNING product_id INTO v_product_id;

    INSERT INTO general_schema.product_variant (
        tenant_id, product_id, sku, variant_name, unit_price, is_active
    )
    VALUES (
        v_tenant_id, v_product_id, 'FVE-001', 'Producto de prueba', 100.00, true
    )
    RETURNING product_variant_id INTO v_variant_id;

    INSERT INTO pos_schema.cash_register (branch_id, is_active)
    VALUES (v_branch_id, true)
    RETURNING cash_register_id INTO v_cash_register_id;

    INSERT INTO pos_schema.loyalty_program (
        tenant_id, points_earned_per_currency_unit, points_redeemed_per_currency_unit,
        minimum_purchase_for_points, is_active
    )
    VALUES (v_tenant_id, 1.00, 100.00, 0.00, true);

    RAISE NOTICE 'Tenant: %, Branch: %, Variant: %', v_tenant_id, v_branch_id, v_variant_id;
    RAISE NOTICE 'SECCION 1 COMPLETADA';
END $section_1$;


-- ========================================
-- SECCION 2: Abrir sesion de caja
-- ========================================
DO $section_2$
DECLARE
    v_tenant_id UUID;
    v_cash_register_id UUID;
    v_user_id UUID;
BEGIN
    RAISE NOTICE 'SECCION 2: Abrir sesion de caja';

    SELECT tenant_id INTO v_tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE';

    SELECT cr.cash_register_id INTO v_cash_register_id
    FROM pos_schema.cash_register cr
    JOIN general_schema.branch b ON cr.branch_id = b.branch_id
    WHERE b.tenant_id = v_tenant_id AND cr.is_active = true
    LIMIT 1;

    SELECT user_id INTO v_user_id FROM general_schema.users WHERE tenant_id = v_tenant_id LIMIT 1;

    CALL pos_schema.open_close_cash_register_session(v_cash_register_id, 'open', 0.00, v_user_id);

    RAISE NOTICE 'SECCION 2 COMPLETADA';
END $section_2$;


-- ========================================
-- SECCION 3: Crear venta con producto (100.00 + 16% IVA = 116.00)
-- ========================================
DO $section_3$
DECLARE
    v_tenant_id UUID;
    v_branch_id UUID;
    v_variant_id UUID;
    v_sale_id UUID;
BEGIN
    RAISE NOTICE 'SECCION 3: Crear venta';

    SELECT tenant_id INTO v_tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE';
    SELECT branch_id INTO v_branch_id FROM general_schema.branch WHERE tenant_id = v_tenant_id LIMIT 1;
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id LIMIT 1;

    INSERT INTO pos_schema.sale (branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
    VALUES (v_branch_id, 1, 100.00, 16.00, 116.00, false)
    RETURNING sale_id INTO v_sale_id;

    INSERT INTO pos_schema.sale_item (sale_id, tenant_id, product_variant_id, quantity, unit_price, total_price)
    VALUES (v_sale_id, v_tenant_id, v_variant_id, 1, 100.00, 100.00);

    RAISE NOTICE 'Venta creada: % (total 116.00)', v_sale_id;
    RAISE NOTICE 'SECCION 3 COMPLETADA';
END $section_3$;


-- ========================================
-- SECCION 4: Registrar pago
-- ========================================
DO $section_4$
DECLARE
    v_tenant_id UUID;
    v_customer_id UUID;
    v_sale_id UUID;
BEGIN
    RAISE NOTICE 'SECCION 4: Registrar pago';

    SELECT tenant_id INTO v_tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE';
    SELECT tenant_customer_id INTO v_customer_id FROM general_schema.tenant_customer
        WHERE tenant_id = v_tenant_id AND email = 'cliente.factura@email.com';
    SELECT s.sale_id INTO v_sale_id FROM pos_schema.sale s
        JOIN general_schema.branch b ON b.branch_id = s.branch_id
        WHERE b.tenant_id = v_tenant_id AND s.is_completed = false
        ORDER BY s.sale_date DESC LIMIT 1;

    INSERT INTO pos_schema.customer_payment (
        tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified
    )
    VALUES (v_customer_id, v_sale_id, 1, 116.00, 1, false);

    RAISE NOTICE 'Pago registrado para venta %', v_sale_id;
    RAISE NOTICE 'SECCION 4 COMPLETADA';
END $section_4$;


-- ========================================
-- SECCION 5: Verificar pago (dispara create_invoice) y aserciones
-- ========================================
DO $section_5$
DECLARE
    v_tenant_id UUID;
    v_payment_id UUID;
    v_sale_id UUID;
    v_sale_completed BOOLEAN;
    v_invoice_id UUID;
    v_invoice_total NUMERIC(10,2);
    v_invoice_item_count INT;
    v_invoice_payment_count INT;
BEGIN
    RAISE NOTICE 'SECCION 5: Verificar pago';

    SELECT tenant_id INTO v_tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE';

    SELECT cp.customer_payment_id, cp.sale_id INTO v_payment_id, v_sale_id
    FROM pos_schema.customer_payment cp
    JOIN general_schema.tenant_customer tc ON cp.tenant_customer_id = tc.tenant_customer_id
    WHERE tc.tenant_id = v_tenant_id AND cp.verified = false
    ORDER BY cp.payment_date DESC LIMIT 1;

    IF v_payment_id IS NULL THEN
        RAISE EXCEPTION 'No se encontro pago pendiente';
    END IF;

    CALL pos_schema.verify_customer_payment(v_payment_id);

    SELECT is_completed INTO v_sale_completed FROM pos_schema.sale WHERE sale_id = v_sale_id;
    IF NOT v_sale_completed THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: la venta no se marco como completada';
    END IF;
    RAISE NOTICE 'ASSERT OK: sale.is_completed = true';

    SELECT invoice_id, total_amount INTO v_invoice_id, v_invoice_total
    FROM pos_schema.invoice WHERE sale_id = v_sale_id;
    IF v_invoice_id IS NULL THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: no se creo invoice para la venta';
    END IF;
    RAISE NOTICE 'ASSERT OK: invoice creado (%), total %', v_invoice_id, v_invoice_total;

    IF v_invoice_total IS DISTINCT FROM 116.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: invoice.total_amount = % (esperado 116.00)', v_invoice_total;
    END IF;
    RAISE NOTICE 'ASSERT OK: invoice.total_amount = 116.00';

    SELECT COUNT(*) INTO v_invoice_item_count FROM pos_schema.invoice_item WHERE invoice_id = v_invoice_id;
    IF v_invoice_item_count <> 1 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: invoice_item count = % (esperado 1)', v_invoice_item_count;
    END IF;
    RAISE NOTICE 'ASSERT OK: invoice_item count = 1';

    SELECT COUNT(*) INTO v_invoice_payment_count FROM pos_schema.invoice_payment WHERE invoice_id = v_invoice_id;
    IF v_invoice_payment_count <> 1 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: invoice_payment count = % (esperado 1)', v_invoice_payment_count;
    END IF;
    RAISE NOTICE 'ASSERT OK: invoice_payment count = 1';

    IF NOT EXISTS (
        SELECT 1 FROM pos_schema.score_transaction WHERE invoice_id = v_invoice_id AND transaction_type_id = 1
    ) THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: no se otorgaron puntos de lealtad';
    END IF;
    RAISE NOTICE 'ASSERT OK: puntos de lealtad otorgados';

    RAISE NOTICE 'SECCION 5 COMPLETADA';
END $section_5$;


-- ========================================
-- SECCION 6: Devolucion parcial y reconciliacion
-- ========================================
DO $section_6$
DECLARE
    v_tenant_id UUID;
    v_sale_id UUID;
    v_invoice_id UUID;
    v_sale_item_id UUID;
    v_return_transaction_id UUID;
    v_invoice_total_after NUMERIC(10,2);
    v_sale_total_after NUMERIC(10,2);
BEGIN
    RAISE NOTICE 'SECCION 6: Devolucion parcial';

    SELECT tenant_id INTO v_tenant_id FROM general_schema.tenant WHERE tenant_name = 'Factura Unificada VE';
    SELECT s.sale_id, inv.invoice_id INTO v_sale_id, v_invoice_id
    FROM pos_schema.sale s
    JOIN general_schema.branch b ON b.branch_id = s.branch_id
    JOIN pos_schema.invoice inv ON inv.sale_id = s.sale_id
    WHERE b.tenant_id = v_tenant_id
    LIMIT 1;

    SELECT sale_item_id INTO v_sale_item_id FROM pos_schema.sale_item WHERE sale_id = v_sale_id LIMIT 1;

    INSERT INTO pos_schema.return_transaction (invoice_id, total_refund_amount, description)
    VALUES (v_invoice_id, 116.00, 'Devolucion total de prueba')
    RETURNING return_transaction_id INTO v_return_transaction_id;

    -- Devuelve la unica linea completa (quantity=1 -> queda en 0, elimina sale_item/invoice_item).
    INSERT INTO pos_schema.return_product (return_transaction_id, sale_item_id, quantity, unit_price)
    VALUES (v_return_transaction_id, v_sale_item_id, 1, 100.00);

    SELECT total_amount INTO v_invoice_total_after FROM pos_schema.invoice WHERE invoice_id = v_invoice_id;
    SELECT total_amount INTO v_sale_total_after FROM pos_schema.sale WHERE sale_id = v_sale_id;

    IF v_invoice_total_after IS DISTINCT FROM 0.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: invoice.total_amount tras devolucion = % (esperado 0.00)', v_invoice_total_after;
    END IF;
    RAISE NOTICE 'ASSERT OK: invoice.total_amount tras devolucion total = 0.00';

    IF v_sale_total_after IS DISTINCT FROM 0.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: sale.total_amount tras devolucion = % (esperado 0.00)', v_sale_total_after;
    END IF;
    RAISE NOTICE 'ASSERT OK: sale.total_amount tras devolucion total = 0.00';

    RAISE NOTICE 'SECCION 6 COMPLETADA';
END $section_6$;


-- ========================================
-- RESUMEN
-- ========================================
DO $summary$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TODAS LAS SECCIONES COMPLETADAS';
    RAISE NOTICE 'Tenant de prueba: Factura Unificada VE';
    RAISE NOTICE 'Vuelva a correr este script libremente (SECCION 0 limpia todo).';
    RAISE NOTICE '========================================';
END $summary$;
