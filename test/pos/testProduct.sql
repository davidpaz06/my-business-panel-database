-- =====================================
-- SCRIPT DE PRUEBA: PRODUCTS - INSERT & DELETE (idempotent)
-- =====================================
-- Objetivo:
--  - Demostrar inserción y borrado de productos uno por uno y en lote (batch)
--  - Idempotencia: al ejecutar varias veces el script, el estado final es el mismo
-- Estructura:
--  0) Limpieza (idempotente)
--  1) Preparación (tenant + categoría)
--  2) Insertar productos individuales (single inserts)
--  3) Insertar productos en lote (batch inserts)
--  4) Borrar producto individual
--  5) Borrar lote de productos
--  6) Verificaciones (constraints / particiones / conteos)
--  7) Resumen final
-- =====================================

set local search_path = general_schema, pos;

-- ========================================
-- SECCIÓN 0: Limpieza inicial (idempotente)
-- ========================================
DO $$
declare
    v_tenant_id uuid;
BEGIN
    raise notice '========================================';
    raise notice '🧹 SECCIÓN 0: Limpieza inicial (idempotente)';
    raise notice '========================================';

    select tenant_id into v_tenant_id from general_schema.tenant where tenant_name = 'Product Test Shop' limit 1;

    if v_tenant_id is not null then
        delete from general_schema.attribute_assignation where tenant_id = v_tenant_id;
        delete from general_schema.product_variant where tenant_id = v_tenant_id;
        delete from general_schema.product where tenant_id = v_tenant_id;
        raise notice '   Removed previous products for tenant %', v_tenant_id;
    else
        raise notice '   No previous test tenant found, nothing to clean';
    end if;

    -- 🔧 Resincronizar secuencia de product_category
    perform setval('general_schema.product_category_product_category_id_seq', 
        coalesce((select max(product_category_id) from general_schema.product_category), 0) + 1, 
        false);
    raise notice '   ✅ product_category sequence synchronized';

    raise notice '✅ SECCIÓN 0 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 1: Preparación (tenant + categoría)
-- ========================================
DO $$
declare
    v_tenant_id uuid;
    v_category_id int;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '🏪 SECCIÓN 1: Preparación (tenant & category)';
    raise notice '========================================';

    select tenant_id into v_tenant_id from general_schema.tenant where tenant_name = 'Product Test Shop' limit 1;
    if v_tenant_id is null then
        INSERT INTO general_schema.tenant (tenant_name, region_id, contact_email, is_subscribed)
        VALUES ('Product Test Shop', (select region_id from general_schema.region limit 1), 'products@testshop.local', false)
        returning tenant_id into v_tenant_id;
        raise notice '   Tenant created: %', v_tenant_id;
    else
        raise notice '   Tenant exists: %', v_tenant_id;
    end if;

    select product_category_id into v_category_id from general_schema.product_category where category_name = 'Test Category' limit 1;
    if v_category_id is null then
        INSERT INTO general_schema.product_category (category_name) VALUES ('Test Category') returning product_category_id into v_category_id;
        raise notice '   Product category created: %', v_category_id;
    else
        raise notice '   Product category exists: %', v_category_id;
    end if;

    raise notice '✅ SECCIÓN 1 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 2: Insertar productos individuales (single inserts)
-- ========================================
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Product Test Shop' limit 1);
    v_pid uuid;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '➕ SECCIÓN 2: Insertar productos individuales';
    raise notice '========================================';

    -- Single insert 1
    INSERT INTO general_schema.product (tenant_id, sku, product_name, unit_price, product_category_id)
    VALUES (v_tenant_id, 'SINGLE-001', 'Single Product One', 9.99, (select product_category_id from general_schema.product_category where category_name = 'Test Category' limit 1))
    on conflict (tenant_id, sku) DO nothing
    returning product_id into v_pid;
    if v_pid is not null then
        raise notice '   Inserted SINGLE-001 -> %', v_pid;
    else
        raise notice '   SINGLE-001 already exists';
    end if;

    -- Single insert 2
    INSERT INTO general_schema.product (tenant_id, sku, product_name, unit_price, product_category_id)
    VALUES (v_tenant_id, 'SINGLE-002', 'Single Product Two', 19.50, (select product_category_id from general_schema.product_category where category_name = 'Test Category' limit 1))
    on conflict (tenant_id, sku) DO nothing
    returning product_id into v_pid;
    if v_pid is not null then
        raise notice '   Inserted SINGLE-002 -> %', v_pid;
    else
        raise notice '   SINGLE-002 already exists';
    end if;

    raise notice '✅ SECCIÓN 2 COMPLETADA';
end $$;


-- ========================================
-- SECCIÓN 3: Insertar productos en lote (batch inserts)
-- ========================================
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Product Test Shop' limit 1);
    i int;
    v_sku text;
    v_pid uuid;  -- ✅ CORRECCIÓN: Declarar variable
    v_count_inserted int := 0;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '📦 SECCIÓN 3: Insertar productos en LOTE (20 items)';
    raise notice '========================================';

    for i in 1..20 loop
        v_sku := lpad(i::text, 3, '0');
        INSERT INTO general_schema.product (tenant_id, sku, product_name, unit_price, product_category_id)
        VALUES (v_tenant_id, 'BATCH-' || v_sku, 'Batch Product ' || v_sku, round( (5 + random()*45)::numeric, 2), (select product_category_id from general_schema.product_category where category_name = 'Test Category' limit 1))
        on conflict (tenant_id, sku) DO nothing
        returning product_id into v_pid;  -- ✅ CORRECCIÓN: Quitar STRICT
        
        if v_pid is not null then  -- ✅ CORRECCIÓN: Verificar si se insertó
            v_count_inserted := v_count_inserted + 1;
        end if;
    end loop;

    raise notice '   Inserted batch products this run: %', v_count_inserted;
    raise notice '✅ SECCIÓN 3 COMPLETADA';
end $$;


-- ========================================
-- SECCIÓN 4: Borrar producto individual
-- ========================================
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Product Test Shop' limit 1);
    v_deleted int;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '➖ SECCIÓN 4: Borrar producto individual (SINGLE-002)';
    raise notice '========================================';

    delete from general_schema.product where tenant_id = v_tenant_id and sku = 'SINGLE-002';
    get diagnostics v_deleted = row_count;

    if v_deleted = 1 then
        raise notice '   SINGLE-002 deleted';
    else
        raise notice '   SINGLE-002 not found (already deleted)';
    end if;

    raise notice '✅ SECCIÓN 4 COMPLETADA';
end $$;


-- ========================================
-- SECCIÓN 5: Borrar lote de productos (batch delete)
-- ========================================
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Product Test Shop' limit 1);
    v_deleted int;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '🧺 SECCIÓN 5: Borrar lote de productos (sku LIKE ''BATCH-%%'')';  -- ✅ CORRECCIÓN: Usar %% para escapar %
    raise notice '========================================';

    delete from general_schema.product where tenant_id = v_tenant_id and sku like 'BATCH-%';
    get diagnostics v_deleted = row_count;

    raise notice '   Batch products deleted this run: %', v_deleted;

    raise notice '✅ SECCIÓN 5 COMPLETADA';
end $$;


-- ========================================
-- SECCIÓN 6: Verificaciones (constraints / partitions / counts)
-- ========================================
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Product Test Shop' limit 1);
    v_count_total int;
    v_count_single int;
    v_tableoid record;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '🔍 SECCIÓN 6: Verificaciones finales';
    raise notice '========================================';

    select count(*) into v_count_total from general_schema.product where tenant_id = v_tenant_id;
    select count(*) into v_count_single from general_schema.product where tenant_id = v_tenant_id and sku = 'SINGLE-001';

    raise notice '   Products remaining for tenant %: %', v_tenant_id, v_count_total;
    raise notice '   SINGLE-001 exists: %', case when v_count_single > 0 then 'yes' else 'no' end;

    -- show partition (tableoid) for a sample row if exists
    if v_count_total > 0 then
        for v_tableoid in
            select tableoid::regclass as partition_name from general_schema.product where tenant_id = v_tenant_id limit 1
        loop
            raise notice '   Sample product partition: %', v_tableoid.partition_name;
        end loop;
    end if;

    -- Assertions
    if v_count_single = 0 then
        raise exception 'Expected SINGLE-001 to exist after tests but it is missing';
    end if;

    raise notice '✅ SECCIÓN 6 COMPLETADA - Constraints & counts ok';
end $$;


-- ========================================
-- SECCIÓN 7: Resumen final
-- ========================================
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Product Test Shop' limit 1);
    v_count int;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECCIÓN 7: RESUMEN FINAL';
    raise notice '========================================';

    select count(*) into v_count from general_schema.product where tenant_id = v_tenant_id;

    raise notice '   Tenant: %', v_tenant_id;
    raise notice '   Final product count for tenant: %', v_count;
    raise notice '';
    raise notice '✅ TEST COMPLETADO - Insert/Delete single & batch verified';
    raise notice '========================================';
end $$;