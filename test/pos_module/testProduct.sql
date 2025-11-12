-- =====================================
-- SCRIPT DE PRUEBA DE PRODUCTOS
-- =====================================
-- Este script prueba todas las funcionalidades de la tabla product:
-- - Inserción de productos
-- - Particionamiento por tenant_id
-- - Full-Text Search (FTS)
-- - Búsquedas JSONB
-- - Índices y constraints
-- =====================================

-- ========================================
-- SECCIÓN 1: Preparación - Crear tenants y productos
-- ========================================
do $$
declare
    v_tenant1 uuid;
    v_tenant2 uuid;
    v_prod_id uuid;
begin
    -- Obtener o crear tenant1 (Comercio de Prueba)
    select tenant_id into v_tenant1
    from core.tenant
    where name = 'Comercio de Prueba';

    if v_tenant1 is null then
        insert into core.tenant(name, contact_email)
        values ('Comercio de Prueba', 'comercio@prueba.com')
        returning tenant_id into v_tenant1;
        raise notice 'Tenant1 creado: %', v_tenant1;
    else
        raise notice 'Tenant1 existente: %', v_tenant1;
    end if;

    -- Crear tenant2 (Comercio B)
    insert into core.tenant(name, contact_email)
    values ('Comercio B', 'comerciob@prueba.com')
    on conflict (name) do nothing
    returning tenant_id into v_tenant2;
    
    if v_tenant2 is null then
        select tenant_id into v_tenant2
        from core.tenant
        where name = 'Comercio B';
        raise notice 'Tenant2 existente: %', v_tenant2;
    else
        raise notice 'Tenant2 creado: %', v_tenant2;
    end if;

    raise notice '========================================';
    raise notice 'SECCIÓN 1: Preparación de datos';
    raise notice '========================================';
    raise notice 'Tenant1 (Comercio de Prueba): %', v_tenant1;
    raise notice 'Tenant2 (Comercio B): %', v_tenant2;
    raise notice '';

    -- Insertar productos para tenant1 con variedad de atributos
    insert into core.product(tenant_id, sku, product_name, attributes, price)
    values (v_tenant1, 'SKU-MAY-01', 'Mayonesa Clásica', '{"brand":"LaMayonesa","flavor":"clasica","size":"500ml"}'::jsonb, 3.50)
    on conflict (tenant_id, sku) do nothing
    returning product_id into v_prod_id;
    if v_prod_id is not null then
        raise notice '✓ Inserted: Mayonesa Clásica';
    end if;

    insert into core.product(tenant_id, sku, product_name, attributes, price)
    values (v_tenant1, 'SKU-MAY-02', 'Mayonesa Light', '{"brand":"LaMayonesa","light":true,"calories":200}'::jsonb, 3.00)
    on conflict (tenant_id, sku) do nothing
    returning product_id into v_prod_id;
    if v_prod_id is not null then
        raise notice '✓ Inserted: Mayonesa Light';
    end if;

    insert into core.product(tenant_id, sku, product_name, attributes, price)
    values (v_tenant1, 'SKU-KET-01', 'Ketchup Picante', '{"brand":"TomateGood","spicy":true,"size":"350ml"}'::jsonb, 2.50)
    on conflict (tenant_id, sku) do nothing
    returning product_id into v_prod_id;
    if v_prod_id is not null then
        raise notice '✓ Inserted: Ketchup Picante';
    end if;

    insert into core.product(tenant_id, sku, product_name, attributes, price)
    values (v_tenant1, 'SKU-MOS-01', 'Mostaza Dijon', '{"brand":"MostazaFina","type":"dijon","origin":"France"}'::jsonb, 2.80)
    on conflict (tenant_id, sku) do nothing
    returning product_id into v_prod_id;
    if v_prod_id is not null then
        raise notice '✓ Inserted: Mostaza Dijon';
    end if;

    insert into core.product(tenant_id, sku, product_name, attributes, price)
    values (v_tenant1, 'SKU-SAL-01', 'Salsa Barbacoa', '{"brand":"SalsaBBQ","smoky":true}'::jsonb, 3.20)
    on conflict (tenant_id, sku) do nothing
    returning product_id into v_prod_id;
    if v_prod_id is not null then
        raise notice '✓ Inserted: Salsa Barbacoa';
    end if;

    -- Insertar productos para tenant2
    insert into core.product(tenant_id, sku, product_name, attributes, price)
    values (v_tenant2, 'SKU-MAY-01', 'Mayonesa Premium', '{"brand":"OtraMarca","premium":true,"organic":true}'::jsonb, 4.50)
    on conflict (tenant_id, sku) do nothing
    returning product_id into v_prod_id;
    if v_prod_id is not null then
        raise notice '✓ Inserted: Mayonesa Premium (tenant2)';
    end if;

    insert into core.product(tenant_id, sku, product_name, attributes, price)
    values (v_tenant2, 'SKU-SAL-01', 'Salsa de Tomate', '{"brand":"SalsaBuena","tomato":true,"size":"500ml"}'::jsonb, 1.99)
    on conflict (tenant_id, sku) do nothing
    returning product_id into v_prod_id;
    if v_prod_id is not null then
        raise notice '✓ Inserted: Salsa de Tomate (tenant2)';
    end if;

    raise notice '';
    raise notice '✅ SECCIÓN 1 FINALIZADA - Productos insertados';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 2: Prueba de restricción de unicidad
-- ========================================
do $$
declare
    v_tenant1 uuid;
begin
    select tenant_id into v_tenant1
    from core.tenant
    where name = 'Comercio de Prueba';

    raise notice '========================================';
    raise notice '🔍 SECCIÓN 2: Restricción de unicidad (tenant_id, sku)';
    raise notice '========================================';
    
    -- Intentar insertar SKU duplicado (debe fallar)
    begin
        insert into core.product(tenant_id, sku, product_name, price)
        values (v_tenant1, 'SKU-MAY-01', 'Mayonesa Duplicate', 3.50);
        raise notice '❌ ERROR: inserción duplicada no fue rechazada';
    exception when unique_violation then
        raise notice '✅ CORRECTO: unique_violation capturada';
        raise notice '   No se permite SKU duplicado por tenant';
    end;

    -- Verificar que el mismo SKU puede existir en diferentes tenants
    raise notice '';
    raise notice 'Verificando que el mismo SKU puede existir en diferentes tenants...';
    declare
        v_count int;
    begin
        select count(*) into v_count
        from core.product
        where sku = 'SKU-MAY-01';
        
        if v_count >= 2 then
            raise notice '✅ CORRECTO: SKU-MAY-01 existe en % tenants diferentes', v_count;
        else
            raise notice '⚠️  Solo existe en 1 tenant';
        end if;
    end;

    raise notice '';
    raise notice '✅ SECCIÓN 2 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 3: Verificar particiones
-- ========================================
do $$
declare
    v_tenant1 uuid;
    v_tenant2 uuid;
    r record;
begin
    select tenant_id into v_tenant1 from core.tenant where name = 'Comercio de Prueba';
    select tenant_id into v_tenant2 from core.tenant where name = 'Comercio B';

    raise notice '========================================';
    raise notice '🗂️  SECCIÓN 3: Verificar particiones (tableoid)';
    raise notice '========================================';
    raise notice '';

    for r in (
        select product_id, product_name, tenant_id, tableoid::regclass as partition_name
        from core.product
        where tenant_id in (v_tenant1, v_tenant2)
        order by tenant_id, product_name
    ) loop
        raise notice '  % | Tenant: % | Part: %', 
                     rpad(r.product_name, 25), 
                     substring(r.tenant_id::text, 1, 8) || '...', 
                     r.partition_name;
    end loop;

    raise notice '';
    raise notice '✅ SECCIÓN 3 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 4: Pruebas de Full-Text Search (FTS)
-- ========================================
do $$
declare
    v_tenant1 uuid;
    r record;
begin
    select tenant_id into v_tenant1 from core.tenant where name = 'Comercio de Prueba';

    raise notice '========================================';
    raise notice '🔎 SECCIÓN 4: Full-Text Search (FTS)';
    raise notice '========================================';
    
    -- Prueba 4.1: Búsqueda simple con ranking
    raise notice '';
    raise notice '4.1 Buscando "mayonesa" con ranking...';
    for r in (
        select product_name,
               ts_rank(product_name_tsv, to_tsquery('spanish', 'mayonesa')) as rank
        from core.product
        where tenant_id = v_tenant1
          and product_name_tsv @@ to_tsquery('spanish', 'mayonesa')
        order by rank desc
    ) loop
        raise notice '  ✓ % (rank: %)', r.product_name, round(r.rank::numeric, 4);
    end loop;

    -- Prueba 4.2: Autocompletado con prefijo
    raise notice '';
    raise notice '4.2 Autocompletado con prefijo "mayo:*"...';
    for r in (
        select product_name
        from core.product
        where tenant_id = v_tenant1
          and product_name_tsv @@ to_tsquery('spanish', 'mayo:*')
        order by product_name
    ) loop
        raise notice '  ✓ %', r.product_name;
    end loop;

    -- Prueba 4.3: Búsqueda múltiple con OR
    raise notice '';
    raise notice '4.3 Búsqueda múltiple: "ketchup | mostaza"...';
    for r in (
        select product_name
        from core.product
        where tenant_id = v_tenant1
          and product_name_tsv @@ to_tsquery('spanish', 'ketchup | mostaza')
        order by product_name
    ) loop
        raise notice '  ✓ %', r.product_name;
    end loop;

    -- Prueba 4.4: Búsqueda con AND
    raise notice '';
    raise notice '4.4 Búsqueda con AND: "salsa & barbacoa"...';
    for r in (
        select product_name
        from core.product
        where tenant_id = v_tenant1
          and product_name_tsv @@ to_tsquery('spanish', 'salsa & barbacoa')
        order by product_name
    ) loop
        raise notice '  ✓ %', r.product_name;
    end loop;

    raise notice '';
    raise notice '✅ SECCIÓN 4 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 5: Pruebas de búsqueda JSONB
-- ========================================
do $$
declare
    v_tenant1 uuid;
    r record;
begin
    select tenant_id into v_tenant1 from core.tenant where name = 'Comercio de Prueba';

    raise notice '========================================';
    raise notice '📦 SECCIÓN 5: Búsqueda JSONB por contención (@>)';
    raise notice '========================================';
    
    -- Prueba 5.1: Buscar por brand
    raise notice '';
    raise notice '5.1 Productos con brand="LaMayonesa"...';
    for r in (
        select product_name, attributes
        from core.product
        where tenant_id = v_tenant1
          and attributes @> '{"brand":"LaMayonesa"}'
    ) loop
        raise notice '  ✓ %', r.product_name;
    end loop;

    -- Prueba 5.2: Buscar por atributo booleano
    raise notice '';
    raise notice '5.2 Productos con light=true...';
    for r in (
        select product_name, attributes
        from core.product
        where tenant_id = v_tenant1
          and attributes @> '{"light":true}'
    ) loop
        raise notice '  ✓ % | Attrs: %', r.product_name, r.attributes;
    end loop;

    -- Prueba 5.3: Buscar por múltiples atributos
    raise notice '';
    raise notice '5.3 Productos con spicy=true...';
    for r in (
        select product_name, attributes
        from core.product
        where tenant_id = v_tenant1
          and attributes @> '{"spicy":true}'
    ) loop
        raise notice '  ✓ % | Attrs: %', r.product_name, r.attributes;
    end loop;

    -- Prueba 5.4: Buscar por existencia de clave
    raise notice '';
    raise notice '5.4 Productos que tienen el atributo "size"...';
    for r in (
        select product_name, attributes->>'size' as size
        from core.product
        where tenant_id = v_tenant1
          and attributes ? 'size'
    ) loop
        raise notice '  ✓ % | Size: %', r.product_name, r.size;
    end loop;

    raise notice '';
    raise notice '✅ SECCIÓN 5 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 6: Estadísticas de particiones e índices (MEJORADA)
-- ========================================
do $$
declare
    r record;
    v_total_partitions int;
    v_total_products int;
    v_total_indexes int;
    v_total_size bigint;
begin
    raise notice '========================================';
    raise notice '📊 SECCIÓN 6: Estadísticas del sistema';
    raise notice '========================================';
    
    -- Contar particiones
    select count(*) into v_total_partitions
    from pg_class c
    join pg_namespace n on c.relnamespace = n.oid
    where n.nspname = 'core'
      and c.relname like 'product_p%'
      and c.relkind = 'r';  -- solo tablas, no índices
    
    -- Contar productos totales
    select count(*) into v_total_products
    from core.product;
    
    -- Contar índices totales (físicos)
    select count(*) into v_total_indexes
    from pg_class c
    join pg_namespace n on c.relnamespace = n.oid
    where n.nspname = 'core'
      and c.relname like 'product_p%_%_idx'
      and c.relkind = 'i';  -- solo índices
    
    -- Tamaño total (particiones + índices)
    select sum(pg_total_relation_size(c.oid)) into v_total_size
    from pg_class c
    join pg_namespace n on c.relnamespace = n.oid
    where n.nspname = 'core'
      and c.relname like 'product_p%';
    
    raise notice '';
    raise notice '6.1 📊 Resumen general:';
    raise notice '  Particiones: %', v_total_partitions;
    raise notice '  Productos: %', v_total_products;
    raise notice '  Índices físicos: %', v_total_indexes;
    raise notice '  Tamaño total: %', pg_size_pretty(v_total_size);
    raise notice '  Promedio por partición: %', pg_size_pretty(v_total_size / v_total_partitions);
    
    -- Listar particiones con datos
    raise notice '';
    raise notice '6.2 🗂️  Particiones con datos:';
    for r in (
        select 
            c.relname,
            pg_size_pretty(pg_relation_size(c.oid)) as partition_size,
            pg_size_pretty(pg_total_relation_size(c.oid)) as total_size,
            coalesce((select count(*) from only core.product where tableoid = c.oid), 0) as row_count
        from pg_class c
        join pg_namespace n on c.relnamespace = n.oid
        where n.nspname = 'core'
          and c.relname like 'product_p_'
          and c.relkind = 'r'
        order by c.relname
    ) loop
        if r.row_count > 0 then
            raise notice '  ✓ % | Rows: % | Data: % | Total (+ índices): %', 
                         r.relname, r.row_count, r.partition_size, r.total_size;
        end if;
    end loop;
    
    -- Listar índices lógicos (tabla padre)
    raise notice '';
    raise notice '6.3 📇 Índices definidos en core.product (lógicos):';
    for r in (
        select 
            indexname,
            pg_size_pretty(sum(pg_relation_size(c.oid))) as total_size
        from pg_indexes i
        join pg_class c on c.relname like i.tablename || '%'
        where i.schemaname = 'core'
          and i.tablename = 'product'
        group by indexname
        order by indexname
    ) loop
        raise notice '  ✓ % | Total: %', rpad(r.indexname, 35), r.total_size;
    end loop;

    raise notice '';
    raise notice '✅ SECCIÓN 6 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 7: Prueba de actualización automática de product_name_tsv
-- ========================================
do $$
declare
    v_tenant1 uuid;
    v_old_name text;
    v_new_name text;
    v_old_tsv tsvector;
    v_new_tsv tsvector;
begin
    select tenant_id into v_tenant1 from core.tenant where name = 'Comercio de Prueba';

    raise notice '========================================';
    raise notice '🔄 SECCIÓN 7: Actualización automática de product_name_tsv';
    raise notice '========================================';
    
    -- Obtener valores antes de la actualización
    select product_name, product_name_tsv into v_old_name, v_old_tsv
    from core.product
    where tenant_id = v_tenant1
      and sku = 'SKU-MAY-02'
    limit 1;
    
    raise notice '';
    raise notice 'Antes de actualizar:';
    raise notice '  Nombre: %', v_old_name;
    raise notice '  TSV: %', v_old_tsv;
    
    -- Actualizar el nombre del producto
    update core.product
    set product_name = 'Mayonesa Extra Light Premium'
    where tenant_id = v_tenant1
      and sku = 'SKU-MAY-02';
    
    -- Obtener valores después de la actualización
    select product_name, product_name_tsv into v_new_name, v_new_tsv
    from core.product
    where tenant_id = v_tenant1
      and sku = 'SKU-MAY-02'
    limit 1;
    
    raise notice '';
    raise notice 'Después de actualizar:';
    raise notice '  Nombre: %', v_new_name;
    raise notice '  TSV: %', v_new_tsv;
    
    -- Verificar que cambió
    if v_old_tsv <> v_new_tsv then
        raise notice '';
        raise notice '✅ CORRECTO: product_name_tsv se actualizó automáticamente';
    else
        raise notice '';
        raise notice '❌ ERROR: product_name_tsv no se actualizó';
    end if;

    raise notice '';
    raise notice '✅ SECCIÓN 7 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 8: Resumen final
-- ========================================
do $$
declare
    v_count_tenant1 int;
    v_count_tenant2 int;
    v_total int;
    v_count_partitions int;
begin
    select count(*) into v_count_tenant1
    from core.product p
    join core.tenant t on p.tenant_id = t.tenant_id
    where t.name = 'Comercio de Prueba';

    select count(*) into v_count_tenant2
    from core.product p
    join core.tenant t on p.tenant_id = t.tenant_id
    where t.name = 'Comercio B';

    v_total := v_count_tenant1 + v_count_tenant2;
    
    select count(*) into v_count_partitions
    from pg_class c
    join pg_namespace n on c.relnamespace = n.oid
    where n.nspname = 'core' and c.relname like 'product_p%';

    raise notice '========================================';
    raise notice '✅ PRUEBAS DE PRODUCTOS COMPLETADAS';
    raise notice '========================================';
    raise notice '';
    raise notice 'Productos insertados:';
    raise notice '  - Comercio de Prueba: % productos', v_count_tenant1;
    raise notice '  - Comercio B: % productos', v_count_tenant2;
    raise notice '  - TOTAL: % productos', v_total;
    raise notice '';
    raise notice 'Infraestructura:';
    raise notice '  - Particiones: %', v_count_partitions;
    raise notice '  - Índices: 4 (tenant_sku, tenant_btree, name_fts, attributes_gin)';
    raise notice '';
    raise notice 'Pruebas ejecutadas:';
    raise notice '  ✓ Sección 1 - Inserción de productos';
    raise notice '  ✓ Sección 2 - Restricción de unicidad';
    raise notice '  ✓ Sección 3 - Verificación de particiones';
    raise notice '  ✓ Sección 4 - Full-Text Search (FTS)';
    raise notice '  ✓ Sección 5 - Búsquedas JSONB';
    raise notice '  ✓ Sección 6 - Estadísticas del sistema';
    raise notice '  ✓ Sección 7 - Actualización automática TSV';
    raise notice '';
    raise notice '📝 Consultas EXPLAIN ANALYZE disponibles abajo';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- CONSULTAS MANUALES SUGERIDAS (EXPLAIN ANALYZE)
-- ========================================

-- 1️⃣ Ver todos los productos con su partición
-- select product_name, tableoid::regclass as partition, attributes, price
-- from core.product
-- order by tenant_id, product_name;

-- 2️⃣ EXPLAIN de full-text search (verificar uso de idx_product_name_fts)
-- explain (analyze, buffers)
-- select product_name, ts_rank(product_name_tsv, to_tsquery('spanish', 'mayonesa')) as rank
-- from core.product
-- where tenant_id = (select tenant_id from core.tenant where name = 'Comercio de Prueba')
--   and product_name_tsv @@ to_tsquery('spanish', 'mayonesa')
-- order by rank desc;

-- 3️⃣ EXPLAIN de búsqueda JSONB (verificar uso de idx_product_attributes_gin)
-- explain (analyze, buffers)
-- select product_name, attributes
-- from core.product
-- where tenant_id = (select tenant_id from core.tenant where name = 'Comercio de Prueba')
--   and attributes @> '{"brand":"LaMayonesa"}';

-- 4️⃣ EXPLAIN de búsqueda por tenant + FTS (verificar partition pruning)
-- explain (analyze, buffers, verbose)
-- select product_name
-- from core.product
-- where tenant_id = (select tenant_id from core.tenant where name = 'Comercio de Prueba')
--   and product_name_tsv @@ to_tsquery('spanish', 'ketchup | mostaza')
-- order by product_name;

-- 5️⃣ Estadísticas de particiones con número de filas
-- select 
--     schemaname,
--     tablename,
--     pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
--     n_live_tup as rows
-- from pg_stat_user_tables
-- where schemaname = 'core'
--   and tablename like 'product_p%'
-- order by tablename;

-- 6️⃣ Ver distribución de productos por partición
-- select 
--     tableoid::regclass as partition,
--     count(*) as product_count
-- from core.product
-- group by tableoid::regclass
-- order by partition;

-- 7️⃣ Verificar que updated_at se actualiza automáticamente
-- select product_name, created_at, updated_at
-- from core.product
-- where tenant_id = (select tenant_id from core.tenant where name = 'Comercio de Prueba')
-- order by updated_at desc;
