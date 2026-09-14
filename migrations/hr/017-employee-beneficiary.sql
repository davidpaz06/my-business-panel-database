-- ============================================================
-- Migracion: 017-employee-beneficiary
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Crea el registro de beneficiarios para el caso de fallecimiento.
-- Por que: el Art. 145 establece que al fallecer el trabajador las
--   prestaciones se distribuyen en PARTES IGUALES entre hijos,
--   conyuge o pareja estable, padres y nietos huerfanos, SIN
--   preferencia ni prelacion entre ellos. Esto tiene dos
--   consecuencias que obligan a una tabla propia:
--   1. El reparto no es un porcentaje pactado sino una division
--      aritmetica entre los reclamantes VALIDOS que se presenten
--      dentro de los 3 meses siguientes. El divisor no se conoce
--      hasta que cierra esa ventana, por lo que hay que registrar
--      cada reclamante con su fecha de reclamo y su validacion.
--   2. Sin preferencia significa que un hijo y un abuelo reclaman
--      lo mismo. El parentesco se guarda para acreditar el derecho,
--      no para ordenar prioridades.
--   share_percentage se persiste calculado al cerrar la ventana,
--   para dejar constancia del divisor efectivamente aplicado.
-- Base legal: Art. 145.
-- Autor/Fecha: 2026-08-27
-- ============================================================

CREATE TABLE IF NOT EXISTS hr_schema.employee_beneficiary (
	beneficiary_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	settlement_id UUID REFERENCES hr_schema.settlement(settlement_id) ON DELETE SET NULL,
	full_name VARCHAR(200) NOT NULL,
	doc_number VARCHAR(100) NOT NULL,
	identification_type_id INTEGER REFERENCES general_schema.identification_type(identification_type_id) ON DELETE SET NULL,
	relationship VARCHAR(20) NOT NULL,
	birth_date DATE,
	claim_date DATE,
	validated BOOLEAN NOT NULL DEFAULT FALSE,
	validated_at DATE,
	share_percentage NUMERIC(7, 4),
	share_amount NUMERIC(18, 4),
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_employee_beneficiary_doc UNIQUE (employee_id, doc_number),
	CONSTRAINT chk_beneficiary_relationship CHECK (relationship IN ('hijo', 'conyuge', 'pareja_estable', 'padre', 'madre', 'nieto_huerfano')),
	CONSTRAINT chk_beneficiary_share CHECK (share_percentage IS NULL OR (share_percentage > 0 AND share_percentage <= 100)),
	CONSTRAINT chk_beneficiary_validacion CHECK (validated = FALSE OR validated_at IS NOT NULL)
);

COMMENT ON TABLE hr_schema.employee_beneficiary IS
	'Beneficiarios de las prestaciones en caso de fallecimiento (Art. 145). El reparto es en partes iguales entre los reclamantes validos, sin preferencia entre parentescos.';

COMMENT ON COLUMN hr_schema.employee_beneficiary.relationship IS
	'Parentesco acreditado (Art. 145): hijo, conyuge, pareja_estable, padre, madre, nieto_huerfano. Sirve para acreditar el derecho, NO para establecer prelacion: todos concurren en partes iguales.';

COMMENT ON COLUMN hr_schema.employee_beneficiary.claim_date IS
	'Fecha en que el beneficiario presento su reclamo. La ventana legal es de 3 meses siguientes al fallecimiento; el divisor del reparto se fija al cerrarla.';

COMMENT ON COLUMN hr_schema.employee_beneficiary.validated IS
	'TRUE = parentesco acreditado y reclamo admitido. Solo los validados entran en el divisor del reparto.';

COMMENT ON COLUMN hr_schema.employee_beneficiary.share_percentage IS
	'Porcentaje efectivamente aplicado, calculado al cerrar la ventana de reclamos: 100 dividido entre el numero de beneficiarios validados. Se persiste para dejar constancia del divisor usado.';

CREATE INDEX IF NOT EXISTS idx_beneficiary_employee
	ON hr_schema.employee_beneficiary (employee_id);

CREATE INDEX IF NOT EXISTS idx_beneficiary_settlement
	ON hr_schema.employee_beneficiary (settlement_id);

CREATE INDEX IF NOT EXISTS idx_beneficiary_tenant
	ON hr_schema.employee_beneficiary (tenant_id);

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_beneficiary_tenant;
-- DROP INDEX IF EXISTS hr_schema.idx_beneficiary_settlement;
-- DROP INDEX IF EXISTS hr_schema.idx_beneficiary_employee;
-- DROP TABLE IF EXISTS hr_schema.employee_beneficiary;
