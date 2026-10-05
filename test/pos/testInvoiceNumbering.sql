-- =====================================================
-- TEST: CORRELATIVO DE FACTURA Y CLIENTE OBLIGATORIO (migracion 040)
-- =====================================================
-- Verifica:
-- 1. invoice_number correlativo por tenant, independiente entre tenants
-- 2. Sin huecos: una transaccion revertida no consume numero
-- 3. Venta anonima y factura sin cliente rechazadas (filas nuevas)
-- 4. Filas historicas sin cliente siguen siendo actualizables (UPDATE)
-- 5. create_invoice() ya no se traga los errores
-- 6. Respaldo: venta pendiente historica sin cliente toma el del pago
--
-- Idempotente: SECCION 0 limpia todo lo que crea este script.
-- =====================================================

-- ========================================
-- SECCION 0: Limpieza
-- ========================================
DO $s0$
DECLARE
    v_tenants UUID[];
BEGIN
    SELECT array_agg(tenant_id) INTO v_tenants
    FROM general_schema.tenant
    WHERE tenant_name IN ('Numeracion VE A', 'Numeracion VE B');

    IF v_tenants IS NOT NULL THEN
        DELETE FROM pos_schema.invoice_payment WHERE invoice_id IN (
            SELECT i.invoice_id FROM pos_schema.invoice i
            JOIN pos_schema.sale s ON s.sale_id = i.sale_id
            JOIN general_schema.branch b ON b.branch_id = s.branch_id
            WHERE b.tenant_id = ANY(v_tenants));
        DELETE FROM pos_schema.invoice_item WHERE invoice_id IN (
            SELECT i.invoice_id FROM pos_schema.invoice i
            JOIN pos_schema.sale s ON s.sale_id = i.sale_id
            JOIN general_schema.branch b ON b.branch_id = s.branch_id
            WHERE b.tenant_id = ANY(v_tenants));
        DELETE FROM pos_schema.invoice WHERE sale_id IN (
            SELECT s.sale_id FROM pos_schema.sale s
            JOIN general_schema.branch b ON b.branch_id = s.branch_id
            WHERE b.tenant_id = ANY(v_tenants));
        DELETE FROM pos_schema.customer_payment WHERE sale_id IN (
            SELECT s.sale_id FROM pos_schema.sale s
            JOIN general_schema.branch b ON b.branch_id = s.branch_id
            WHERE b.tenant_id = ANY(v_tenants));
        DELETE FROM pos_schema.sale_item WHERE sale_id IN (
            SELECT s.sale_id FROM pos_schema.sale s
            JOIN general_schema.branch b ON b.branch_id = s.branch_id
            WHERE b.tenant_id = ANY(v_tenants));
        DELETE FROM pos_schema.sale WHERE branch_id IN (
            SELECT branch_id FROM general_schema.branch WHERE tenant_id = ANY(v_tenants));
        DELETE FROM general_schema.tenant_customer WHERE tenant_id = ANY(v_tenants);
        DELETE FROM general_schema.product_variant WHERE tenant_id = ANY(v_tenants);
        DELETE FROM general_schema.branch WHERE tenant_id = ANY(v_tenants);
        DELETE FROM general_schema.tenant WHERE tenant_id = ANY(v_tenants);
    END IF;

    DELETE FROM general_schema.product WHERE product_name = 'Producto numeracion VE';
    DELETE FROM general_schema.tax_rate WHERE rate_code = 'IVA16-NUMT';

    RAISE NOTICE 'SECCION 0: limpieza completada';
END $s0$;


-- ========================================
-- SECCION 1: Datos base (2 tenants, 1 cliente c/u, producto con IVA 16%)
-- ========================================
DO $s1$
DECLARE
    v_tax_rate_id INTEGER;
    v_product_id UUID;
    v_tenant UUID;
    v_name TEXT;
    v_suffix TEXT;
    v_branch UUID;
BEGIN
    INSERT INTO general_schema.tax_rate (rate_percentage, rate_code, rate_name)
    VALUES (16.00, 'IVA16-NUMT', 'IVA 16% (Test numeracion)')
    RETURNING tax_rate_id INTO v_tax_rate_id;

    INSERT INTO general_schema.product (product_name, tax_rate_id)
    VALUES ('Producto numeracion VE', v_tax_rate_id)
    RETURNING product_id INTO v_product_id;

    FOREACH v_suffix IN ARRAY ARRAY['A', 'B'] LOOP
        v_name := 'Numeracion VE ' || v_suffix;

        INSERT INTO general_schema.tenant
            (tenant_name, region_id, identification, contact_email, is_subscribed)
        VALUES (
            v_name,
            (SELECT region_id FROM general_schema.region WHERE region_name = 'Venezuela'),
            'J-NUM-' || v_suffix || '-0001',
            'admin-num-' || lower(v_suffix) || '@test.com',
            true)
        RETURNING tenant_id INTO v_tenant;

        INSERT INTO general_schema.branch (tenant_id, branch_name, branch_address, is_main_branch)
        VALUES (v_tenant, 'Sucursal ' || v_suffix, 'Av. de prueba ' || v_suffix, true)
        RETURNING branch_id INTO v_branch;

        INSERT INTO general_schema.tenant_customer
            (tenant_id, first_name, last_name, document_number, email, phone, address, customer_segment_id)
        VALUES (v_tenant, 'Cliente', v_suffix, 'V-9000000' || v_suffix,
                'cliente-num-' || lower(v_suffix) || '@test.com',
                '+58-414-000000' || ascii(v_suffix), 'Direccion cliente ' || v_suffix, 3);

        INSERT INTO general_schema.product_variant
            (tenant_id, product_id, sku, variant_name, unit_price, is_active)
        VALUES (v_tenant, v_product_id, 'NUM-001', 'Producto de prueba', 100.00, true);
    END LOOP;

    RAISE NOTICE 'SECCION 1: datos base creados';
END $s1$;


-- ========================================
-- SECCION 2: Correlativo por tenant e independencia entre tenants
-- ========================================
DO $s2$
DECLARE
    v_tenant_a UUID; v_tenant_b UUID;
    v_branch_a UUID; v_branch_b UUID;
    v_cust_a UUID;   v_cust_b UUID;
    v_var_a UUID;    v_var_b UUID;
    v_sale UUID;
    v_num INTEGER;
    v_tenant_on_invoice UUID;
    i INTEGER;
BEGIN
    SELECT tenant_id INTO v_tenant_a FROM general_schema.tenant WHERE tenant_name = 'Numeracion VE A';
    SELECT tenant_id INTO v_tenant_b FROM general_schema.tenant WHERE tenant_name = 'Numeracion VE B';
    SELECT branch_id INTO v_branch_a FROM general_schema.branch WHERE tenant_id = v_tenant_a;
    SELECT branch_id INTO v_branch_b FROM general_schema.branch WHERE tenant_id = v_tenant_b;
    SELECT tenant_customer_id INTO v_cust_a FROM general_schema.tenant_customer WHERE tenant_id = v_tenant_a;
    SELECT tenant_customer_id INTO v_cust_b FROM general_schema.tenant_customer WHERE tenant_id = v_tenant_b;
    SELECT product_variant_id INTO v_var_a FROM general_schema.product_variant WHERE tenant_id = v_tenant_a;
    SELECT product_variant_id INTO v_var_b FROM general_schema.product_variant WHERE tenant_id = v_tenant_b;

    -- Dos ventas en A, una en B.
    FOR i IN 1..2 LOOP
        INSERT INTO pos_schema.sale (branch_id, tenant_customer_id, sale_condition, currency_id,
                                     subtotal_amount, tax_amount, total_amount, is_completed)
        VALUES (v_branch_a, v_cust_a, '01', 1, 100.00, 16.00, 116.00, false)
        RETURNING sale_id INTO v_sale;
        INSERT INTO pos_schema.sale_item (sale_id, tenant_id, product_variant_id, quantity, unit_price, total_price)
        VALUES (v_sale, v_tenant_a, v_var_a, 1, 100.00, 100.00);
        UPDATE pos_schema.sale SET is_completed = true WHERE sale_id = v_sale;

        SELECT invoice_number, tenant_id INTO v_num, v_tenant_on_invoice
        FROM pos_schema.invoice WHERE sale_id = v_sale;
        IF v_num IS DISTINCT FROM i THEN
            RAISE EXCEPTION 'ASSERT FALLIDO: tenant A factura % tiene numero % (esperado %)', i, v_num, i;
        END IF;
        IF v_tenant_on_invoice IS DISTINCT FROM v_tenant_a THEN
            RAISE EXCEPTION 'ASSERT FALLIDO: invoice.tenant_id no coincide con el tenant A';
        END IF;
    END LOOP;
    RAISE NOTICE 'ASSERT OK: tenant A numera 1, 2 con tenant_id asignado';

    INSERT INTO pos_schema.sale (branch_id, tenant_customer_id, sale_condition, currency_id,
                                 subtotal_amount, tax_amount, total_amount, is_completed)
    VALUES (v_branch_b, v_cust_b, '01', 1, 100.00, 16.00, 116.00, false)
    RETURNING sale_id INTO v_sale;
    INSERT INTO pos_schema.sale_item (sale_id, tenant_id, product_variant_id, quantity, unit_price, total_price)
    VALUES (v_sale, v_tenant_b, v_var_b, 1, 100.00, 100.00);
    UPDATE pos_schema.sale SET is_completed = true WHERE sale_id = v_sale;

    SELECT invoice_number INTO v_num FROM pos_schema.invoice WHERE sale_id = v_sale;
    IF v_num IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: tenant B arranca en % (esperado 1, contador independiente)', v_num;
    END IF;
    RAISE NOTICE 'ASSERT OK: tenant B arranca en 1 (contador independiente)';
END $s2$;


-- ========================================
-- SECCION 3: Sin huecos ante rollback
-- ========================================
DO $s3$
DECLARE
    v_tenant_a UUID; v_branch_a UUID; v_cust_a UUID; v_var_a UUID;
    v_sale UUID;
    v_num INTEGER;
BEGIN
    SELECT tenant_id INTO v_tenant_a FROM general_schema.tenant WHERE tenant_name = 'Numeracion VE A';
    SELECT branch_id INTO v_branch_a FROM general_schema.branch WHERE tenant_id = v_tenant_a;
    SELECT tenant_customer_id INTO v_cust_a FROM general_schema.tenant_customer WHERE tenant_id = v_tenant_a;
    SELECT product_variant_id INTO v_var_a FROM general_schema.product_variant WHERE tenant_id = v_tenant_a;

    INSERT INTO pos_schema.sale (branch_id, tenant_customer_id, sale_condition, currency_id,
                                 subtotal_amount, tax_amount, total_amount, is_completed)
    VALUES (v_branch_a, v_cust_a, '01', 1, 100.00, 16.00, 116.00, false)
    RETURNING sale_id INTO v_sale;
    INSERT INTO pos_schema.sale_item (sale_id, tenant_id, product_variant_id, quantity, unit_price, total_price)
    VALUES (v_sale, v_tenant_a, v_var_a, 1, 100.00, 100.00);

    -- Completa la venta (asigna el numero 3) y fuerza el rollback del bloque.
    BEGIN
        UPDATE pos_schema.sale SET is_completed = true WHERE sale_id = v_sale;
        RAISE EXCEPTION 'rollback forzado del test';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;

    IF EXISTS (SELECT 1 FROM pos_schema.invoice WHERE sale_id = v_sale) THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: la factura sobrevivio al rollback';
    END IF;

    UPDATE pos_schema.sale SET is_completed = true WHERE sale_id = v_sale;
    SELECT invoice_number INTO v_num FROM pos_schema.invoice WHERE sale_id = v_sale;
    IF v_num IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: tras rollback el numero es % (esperado 3, sin hueco)', v_num;
    END IF;
    RAISE NOTICE 'ASSERT OK: el rollback no consumio numero (siguiente = 3)';
END $s3$;


-- ========================================
-- SECCION 4: Cliente obligatorio
-- ========================================
DO $s4$
DECLARE
    v_tenant_a UUID; v_branch_a UUID; v_cust_a UUID;
    v_sale UUID;
BEGIN
    SELECT tenant_id INTO v_tenant_a FROM general_schema.tenant WHERE tenant_name = 'Numeracion VE A';
    SELECT branch_id INTO v_branch_a FROM general_schema.branch WHERE tenant_id = v_tenant_a;
    SELECT tenant_customer_id INTO v_cust_a FROM general_schema.tenant_customer WHERE tenant_id = v_tenant_a;

    -- Venta anonima rechazada.
    BEGIN
        INSERT INTO pos_schema.sale (branch_id, sale_condition, currency_id,
                                     subtotal_amount, tax_amount, total_amount, is_completed)
        VALUES (v_branch_a, '01', 1, 100.00, 16.00, 116.00, false);
        RAISE EXCEPTION 'ASSERT FALLIDO: se acepto una venta anonima';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE '%anonima%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'ASSERT OK: venta anonima rechazada';

    -- Factura sin cliente rechazada.
    INSERT INTO pos_schema.sale (branch_id, tenant_customer_id, sale_condition, currency_id,
                                 subtotal_amount, tax_amount, total_amount, is_completed)
    VALUES (v_branch_a, v_cust_a, '01', 1, 100.00, 16.00, 116.00, false)
    RETURNING sale_id INTO v_sale;
    BEGIN
        INSERT INTO pos_schema.invoice (sale_id, currency_id, subtotal_amount, tax_amount, total_amount)
        VALUES (v_sale, 1, 100.00, 16.00, 116.00);
        RAISE EXCEPTION 'ASSERT FALLIDO: se acepto una factura sin cliente';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE '%anonima%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'ASSERT OK: factura sin cliente rechazada';
END $s4$;


-- ========================================
-- SECCION 5: Filas historicas sin cliente, error no tragado y respaldo por pago
-- ========================================
DO $s5$
DECLARE
    v_tenant_a UUID; v_branch_a UUID; v_cust_a UUID; v_var_a UUID;
    v_legacy_sale UUID;
    v_fallback_sale UUID;
    v_invoice_customer UUID;
    v_is_refunded BOOLEAN;
BEGIN
    SELECT tenant_id INTO v_tenant_a FROM general_schema.tenant WHERE tenant_name = 'Numeracion VE A';
    SELECT branch_id INTO v_branch_a FROM general_schema.branch WHERE tenant_id = v_tenant_a;
    SELECT tenant_customer_id INTO v_cust_a FROM general_schema.tenant_customer WHERE tenant_id = v_tenant_a;
    SELECT product_variant_id INTO v_var_a FROM general_schema.product_variant WHERE tenant_id = v_tenant_a;

    -- Simula dos ventas anonimas historicas (el trigger de insert las rechazaria).
    ALTER TABLE pos_schema.sale DISABLE TRIGGER trg_sale_require_customer;
    INSERT INTO pos_schema.sale (branch_id, sale_condition, currency_id,
                                 subtotal_amount, tax_amount, total_amount, is_completed)
    VALUES (v_branch_a, '01', 1, 100.00, 16.00, 116.00, false)
    RETURNING sale_id INTO v_legacy_sale;
    INSERT INTO pos_schema.sale (branch_id, sale_condition, currency_id,
                                 subtotal_amount, tax_amount, total_amount, is_completed)
    VALUES (v_branch_a, '01', 1, 100.00, 16.00, 116.00, false)
    RETURNING sale_id INTO v_fallback_sale;
    ALTER TABLE pos_schema.sale ENABLE TRIGGER trg_sale_require_customer;

    -- 4. UPDATE de una fila historica sin cliente sigue funcionando.
    UPDATE pos_schema.sale SET is_refunded = true WHERE sale_id = v_legacy_sale;
    SELECT is_refunded INTO v_is_refunded FROM pos_schema.sale WHERE sale_id = v_legacy_sale;
    IF v_is_refunded IS NOT TRUE THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: no se pudo actualizar una venta historica sin cliente';
    END IF;
    RAISE NOTICE 'ASSERT OK: venta historica sin cliente sigue siendo actualizable';

    -- 5. Completar una venta sin cliente ni pago con cliente falla en voz alta.
    INSERT INTO pos_schema.sale_item (sale_id, tenant_id, product_variant_id, quantity, unit_price, total_price)
    VALUES (v_legacy_sale, v_tenant_a, v_var_a, 1, 100.00, 100.00);
    BEGIN
        UPDATE pos_schema.sale SET is_completed = true WHERE sale_id = v_legacy_sale;
        RAISE EXCEPTION 'ASSERT FALLIDO: create_invoice() se trago el error';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE '%anonima%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'ASSERT OK: create_invoice() propaga el error (no se traga)';

    -- 6. Respaldo: la venta pendiente sin cliente toma el cliente de su pago.
    INSERT INTO pos_schema.sale_item (sale_id, tenant_id, product_variant_id, quantity, unit_price, total_price)
    VALUES (v_fallback_sale, v_tenant_a, v_var_a, 1, 100.00, 100.00);
    INSERT INTO pos_schema.customer_payment
        (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
    VALUES (v_cust_a, v_fallback_sale, 1, 116.00, 1, true);
    UPDATE pos_schema.sale SET is_completed = true WHERE sale_id = v_fallback_sale;

    SELECT tenant_customer_id INTO v_invoice_customer
    FROM pos_schema.invoice WHERE sale_id = v_fallback_sale;
    IF v_invoice_customer IS DISTINCT FROM v_cust_a THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: el respaldo por pago no asigno el cliente a la factura';
    END IF;
    RAISE NOTICE 'ASSERT OK: venta pendiente historica toma el cliente del pago';
END $s5$;


DO $summary$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TODAS LAS SECCIONES COMPLETADAS';
    RAISE NOTICE 'Tenants de prueba: Numeracion VE A / Numeracion VE B';
    RAISE NOTICE 'Vuelva a correr este script libremente (SECCION 0 limpia todo).';
    RAISE NOTICE '========================================';
END $summary$;
