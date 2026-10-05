-- Migracion 040: factura de venta con correlativo por tenant y cliente obligatorio.
--
-- Contexto: el cliente (Venezuela) pidio replicar el modelo de factura SENIAT:
--   * numero de factura de 8 digitos (ej. 00055703), correlativo INTERNO del
--     negocio -- por tenant, sin huecos --, que reemplaza al UUID visible;
--   * los datos del comprador son obligatorios: se elimina la venta anonima;
--   * razon social para compradores persona juridica (J/G/C).
-- El codigo de maquina homologada (MH) que traian las facturas fiscales ya no
-- se usa, por eso no se modela.
--
-- Decisiones de diseño:
--   * Las facturas ya emitidas quedan como estan: invoice_number y tenant_id
--     quedan NULL (no se renumera ni se hace backfill).
--   * La numeracion vive en la BD (trigger BEFORE INSERT) porque la factura se
--     crea por dos caminos: sale.service inserta la fila y create_invoice() la
--     crea como respaldo. Un solo punto de asignacion cubre ambos.
--   * El contador usa un upsert que bloquea la fila del tenant hasta el commit:
--     serializa la creacion de facturas por tenant y, si la transaccion falla,
--     el incremento se revierte con ella (sin huecos).
--   * "Cliente obligatorio" va en triggers BEFORE INSERT y NO en un CHECK
--     NOT VALID: un CHECK NOT VALID se vuelve a evaluar en cada UPDATE de las
--     filas viejas (p. ej. reembolsar una venta anonima historica) y las
--     rechazaria.
--   * create_invoice() deja de tragarse los errores (exception when others):
--     con numeracion y cliente obligatorio, un fallo silencioso cerraria la
--     venta sin factura.

SET SEARCH_PATH TO pos_schema;

-- 1. Razon social del comprador (obligatoria por API cuando el tipo es J/G/C).
ALTER TABLE general_schema.tenant_customer
    ADD COLUMN IF NOT EXISTS business_name VARCHAR(200);

COMMENT ON COLUMN general_schema.tenant_customer.business_name IS
    'Razon social del cliente. Se imprime en la factura en lugar de first_name/last_name cuando el cliente es persona juridica (J/G/C).';

-- 2. Numero de factura y tenant emisor.
ALTER TABLE pos_schema.invoice
    ADD COLUMN IF NOT EXISTS tenant_id UUID
        REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS invoice_number INTEGER;

COMMENT ON COLUMN pos_schema.invoice.invoice_number IS
    'Correlativo interno por tenant (se muestra con 8 digitos). NULL en facturas emitidas antes de la migracion 040.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_invoice_tenant_number
    ON pos_schema.invoice(tenant_id, invoice_number)
    WHERE invoice_number IS NOT NULL;

-- 3. Contador por tenant.
CREATE TABLE IF NOT EXISTS pos_schema.invoice_counter (
    tenant_id   UUID PRIMARY KEY
        REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    last_number INTEGER NOT NULL DEFAULT 0 CHECK (last_number >= 0),
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Asignacion del numero (BEFORE INSERT en invoice).
CREATE OR REPLACE FUNCTION pos_schema.assign_invoice_number()
RETURNS trigger AS $$
DECLARE
    v_tenant_id UUID;
    v_number INTEGER;
BEGIN
    SELECT b.tenant_id INTO v_tenant_id
    FROM pos_schema.sale s
    JOIN general_schema.branch b ON b.branch_id = s.branch_id
    WHERE s.sale_id = NEW.sale_id;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'No se pudo resolver el tenant de la venta % para numerar la factura', NEW.sale_id;
    END IF;

    INSERT INTO pos_schema.invoice_counter (tenant_id, last_number)
    VALUES (v_tenant_id, 1)
    ON CONFLICT (tenant_id) DO UPDATE
        SET last_number = pos_schema.invoice_counter.last_number + 1,
            updated_at = CURRENT_TIMESTAMP
    RETURNING last_number INTO v_number;

    NEW.tenant_id := v_tenant_id;
    NEW.invoice_number := v_number;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invoice_assign_number ON pos_schema.invoice;
CREATE TRIGGER trg_invoice_assign_number
    BEFORE INSERT ON pos_schema.invoice
    FOR EACH ROW
    EXECUTE FUNCTION pos_schema.assign_invoice_number();

-- 5. Cliente obligatorio en venta y factura nuevas.
CREATE OR REPLACE FUNCTION pos_schema.require_customer()
RETURNS trigger AS $$
BEGIN
    IF NEW.tenant_customer_id IS NULL THEN
        RAISE EXCEPTION 'La tabla % requiere un cliente registrado (tenant_customer_id): la venta anonima no esta permitida', TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sale_require_customer ON pos_schema.sale;
CREATE TRIGGER trg_sale_require_customer
    BEFORE INSERT ON pos_schema.sale
    FOR EACH ROW
    EXECUTE FUNCTION pos_schema.require_customer();

DROP TRIGGER IF EXISTS trg_invoice_require_customer ON pos_schema.invoice;
CREATE TRIGGER trg_invoice_require_customer
    BEFORE INSERT ON pos_schema.invoice
    FOR EACH ROW
    EXECUTE FUNCTION pos_schema.require_customer();

-- 6. create_invoice(): cliente desde la venta (con respaldo al pago para
--    ventas pendientes historicas) y sin tragarse los errores.
CREATE OR REPLACE FUNCTION create_invoice()
returns trigger as $$
declare
    _invoice_id uuid;
    _tenant_customer_id uuid;
    _currency_id INTEGER;
    _subtotal numeric(10,2);
    _tax numeric(10,2);
    _total numeric(10,2);
    _payment_ids uuid[];
    _cash_register_session_id uuid;
    _items_count int;
BEGIN
        raise notice 'Creating invoice for sale: %', new.sale_id;

        if exists(
            select 1 from pos_schema.invoice
            where sale_id = new.sale_id
        ) then
            raise notice 'Invoice already exists for sale: %', new.sale_id;
            return new;
        end if;

        _tenant_customer_id := COALESCE(
            new.tenant_customer_id,
            (
                select tenant_customer_id
                from pos_schema.customer_payment
                where sale_id = new.sale_id
                  and tenant_customer_id is not null
                limit 1
            )
        );

        _currency_id := new.currency_id;

        -- Resolve active cash register session in the branch
        SELECT crs.cash_register_session_id INTO _cash_register_session_id
        FROM pos_schema.cash_register_session crs
        JOIN pos_schema.cash_register cr ON crs.cash_register_id = cr.cash_register_id
        WHERE cr.branch_id = new.branch_id
        AND crs.is_active = true
        LIMIT 1;

        -- Insert invoice with placeholder totals (will be updated from items).
        -- trg_invoice_require_customer rechaza cliente nulo y
        -- trg_invoice_assign_number asigna tenant_id e invoice_number.
        INSERT INTO pos_schema.invoice (
            sale_id,
            tenant_customer_id,
            currency_id,
            subtotal_amount,
            tax_amount,
            total_amount,
            cash_register_session_id
        ) VALUES (
            new.sale_id,
            _tenant_customer_id,
            _currency_id,
            0,
            0,
            0,
            _cash_register_session_id
        ) returning invoice_id into _invoice_id;

        raise notice '   Invoice created: %', _invoice_id;
        raise notice '   Cash Register Session: %', _cash_register_session_id;

        INSERT INTO pos_schema.invoice_item (
            invoice_id,
            sale_item_id,
            tenant_id,
            product_variant_id,
            tax_rate_id,
            description,
            quantity,
            unit_price,
            subtotal,
            tax_rate_percentage,
            tax_amount,
            total_price
        )
        SELECT
            _invoice_id,
            si.sale_item_id,
            si.tenant_id,
            si.product_variant_id,
            p.tax_rate_id,
            COALESCE(pv.variant_name, p.product_name, 'Product'),
            si.quantity,
            si.unit_price,
            si.total_price,
            COALESCE(tr.rate_percentage, 0),
            ROUND(si.total_price * COALESCE(tr.rate_percentage, 0) / 100, 2),
            si.total_price + ROUND(si.total_price * COALESCE(tr.rate_percentage, 0) / 100, 2)
        FROM pos_schema.sale_item si
        JOIN general_schema.product_variant pv
            ON si.tenant_id = pv.tenant_id AND si.product_variant_id = pv.product_variant_id
        LEFT JOIN general_schema.product p ON pv.product_id = p.product_id
        LEFT JOIN general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
        WHERE si.sale_id = new.sale_id;

        GET DIAGNOSTICS _items_count = ROW_COUNT;
        raise notice '   % invoice item(s) created', _items_count;

        -- Update invoice totals from items (per-item tax)
        SELECT
            COALESCE(SUM(ii.subtotal), 0),
            COALESCE(SUM(ii.tax_amount), 0)
        INTO _subtotal, _tax
        FROM pos_schema.invoice_item ii
        WHERE ii.invoice_id = _invoice_id;

        _total := _subtotal + _tax;

        UPDATE pos_schema.invoice
        SET subtotal_amount = _subtotal,
            tax_amount = _tax,
            total_amount = _total
        WHERE invoice_id = _invoice_id;

        raise notice '   Subtotal: $%', _subtotal;
        raise notice '   Tax (per-item): $%', _tax;
        raise notice '   Total: $%', _total;

        -- Link verified payments
        select array_agg(customer_payment_id) into _payment_ids
        from pos_schema.customer_payment
        where sale_id = new.sale_id
        and verified = true;

        INSERT INTO pos_schema.invoice_payment(invoice_id, customer_payment_id, payment_amount)
        select
            _invoice_id,
            customer_payment_id,
            payment_amount
        from pos_schema.customer_payment
        where customer_payment_id = any(_payment_ids);

        raise notice '   % payment(s) linked to invoice', array_length(_payment_ids, 1);
        raise notice '';
        raise notice 'Invoice creation completed successfully';
        raise notice '   Invoice ID: %', _invoice_id;
        raise notice '   Sale ID: %', new.sale_id;

        return new;
end;
$$ language plpgsql;

-- 7. Cableado del trigger. La migracion 021 renombro la tabla pero nunca
--    recableo el trigger: en entornos construidos por migraciones (no por
--    bootstrap) sigue activo on_sale_completed_create_digital_sale_invoice,
--    que apunta a una tabla inexistente y traga el error, y create_invoice()
--    no esta conectado. Se alinea con pos_functions.sql (fuente de verdad).
--    El flujo principal no cambia: sale.service inserta la venta ya completada
--    (INSERT no dispara este trigger de UPDATE) y crea la factura el mismo;
--    el trigger solo cubre ventas que se completan despues por UPDATE.
DROP TRIGGER IF EXISTS on_sale_completed_create_bill ON pos_schema.sale;
DROP TRIGGER IF EXISTS on_sale_completed_create_digital_sale_invoice ON pos_schema.sale;
DROP TRIGGER IF EXISTS on_sale_completed_create_invoice ON pos_schema.sale;
CREATE TRIGGER on_sale_completed_create_invoice
    AFTER UPDATE OF is_completed ON pos_schema.sale
    FOR EACH ROW
    WHEN (old.is_completed IS FALSE AND new.is_completed IS TRUE)
    EXECUTE FUNCTION create_invoice();

DROP FUNCTION IF EXISTS pos_schema.create_digital_sale_invoice();

-- Rollback (comentado, documentacion -- no se ejecuta automaticamente):
-- DROP TRIGGER IF EXISTS on_sale_completed_create_invoice ON pos_schema.sale;
-- (el trigger/funcion legacy create_digital_sale_invoice no se restauran: apuntaban a una tabla inexistente)
-- DROP TRIGGER IF EXISTS trg_invoice_require_customer ON pos_schema.invoice;
-- DROP TRIGGER IF EXISTS trg_sale_require_customer ON pos_schema.sale;
-- DROP TRIGGER IF EXISTS trg_invoice_assign_number ON pos_schema.invoice;
-- DROP FUNCTION IF EXISTS pos_schema.require_customer();
-- DROP FUNCTION IF EXISTS pos_schema.assign_invoice_number();
-- DROP TABLE IF EXISTS pos_schema.invoice_counter;
-- DROP INDEX IF EXISTS pos_schema.uq_invoice_tenant_number;
-- ALTER TABLE pos_schema.invoice DROP COLUMN IF EXISTS invoice_number, DROP COLUMN IF EXISTS tenant_id;
-- ALTER TABLE general_schema.tenant_customer DROP COLUMN IF EXISTS business_name;
-- Restaurar create_invoice() a su version previa desde functions/pos/pos_functions.sql
-- en el commit anterior a esta migracion (cliente desde customer_payment + exception when others).
