-- ============================================================
-- Plan de Cuentas Plantilla NIIF para PYMES (Costa Rica)
-- ============================================================
-- Este seed NO inserta directamente en chart_of_accounts
-- (esa tabla es por tenant). En su lugar, popula una tabla
-- temporal de plantilla que la función provision_tenant_accounts()
-- usa para copiar cuentas al crear un nuevo tenant.
-- ============================================================

SET SEARCH_PATH TO accounting_schema;

CREATE TABLE IF NOT EXISTS accounting_schema.chart_of_accounts_template (
    template_id SERIAL PRIMARY KEY,
    account_code VARCHAR(20) NOT NULL UNIQUE,
    account_name VARCHAR(150) NOT NULL,
    account_type_id INTEGER NOT NULL REFERENCES accounting_schema.account_type(account_type_id),
    parent_code VARCHAR(20),
    allows_transactions BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE accounting_schema.chart_of_accounts_template IS
    'Template chart of accounts based on NIIF for PYMES (Costa Rica).
     Copied to chart_of_accounts per tenant via provision_tenant_accounts().';

-- Limpiar template para re-seed limpio
TRUNCATE accounting_schema.chart_of_accounts_template RESTART IDENTITY;

-- -------------------------------------------------------
-- 1. ACTIVOS
-- -------------------------------------------------------
INSERT INTO accounting_schema.chart_of_accounts_template(account_code, account_name, account_type_id, parent_code, allows_transactions) VALUES
-- Grupo principal
('1',       'Activos',                          1, NULL,    FALSE),

-- Activo Corriente
('1-1',     'Activo Corriente',                 1, '1',     FALSE),
('1-1-001', 'Caja General',                     1, '1-1',   TRUE),
('1-1-002', 'Bancos',                           1, '1-1',   TRUE),
('1-1-003', 'Cuentas por Cobrar Clientes',      1, '1-1',   TRUE),
('1-1-004', 'Documentos por Cobrar',            1, '1-1',   TRUE),
('1-1-005', 'IVA Crédito Fiscal',               1, '1-1',   TRUE),
('1-1-006', 'Anticipo a Proveedores',           1, '1-1',   TRUE),
('1-1-007', 'Inventario de Mercadería',         1, '1-1',   TRUE),
('1-1-008', 'Inventario de Materia Prima',      1, '1-1',   TRUE),

-- Activo No Corriente
('1-2',     'Activo No Corriente',              1, '1',     FALSE),
('1-2-001', 'Terrenos',                         1, '1-2',   TRUE),
('1-2-002', 'Edificios',                        1, '1-2',   TRUE),
('1-2-003', 'Mobiliario y Equipo',              1, '1-2',   TRUE),
('1-2-004', 'Equipo de Cómputo',                1, '1-2',   TRUE),
('1-2-005', 'Vehículos',                        1, '1-2',   TRUE),
('1-2-006', 'Depreciación Acumulada',           1, '1-2',   TRUE),

-- -------------------------------------------------------
-- 2. PASIVOS
-- -------------------------------------------------------
('2',       'Pasivos',                          2, NULL,    FALSE),

-- Pasivo Corriente
('2-1',     'Pasivo Corriente',                 2, '2',     FALSE),
('2-1-001', 'Cuentas por Pagar Proveedores',    2, '2-1',   TRUE),
('2-1-002', 'Documentos por Pagar',             2, '2-1',   TRUE),
('2-1-003', 'IVA Débito Fiscal',                2, '2-1',   TRUE),
('2-1-004', 'Retenciones por Pagar',            2, '2-1',   TRUE),
('2-1-005', 'Salarios por Pagar',               2, '2-1',   TRUE),
('2-1-006', 'Cargas Sociales por Pagar',        2, '2-1',   TRUE),
('2-1-007', 'Impuesto sobre la Renta por Pagar',2, '2-1',   TRUE),
('2-1-008', 'Anticipos de Clientes',            2, '2-1',   TRUE),

-- Pasivo No Corriente
('2-2',     'Pasivo No Corriente',              2, '2',     FALSE),
('2-2-001', 'Préstamos Bancarios LP',           2, '2-2',   TRUE),
('2-2-002', 'Hipotecas por Pagar',              2, '2-2',   TRUE),

-- -------------------------------------------------------
-- 3. PATRIMONIO
-- -------------------------------------------------------
('3',       'Patrimonio',                       3, NULL,    FALSE),
('3-1',     'Capital Social',                   3, '3',     TRUE),
('3-2',     'Reserva Legal',                    3, '3',     TRUE),
('3-3',     'Utilidades Retenidas',             3, '3',     TRUE),
('3-4',     'Utilidad del Período',             3, '3',     TRUE),
('3-5',     'Pérdida del Período',              3, '3',     TRUE),

-- -------------------------------------------------------
-- 4. INGRESOS
-- -------------------------------------------------------
('4',       'Ingresos',                         4, NULL,    FALSE),
('4-1',     'Ingresos Operativos',              4, '4',     FALSE),
('4-1-001', 'Ingresos por Ventas',              4, '4-1',   TRUE),
('4-1-002', 'Devoluciones sobre Ventas',        4, '4-1',   TRUE),
('4-1-003', 'Descuentos sobre Ventas',          4, '4-1',   TRUE),
('4-2',     'Ingresos No Operativos',           4, '4',     FALSE),
('4-2-001', 'Ingresos por Intereses',           4, '4-2',   TRUE),
('4-2-002', 'Otros Ingresos',                   4, '4-2',   TRUE),

-- -------------------------------------------------------
-- 5. GASTOS
-- -------------------------------------------------------
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

-- -------------------------------------------------------
-- 6. COSTOS
-- -------------------------------------------------------
('6',       'Costos',                           6, NULL,    FALSE),
('6-1',     'Costo de Ventas',                  6, '6',     TRUE),
('6-2',     'Costo de Producción',              6, '6',     TRUE),
('6-3',     'Costo de Mano de Obra Directa',    6, '6',     TRUE);
