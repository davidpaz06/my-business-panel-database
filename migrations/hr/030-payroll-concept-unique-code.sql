-- ============================================================
-- Migration: 030-payroll-concept-unique-code
-- Schema: hr
-- Date: 2026-09-22
-- Author: Claude (session work)
--
-- Why: hr_schema.provision_tenant_payroll_concepts() only ever ran
-- once per tenant (bailed out if the tenant already had ANY concept
-- row), so a tenant provisioned before this migration never receives
-- new template rows added later (e.g. the deduction concepts added
-- in seeds/catalog/hr/004 for kind-mapped manual deductions used by
-- payroll.service.ts). This constraint lets that function switch to
-- an idempotent "INSERT ... ON CONFLICT (tenant_id, code) DO NOTHING",
-- so re-running it backfills only the rows a tenant is missing.
-- No behavior change for a brand-new tenant (same set of rows either
-- way); existing tenants must re-run the function once to backfill.
-- ============================================================

-- Dedupe previo: datos reales de desarrollo ya tienen (tenant_id, code)
-- duplicados de antes de que este constraint existiera (conceptos viejos
-- de prueba, referenciados desde payroll_movement historico -- no se
-- pueden borrar sin perder el detalle de planillas ya cerradas). Para
-- cada grupo duplicado se renombra el code de todas las filas menos la
-- de concept_id mas alto (la version vigente/mas reciente) a 'OLD<id>'
-- -- cabe en VARCHAR(10) para cualquier id de hasta 6 digitos y deja
-- claro que es un concepto historico. Idempotente: code VARCHAR(10) no
-- vuelve a matchear el patron de duplicado una vez renombrado.
DO $$
DECLARE
  dup RECORD;
BEGIN
  FOR dup IN
    SELECT concept_id
    FROM (
      SELECT concept_id,
        ROW_NUMBER() OVER (PARTITION BY tenant_id, code ORDER BY concept_id DESC) AS rn
      FROM hr_schema.payroll_concept
    ) ranked
    WHERE rn > 1
  LOOP
    UPDATE hr_schema.payroll_concept
    SET code = 'OLD' || dup.concept_id::text
    WHERE concept_id = dup.concept_id;
  END LOOP;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_payroll_concept_tenant_code'
  ) THEN
    ALTER TABLE hr_schema.payroll_concept
      ADD CONSTRAINT uq_payroll_concept_tenant_code UNIQUE (tenant_id, code);
  END IF;
END $$;

-- Rollback (commented, not auto-applied):
-- ALTER TABLE hr_schema.payroll_concept DROP CONSTRAINT IF EXISTS uq_payroll_concept_tenant_code;
