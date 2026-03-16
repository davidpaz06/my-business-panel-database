-- ============================================================
-- Migration 012: Add Accounting Schema
-- Module 4.1 - Contabilidad General y Registros Automatizados
-- ============================================================
-- This migration creates the full accounting schema from scratch.
-- Safe to run on databases that don't have it yet.
-- ============================================================

BEGIN;

-- -------------------------------------------------------
-- 1. CREATE SCHEMA
-- -------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS accounting_schema;

-- -------------------------------------------------------
-- 2. CATALOG TABLES
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.account_type (
    account_type_id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) UNIQUE NOT NULL,
    nature VARCHAR(10) NOT NULL CHECK (nature IN ('DEBIT', 'CREDIT')),
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS accounting_schema.journal_entry_status (
    status_id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS accounting_schema.source_type (
    source_type_id SERIAL PRIMARY KEY,
    source_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------
-- 3. COST CENTERS
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.cost_center (
    cost_center_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    center_code VARCHAR(20) NOT NULL,
    center_name VARCHAR(100) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(tenant_id, center_code)
);

CREATE INDEX IF NOT EXISTS idx_cost_center_tenant
    ON accounting_schema.cost_center(tenant_id);

-- -------------------------------------------------------
-- 4. CHART OF ACCOUNTS
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.chart_of_accounts (
    account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    account_code VARCHAR(20) NOT NULL,
    account_name VARCHAR(150) NOT NULL,
    account_type_id INTEGER NOT NULL REFERENCES accounting_schema.account_type(account_type_id),
    parent_account_id UUID REFERENCES accounting_schema.chart_of_accounts(account_id) ON DELETE SET NULL,
    cost_center_id UUID REFERENCES accounting_schema.cost_center(cost_center_id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_system BOOLEAN DEFAULT FALSE,
    allows_transactions BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(tenant_id, account_code),
    CONSTRAINT chk_no_self_parent CHECK (account_id != parent_account_id)
);

CREATE INDEX IF NOT EXISTS idx_coa_tenant ON accounting_schema.chart_of_accounts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_coa_parent ON accounting_schema.chart_of_accounts(parent_account_id) WHERE parent_account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_coa_type ON accounting_schema.chart_of_accounts(account_type_id);
CREATE INDEX IF NOT EXISTS idx_coa_tenant_active ON accounting_schema.chart_of_accounts(tenant_id, is_active) WHERE is_active = TRUE;

-- -------------------------------------------------------
-- 5. JOURNAL ENTRIES
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.journal_entry (
    entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    entry_number SERIAL,
    source_type_id INTEGER NOT NULL REFERENCES accounting_schema.source_type(source_type_id),
    source_id UUID,
    entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
    description TEXT,
    status_id INTEGER NOT NULL DEFAULT 1 REFERENCES accounting_schema.journal_entry_status(status_id),
    total_debit NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (total_debit >= 0),
    total_credit NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (total_credit >= 0),
    created_by UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(tenant_id, entry_number)
);

CREATE INDEX IF NOT EXISTS idx_je_tenant ON accounting_schema.journal_entry(tenant_id);
CREATE INDEX IF NOT EXISTS idx_je_date ON accounting_schema.journal_entry(tenant_id, entry_date);
CREATE INDEX IF NOT EXISTS idx_je_source ON accounting_schema.journal_entry(source_type_id, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_je_status ON accounting_schema.journal_entry(status_id);

-- -------------------------------------------------------
-- 6. JOURNAL ENTRY LINES
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.journal_entry_line (
    line_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id UUID NOT NULL REFERENCES accounting_schema.journal_entry(entry_id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounting_schema.chart_of_accounts(account_id),
    cost_center_id UUID REFERENCES accounting_schema.cost_center(cost_center_id) ON DELETE SET NULL,
    debit_amount NUMERIC(14,4) NOT NULL DEFAULT 0,
    credit_amount NUMERIC(14,4) NOT NULL DEFAULT 0,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_positive_amounts CHECK (debit_amount >= 0 AND credit_amount >= 0),
    CONSTRAINT chk_single_side CHECK (NOT (debit_amount > 0 AND credit_amount > 0))
);

CREATE INDEX IF NOT EXISTS idx_jel_entry ON accounting_schema.journal_entry_line(entry_id);
CREATE INDEX IF NOT EXISTS idx_jel_account ON accounting_schema.journal_entry_line(account_id);

-- -------------------------------------------------------
-- 7. ACCOUNTING MAPPING RULES
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.accounting_mapping_rule (
    rule_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    source_type_id INTEGER NOT NULL REFERENCES accounting_schema.source_type(source_type_id),
    rule_name VARCHAR(100) NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(tenant_id, source_type_id, rule_name)
);

CREATE TABLE IF NOT EXISTS accounting_schema.accounting_mapping_rule_line (
    rule_line_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id UUID NOT NULL REFERENCES accounting_schema.accounting_mapping_rule(rule_id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounting_schema.chart_of_accounts(account_id),
    side VARCHAR(6) NOT NULL CHECK (side IN ('DEBIT', 'CREDIT')),
    amount_field VARCHAR(50) NOT NULL,
    line_order INTEGER NOT NULL DEFAULT 0,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(rule_id, line_order)
);

CREATE INDEX IF NOT EXISTS idx_amrl_rule ON accounting_schema.accounting_mapping_rule_line(rule_id);

-- -------------------------------------------------------
-- 8. CHART OF ACCOUNTS TEMPLATE
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.chart_of_accounts_template (
    template_id SERIAL PRIMARY KEY,
    account_code VARCHAR(20) NOT NULL UNIQUE,
    account_name VARCHAR(150) NOT NULL,
    account_type_id INTEGER NOT NULL REFERENCES accounting_schema.account_type(account_type_id),
    parent_code VARCHAR(20),
    allows_transactions BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------
-- 9. SEED CATALOGS
-- -------------------------------------------------------

INSERT INTO accounting_schema.account_type(type_name, nature, description) VALUES
('Activo', 'DEBIT', 'Bienes y derechos de la empresa'),
('Pasivo', 'CREDIT', 'Obligaciones y deudas de la empresa'),
('Patrimonio', 'CREDIT', 'Capital y resultados acumulados'),
('Ingreso', 'CREDIT', 'Ingresos operativos y no operativos'),
('Gasto', 'DEBIT', 'Gastos operativos y administrativos'),
('Costo', 'DEBIT', 'Costos directos de producción y venta')
ON CONFLICT DO NOTHING;

INSERT INTO accounting_schema.journal_entry_status(status_name, description) VALUES
('Borrador', 'Asiento en estado de borrador, pendiente de confirmación'),
('Confirmado', 'Asiento confirmado y registrado en el libro mayor'),
('Anulado', 'Asiento anulado, no afecta los estados financieros')
ON CONFLICT DO NOTHING;

INSERT INTO accounting_schema.source_type(source_name, description) VALUES
('SALE_CASH', 'Venta al contado'),
('SALE_CREDIT', 'Venta a crédito'),
('SALE_COGS', 'Costo de venta asociado a una venta'),
('PURCHASE', 'Compra de inventario o servicios'),
('PAYMENT_RECEIVED', 'Pago recibido de cliente'),
('PAYMENT_MADE', 'Pago realizado a proveedor'),
('PAYROLL', 'Registro de nómina'),
('MANUAL', 'Asiento manual ingresado por el usuario'),
('ADJUSTMENT', 'Ajuste contable')
ON CONFLICT DO NOTHING;

-- -------------------------------------------------------
-- 10. SEED CHART OF ACCOUNTS TEMPLATE (NIIF PYMES CR)
-- -------------------------------------------------------

TRUNCATE accounting_schema.chart_of_accounts_template RESTART IDENTITY;

INSERT INTO accounting_schema.chart_of_accounts_template(account_code, account_name, account_type_id, parent_code, allows_transactions) VALUES
-- ACTIVOS
('1',       'Activos',                          1, NULL,    FALSE),
('1-1',     'Activo Corriente',                 1, '1',     FALSE),
('1-1-001', 'Caja General',                     1, '1-1',   TRUE),
('1-1-002', 'Bancos',                           1, '1-1',   TRUE),
('1-1-003', 'Cuentas por Cobrar Clientes',      1, '1-1',   TRUE),
('1-1-004', 'Documentos por Cobrar',            1, '1-1',   TRUE),
('1-1-005', 'IVA Crédito Fiscal',               1, '1-1',   TRUE),
('1-1-006', 'Anticipo a Proveedores',           1, '1-1',   TRUE),
('1-1-007', 'Inventario de Mercadería',         1, '1-1',   TRUE),
('1-1-008', 'Inventario de Materia Prima',      1, '1-1',   TRUE),
('1-2',     'Activo No Corriente',              1, '1',     FALSE),
('1-2-001', 'Terrenos',                         1, '1-2',   TRUE),
('1-2-002', 'Edificios',                        1, '1-2',   TRUE),
('1-2-003', 'Mobiliario y Equipo',              1, '1-2',   TRUE),
('1-2-004', 'Equipo de Cómputo',                1, '1-2',   TRUE),
('1-2-005', 'Vehículos',                        1, '1-2',   TRUE),
('1-2-006', 'Depreciación Acumulada',           1, '1-2',   TRUE),
-- PASIVOS
('2',       'Pasivos',                          2, NULL,    FALSE),
('2-1',     'Pasivo Corriente',                 2, '2',     FALSE),
('2-1-001', 'Cuentas por Pagar Proveedores',    2, '2-1',   TRUE),
('2-1-002', 'Documentos por Pagar',             2, '2-1',   TRUE),
('2-1-003', 'IVA Débito Fiscal',                2, '2-1',   TRUE),
('2-1-004', 'Retenciones por Pagar',            2, '2-1',   TRUE),
('2-1-005', 'Salarios por Pagar',               2, '2-1',   TRUE),
('2-1-006', 'Cargas Sociales por Pagar',        2, '2-1',   TRUE),
('2-1-007', 'Impuesto sobre la Renta por Pagar',2, '2-1',   TRUE),
('2-1-008', 'Anticipos de Clientes',            2, '2-1',   TRUE),
('2-2',     'Pasivo No Corriente',              2, '2',     FALSE),
('2-2-001', 'Préstamos Bancarios LP',           2, '2-2',   TRUE),
('2-2-002', 'Hipotecas por Pagar',              2, '2-2',   TRUE),
-- PATRIMONIO
('3',       'Patrimonio',                       3, NULL,    FALSE),
('3-1',     'Capital Social',                   3, '3',     TRUE),
('3-2',     'Reserva Legal',                    3, '3',     TRUE),
('3-3',     'Utilidades Retenidas',             3, '3',     TRUE),
('3-4',     'Utilidad del Período',             3, '3',     TRUE),
('3-5',     'Pérdida del Período',              3, '3',     TRUE),
-- INGRESOS
('4',       'Ingresos',                         4, NULL,    FALSE),
('4-1',     'Ingresos Operativos',              4, '4',     FALSE),
('4-1-001', 'Ingresos por Ventas',              4, '4-1',   TRUE),
('4-1-002', 'Devoluciones sobre Ventas',        4, '4-1',   TRUE),
('4-1-003', 'Descuentos sobre Ventas',          4, '4-1',   TRUE),
('4-2',     'Ingresos No Operativos',           4, '4',     FALSE),
('4-2-001', 'Ingresos por Intereses',           4, '4-2',   TRUE),
('4-2-002', 'Otros Ingresos',                   4, '4-2',   TRUE),
-- GASTOS
('5',       'Gastos',                           5, NULL,    FALSE),
('5-1',     'Gastos Operativos',                5, '5',     FALSE),
('5-1-001', 'Salarios y Sueldos',               5, '5-1',   TRUE),
('5-1-002', 'Cargas Sociales',                  5, '5-1',   TRUE),
('5-1-003', 'Alquiler',                         5, '5-1',   TRUE),
('5-1-004', 'Servicios Públicos',               5, '5-1',   TRUE),
('5-1-005', 'Depreciación',                     5, '5-1',   TRUE),
('5-1-006', 'Seguros',                          5, '5-1',   TRUE),
('5-1-007', 'Suministros de Oficina',           5, '5-1',   TRUE),
('5-1-008', 'Mantenimiento y Reparaciones',     5, '5-1',   TRUE),
('5-1-009', 'Publicidad y Mercadeo',            5, '5-1',   TRUE),
('5-1-010', 'Gastos de Viaje',                  5, '5-1',   TRUE),
('5-2',     'Gastos Financieros',               5, '5',     FALSE),
('5-2-001', 'Intereses Pagados',                5, '5-2',   TRUE),
('5-2-002', 'Comisiones Bancarias',             5, '5-2',   TRUE),
('5-2-003', 'Diferencial Cambiario',            5, '5-2',   TRUE),
-- COSTOS
('6',       'Costos',                           6, NULL,    FALSE),
('6-1',     'Costo de Ventas',                  6, '6',     TRUE),
('6-2',     'Costo de Producción',              6, '6',     TRUE),
('6-3',     'Costo de Mano de Obra Directa',    6, '6',     TRUE);

-- -------------------------------------------------------
-- 11. FUNCTIONS
-- -------------------------------------------------------

CREATE OR REPLACE FUNCTION accounting_schema.validate_journal_balance(_entry_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    _total_debit NUMERIC(14,4);
    _total_credit NUMERIC(14,4);
    _line_count INT;
BEGIN
    SELECT count(*), coalesce(sum(debit_amount), 0), coalesce(sum(credit_amount), 0)
    INTO _line_count, _total_debit, _total_credit
    FROM accounting_schema.journal_entry_line
    WHERE entry_id = _entry_id;

    IF _line_count = 0 THEN
        RAISE EXCEPTION 'Journal entry % has no lines', _entry_id;
    END IF;
    IF _line_count < 2 THEN
        RAISE EXCEPTION 'Journal entry % must have at least 2 lines', _entry_id;
    END IF;
    IF _total_debit != _total_credit THEN
        RAISE EXCEPTION 'Journal entry % is unbalanced: debits=% credits=%',
            _entry_id, _total_debit, _total_credit;
    END IF;

    UPDATE accounting_schema.journal_entry
    SET total_debit = _total_debit, total_credit = _total_credit, updated_at = CURRENT_TIMESTAMP
    WHERE entry_id = _entry_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION accounting_schema.confirm_journal_entry(_entry_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    _current_status INT;
    _status_borrador INT;
    _status_confirmado INT;
BEGIN
    SELECT status_id INTO _status_borrador FROM accounting_schema.journal_entry_status WHERE status_name = 'Borrador';
    SELECT status_id INTO _status_confirmado FROM accounting_schema.journal_entry_status WHERE status_name = 'Confirmado';
    SELECT status_id INTO _current_status FROM accounting_schema.journal_entry WHERE entry_id = _entry_id;

    IF _current_status IS NULL THEN RAISE EXCEPTION 'Journal entry % not found', _entry_id; END IF;
    IF _current_status != _status_borrador THEN
        RAISE EXCEPTION 'Journal entry % is not in Borrador status', _entry_id;
    END IF;

    PERFORM accounting_schema.validate_journal_balance(_entry_id);

    UPDATE accounting_schema.journal_entry
    SET status_id = _status_confirmado, updated_at = CURRENT_TIMESTAMP
    WHERE entry_id = _entry_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION accounting_schema.void_journal_entry(_entry_id UUID, _voided_by UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    _status_confirmado INT;
    _status_anulado INT;
    _entry RECORD;
    _reversal_id UUID;
    _source_type_adj INT;
BEGIN
    SELECT status_id INTO _status_confirmado FROM accounting_schema.journal_entry_status WHERE status_name = 'Confirmado';
    SELECT status_id INTO _status_anulado FROM accounting_schema.journal_entry_status WHERE status_name = 'Anulado';
    SELECT * INTO _entry FROM accounting_schema.journal_entry WHERE entry_id = _entry_id;

    IF _entry IS NULL THEN RAISE EXCEPTION 'Journal entry % not found', _entry_id; END IF;
    IF _entry.status_id != _status_confirmado THEN
        RAISE EXCEPTION 'Only confirmed entries can be voided (entry %)', _entry_id;
    END IF;

    SELECT source_type_id INTO _source_type_adj FROM accounting_schema.source_type WHERE source_name = 'ADJUSTMENT';

    UPDATE accounting_schema.journal_entry
    SET status_id = _status_anulado, updated_at = CURRENT_TIMESTAMP
    WHERE entry_id = _entry_id;

    INSERT INTO accounting_schema.journal_entry(
        tenant_id, source_type_id, source_id, entry_date,
        description, status_id, total_debit, total_credit, created_by
    ) VALUES (
        _entry.tenant_id, _source_type_adj, _entry_id, CURRENT_DATE,
        'Reversión de asiento ' || _entry.entry_number,
        _status_confirmado, _entry.total_debit, _entry.total_credit, _voided_by
    ) RETURNING entry_id INTO _reversal_id;

    INSERT INTO accounting_schema.journal_entry_line(
        entry_id, account_id, cost_center_id, debit_amount, credit_amount, description
    )
    SELECT _reversal_id, account_id, cost_center_id,
           credit_amount, debit_amount,
           'Reversión: ' || coalesce(description, '')
    FROM accounting_schema.journal_entry_line
    WHERE entry_id = _entry_id;

    RETURN _reversal_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION accounting_schema.provision_tenant_accounts(_tenant_id UUID)
RETURNS INT AS $$
DECLARE
    _template RECORD;
    _parent_id UUID;
    _inserted INT := 0;
    _account_map JSONB := '{}';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM general_schema.tenant WHERE tenant_id = _tenant_id) THEN
        RAISE EXCEPTION 'Tenant % not found', _tenant_id;
    END IF;
    IF EXISTS (SELECT 1 FROM accounting_schema.chart_of_accounts WHERE tenant_id = _tenant_id LIMIT 1) THEN
        RAISE NOTICE 'Tenant % already has chart of accounts provisioned', _tenant_id;
        RETURN 0;
    END IF;

    FOR _template IN
        SELECT * FROM accounting_schema.chart_of_accounts_template ORDER BY account_code
    LOOP
        _parent_id := NULL;
        IF _template.parent_code IS NOT NULL THEN
            _parent_id := (_account_map ->> _template.parent_code)::UUID;
        END IF;

        INSERT INTO accounting_schema.chart_of_accounts(
            tenant_id, account_code, account_name, account_type_id,
            parent_account_id, is_active, is_system, allows_transactions
        ) VALUES (
            _tenant_id, _template.account_code, _template.account_name, _template.account_type_id,
            _parent_id, TRUE, TRUE, _template.allows_transactions
        ) RETURNING account_id INTO _parent_id;

        _account_map := _account_map || jsonb_build_object(_template.account_code, _parent_id::TEXT);
        _inserted := _inserted + 1;
    END LOOP;

    RAISE NOTICE 'Provisioned % accounts for tenant %', _inserted, _tenant_id;
    RETURN _inserted;
END;
$$ LANGUAGE plpgsql;

COMMIT;
