-- =====================================================
-- TEST: IVA INCLUIDO EN LAS LINEAS DE FACTURA (migracion 042)
-- =====================================================
-- Verifica que pos_schema.invoice_item respeta product_variant.includes_iva:
-- 1. invoice_item_amounts(): desglose con IVA incluido y con IVA encima
-- 2. create_invoice(): linea con IVA incluido = base + IVA, total = precio cobrado
--    (sin IVA doble); linea sin IVA incluido suma el IVA encima como siempre
-- 3. Totales de la factura = totales de la venta
-- 4. update_on_return(): la devolucion parcial recalcula la linea y la venta
--    con la misma regla
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
    FROM general_schema.tenant WHERE tenant_name = 'Factura IVA Incluido';

    IF v_tenants IS NOT NULL THEN
        DELETE FROM pos_schema.return_product WHERE return_transaction_id IN (
            SELECT rt.return_transaction_id FROM pos_schema.return_transaction rt
            JOIN pos_schema.invoice i ON i.invoice_id = rt.invoice_id
            JOIN pos_schema.sale s ON s.sale_id = i.sale_id
            JOIN general_schema.branch b ON b.branch_id = s.branch_id
            WHERE b.tenant_id = ANY(v_tenants));
        DELETE FROM pos_schema.return_transaction WHERE invoice_id IN (
            SELECT i.invoice_id FROM pos_schema.invoice i
            JOIN pos_schema.sale s ON s.sale_id = i.sale_id
            JOIN general_schema.branch b ON b.branch_id = s.branch_id
            WHERE b.tenant_id = ANY(v_tenants));
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

    DELETE FROM general_schema.product WHERE product_name IN ('Producto IVA incluido', 'Producto IVA aparte');
    DELETE FROM general_schema.tax_rate WHERE rate_code = 'IVA16-INCL';

    RAISE NOTICE 'SECCION 0: limpieza completada';
END $s0$;


-- ========================================
-- SECCION 1: Datos base
-- ========================================
DO $s1$
DECLARE
    v_tax_rate_id INTEGER;
    v_product_inc UUID;
    v_product_exc UUID;
    v_tenant UUID;
BEGIN
    INSERT INTO general_schema.tax_rate (rate_percentage, rate_code, rate_name)
    VALUES (16.00, 'IVA16-INCL', 'IVA 16% (Test IVA incluido)')
    RETURNING tax_rate_id INTO v_tax_rate_id;

    INSERT INTO general_schema.product (product_name, tax_rate_id)
    VALUES ('Producto IVA incluido', v_tax_rate_id) RETURNING product_id INTO v_product_inc;
    INSERT INTO general_schema.product (product_name, tax_rate_id)
    VALUES ('Producto IVA aparte', v_tax_rate_id) RETURNING product_id INTO v_product_exc;

    INSERT INTO general_schema.tenant (tenant_name, region_id, identification, contact_email, is_subscribed)
    VALUES ('Factura IVA Incluido',
            (SELECT region_id FROM general_schema.region WHERE region_name = 'Venezuela'),
            'J-INCL-0001', 'admin-incl@test.com', true)
    RETURNING tenant_id INTO v_tenant;

    INSERT INTO general_schema.branch (tenant_id, branch_name, branch_address, is_main_branch)
    VALUES (v_tenant, 'Sucursal IVA', 'Av. de prueba', true);

    INSERT INTO general_schema.tenant_customer
        (tenant_id, first_name, last_name, document_number, email, phone, address, customer_segment_id)
    VALUES (v_tenant, 'Cliente', 'IVA', 'V-9100000', 'cliente-incl@test.com',
            '+58-414-0000001', 'Direccion cliente', 3);

    -- INC: precio 116.00 con IVA incluido. EXC: precio 100.00, el IVA va encima.
    INSERT INTO general_schema.product_variant
        (tenant_id, product_id, sku, variant_name, unit_price, includes_iva, is_active)
    VALUES (v_tenant, v_product_inc, 'INCL-INC', 'Con IVA incluido', 116.00, true, true),
           (v_tenant, v_product_exc, 'INCL-EXC', 'IVA aparte', 100.00, false, true);

    RAISE NOTICE 'SECCION 1: datos base creados';
END $s1$;


-- ========================================
-- SECCION 2: invoice_item_amounts()
-- ========================================
DO $s2$
DECLARE
    r record;
BEGIN
    SELECT * INTO r FROM pos_schema.invoice_item_amounts(232.00, 16, true);
    IF r.item_subtotal <> 200.00 OR r.item_tax_amount <> 32.00 OR r.item_total <> 232.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO incluido: % / % / %', r.item_subtotal, r.item_tax_amount, r.item_total;
    END IF;

    SELECT * INTO r FROM pos_schema.invoice_item_amounts(100.00, 16, false);
    IF r.item_subtotal <> 100.00 OR r.item_tax_amount <> 16.00 OR r.item_total <> 116.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO aparte: % / % / %', r.item_subtotal, r.item_tax_amount, r.item_total;
    END IF;

    -- Redondeo: 30.00 con IVA incluido -> base 25.86, IVA 4.14, suma exacta 30.00
    SELECT * INTO r FROM pos_schema.invoice_item_amounts(30.00, 16, true);
    IF r.item_subtotal <> 25.86 OR r.item_tax_amount <> 4.14 OR r.item_total <> 30.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO redondeo: % / % / %', r.item_subtotal, r.item_tax_amount, r.item_total;
    END IF;

    -- Sin tasa (producto sin tax_rate_id): sin IVA en ninguno de los dos modos
    SELECT * INTO r FROM pos_schema.invoice_item_amounts(50.00, 0, true);
    IF r.item_subtotal <> 50.00 OR r.item_tax_amount <> 0 OR r.item_total <> 50.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO tasa 0: % / % / %', r.item_subtotal, r.item_tax_amount, r.item_total;
    END IF;
    RAISE NOTICE 'ASSERT OK: invoice_item_amounts() desglosa y suma encima segun includes_iva';
END $s2$;


-- ========================================
-- SECCION 3: create_invoice() y devolucion parcial
-- ========================================
DO $s3$
DECLARE
    v_tenant UUID; v_branch UUID; v_cust UUID;
    v_var_inc UUID; v_var_exc UUID;
    v_sale UUID; v_invoice UUID;
    v_si_inc UUID;
    v_return_tx UUID;
    r record;
BEGIN
    SELECT tenant_id INTO v_tenant FROM general_schema.tenant WHERE tenant_name = 'Factura IVA Incluido';
    SELECT branch_id INTO v_branch FROM general_schema.branch WHERE tenant_id = v_tenant;
    SELECT tenant_customer_id INTO v_cust FROM general_schema.tenant_customer WHERE tenant_id = v_tenant;
    SELECT product_variant_id INTO v_var_inc FROM general_schema.product_variant WHERE tenant_id = v_tenant AND sku = 'INCL-INC';
    SELECT product_variant_id INTO v_var_exc FROM general_schema.product_variant WHERE tenant_id = v_tenant AND sku = 'INCL-EXC';

    -- Venta como la calcula el POS: INC 2 x 116.00 = 232.00 (IVA incluido, sin IVA encima)
    -- + EXC 1 x 100.00 (+16.00 de IVA) -> subtotal 332.00, IVA 16.00, total 348.00
    INSERT INTO pos_schema.sale (branch_id, tenant_customer_id, sale_condition, currency_id,
                                 subtotal_amount, tax_amount, total_amount, is_completed)
    VALUES (v_branch, v_cust, '01', 1, 332.00, 16.00, 348.00, false)
    RETURNING sale_id INTO v_sale;
    INSERT INTO pos_schema.sale_item (sale_id, tenant_id, product_variant_id, quantity, unit_price, total_price)
    VALUES (v_sale, v_tenant, v_var_inc, 2, 116.00, 232.00),
           (v_sale, v_tenant, v_var_exc, 1, 100.00, 100.00);
    UPDATE pos_schema.sale SET is_completed = true WHERE sale_id = v_sale;

    SELECT invoice_id INTO v_invoice FROM pos_schema.invoice WHERE sale_id = v_sale;
    IF v_invoice IS NULL THEN
        RAISE EXCEPTION 'ASSERT FALLIDO: la venta completada no genero factura';
    END IF;

    -- Linea con IVA incluido: base 200.00 + IVA 32.00 = 232.00 (lo cobrado)
    SELECT ii.subtotal, ii.tax_amount, ii.total_price, ii.unit_price INTO r
    FROM pos_schema.invoice_item ii WHERE ii.invoice_id = v_invoice AND ii.product_variant_id = v_var_inc;
    IF r.subtotal <> 200.00 OR r.tax_amount <> 32.00 OR r.total_price <> 232.00 OR r.unit_price <> 116.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO linea incluida: sub=% iva=% total=% unit=%',
            r.subtotal, r.tax_amount, r.total_price, r.unit_price;
    END IF;

    -- Linea sin IVA incluido: base 100.00 + IVA 16.00 = 116.00 (como antes)
    SELECT ii.subtotal, ii.tax_amount, ii.total_price INTO r
    FROM pos_schema.invoice_item ii WHERE ii.invoice_id = v_invoice AND ii.product_variant_id = v_var_exc;
    IF r.subtotal <> 100.00 OR r.tax_amount <> 16.00 OR r.total_price <> 116.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO linea aparte: sub=% iva=% total=%', r.subtotal, r.tax_amount, r.total_price;
    END IF;

    -- Factura = venta: el total cobrado no cambia por el desglose
    SELECT subtotal_amount, tax_amount, total_amount INTO r FROM pos_schema.invoice WHERE invoice_id = v_invoice;
    IF r.subtotal_amount <> 300.00 OR r.tax_amount <> 48.00 OR r.total_amount <> 348.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO factura: sub=% iva=% total=% (esperado 300/48/348)',
            r.subtotal_amount, r.tax_amount, r.total_amount;
    END IF;
    RAISE NOTICE 'ASSERT OK: factura 300.00 + IVA 48.00 = 348.00 = total de la venta (sin IVA doble)';

    -- Devolucion de 1 de las 2 unidades con IVA incluido
    SELECT sale_item_id INTO v_si_inc FROM pos_schema.sale_item WHERE sale_id = v_sale AND product_variant_id = v_var_inc;
    INSERT INTO pos_schema.return_transaction (invoice_id, tenant_customer_id, total_refund_amount, description)
    VALUES (v_invoice, v_cust, 0.00, 'Test IVA incluido')
    RETURNING return_transaction_id INTO v_return_tx;
    INSERT INTO pos_schema.return_product (return_transaction_id, sale_item_id, quantity, unit_price)
    VALUES (v_return_tx, v_si_inc, 1, 116.00);

    SELECT ii.subtotal, ii.tax_amount, ii.total_price INTO r
    FROM pos_schema.invoice_item ii WHERE ii.invoice_id = v_invoice AND ii.product_variant_id = v_var_inc;
    IF r.subtotal <> 100.00 OR r.tax_amount <> 16.00 OR r.total_price <> 116.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO linea tras devolucion: sub=% iva=% total=%', r.subtotal, r.tax_amount, r.total_price;
    END IF;

    SELECT subtotal_amount, tax_amount, total_amount INTO r FROM pos_schema.invoice WHERE invoice_id = v_invoice;
    IF r.subtotal_amount <> 200.00 OR r.tax_amount <> 32.00 OR r.total_amount <> 232.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO factura tras devolucion: sub=% iva=% total=% (esperado 200/32/232)',
            r.subtotal_amount, r.tax_amount, r.total_amount;
    END IF;

    -- Venta: subtotal 116 + 100, IVA solo del item que lo suma encima (16.00)
    SELECT subtotal_amount, tax_amount, total_amount INTO r FROM pos_schema.sale WHERE sale_id = v_sale;
    IF r.subtotal_amount <> 216.00 OR r.tax_amount <> 16.00 OR r.total_amount <> 232.00 THEN
        RAISE EXCEPTION 'ASSERT FALLIDO venta tras devolucion: sub=% iva=% total=% (esperado 216/16/232)',
            r.subtotal_amount, r.tax_amount, r.total_amount;
    END IF;
    RAISE NOTICE 'ASSERT OK: devolucion parcial recalcula linea, factura y venta con la misma regla';
END $s3$;


-- ========================================
-- SECCION 4: Limpieza final
-- ========================================
DO $s4$
DECLARE
    v_tenants UUID[];
BEGIN
    SELECT array_agg(tenant_id) INTO v_tenants
    FROM general_schema.tenant WHERE tenant_name = 'Factura IVA Incluido';

    IF v_tenants IS NOT NULL THEN
        DELETE FROM pos_schema.return_product WHERE return_transaction_id IN (
            SELECT rt.return_transaction_id FROM pos_schema.return_transaction rt
            JOIN pos_schema.invoice i ON i.invoice_id = rt.invoice_id
            JOIN pos_schema.sale s ON s.sale_id = i.sale_id
            JOIN general_schema.branch b ON b.branch_id = s.branch_id
            WHERE b.tenant_id = ANY(v_tenants));
        DELETE FROM pos_schema.return_transaction WHERE invoice_id IN (
            SELECT i.invoice_id FROM pos_schema.invoice i
            JOIN pos_schema.sale s ON s.sale_id = i.sale_id
            JOIN general_schema.branch b ON b.branch_id = s.branch_id
            WHERE b.tenant_id = ANY(v_tenants));
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

    DELETE FROM general_schema.product WHERE product_name IN ('Producto IVA incluido', 'Producto IVA aparte');
    DELETE FROM general_schema.tax_rate WHERE rate_code = 'IVA16-INCL';

    RAISE NOTICE 'SECCION 4: limpieza final completada';
END $s4$;
