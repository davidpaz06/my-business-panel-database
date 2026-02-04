# Paysheet (Payroll) — End-to-End Flow

This document explains the paysheet (payroll) flow in the HR module: how a paysheet and its details are created, how income entries update gross salary via triggers, how recalculation states are enforced, how the paysheet is closed, and how to generate a monthly CCSS report. The flow REFERENCES `hr_schema` tables, triggers, and functions defined in the project.

Scope: create and manage paysheets for employees, aggregate income concepts into gross salary, validate readiness for closure, finalize the paysheet, and compute CCSS totals by month.

## Prerequisites

- general_schema data: a `general_schema.branch` to attribute the paysheet, and valid `general_schema.payment_method` IDs for employee payments in `paysheet_detail`.
- Employees: existing employees in `hr_schema.employee` (can be created via `hr_schema.create_new_employee`).
- HR objects: deployed `hr_schema.paysheet`, `hr_schema.paysheet_detail`, `hr_schema.income_concept`, `hr_schema.income_register`, and status catalog `hr_schema.paysheet_status` with at least `Pending`, `Completed`, `Canceled`.
- Triggers & functions: trigger `update_gross_salary` over `income_register`; trigger `protect_net_salary` over `paysheet_detail`; functions `hr_schema.update_paysheet_state` and `hr_schema.generate_monthly_ccss`.

## High-level Flow

1. Insert a `paysheet` for a branch and a period (start/end dates and payment day).
2. Insert one or more `paysheet_detail` rows (one per employee) with an initial `gross_salary` (often 0), `recalc_needed = TRUE`.
3. Insert `income_concept` catalog entries (if needed) and then `income_register` rows per detail to represent salary components. A trigger sums them into `paysheet_detail.gross_salary` and sets `recalc_needed = TRUE`.
4. Run the calculation engine (in the backend) to compute deductions and `net_salary`, then update `paysheet_detail` with final amounts and set `recalc_needed = FALSE`.
5. Close the paysheet by calling `hr_schema.update_paysheet_state(p_paysheet_id)`. It verifies no detail requires recalculation and sets status to `Completed`.
6. Generate the monthly CCSS report via `hr_schema.generate_monthly_ccss(p_year, p_month)
(Functionality for the phase 2)
`.

## Detailed Steps & SQL snippets

### 1) Create paysheet and detail(s)

```sql
-- Status lookup (recommended, or store it in app config)
SELECT status_id
FROM hr_schema.paysheet_status
WHERE status_description = 'Pending';

-- Minimal paysheet (example dates)
INSERT INTO hr_schema.paysheet (
	branch_id, period_start_date, period_end_date, payment_day, payment_amount, paysheet_status_id
)
VALUES (
	<branch_id>,
	DATE '2025-12-01',
	DATE '2025-12-31',
	DATE '2025-12-31',
	0.00,
	1 --Status "Pending"
)
RETURNING paysheet_id;

-- For each employee (one detail per employee)
INSERT INTO hr_schema.paysheet_detail (
	paysheet_id, employee_id, payment_method_id,
	gross_salary, ccss_employee_deduction, ccss_tenant_deduction,
	income_tax_amount, total_deduction, net_salary, pay_date, recalc_needed
)
VALUES (
	<paysheet_id>,
	<employee_id>,
	<payment_method_id>,
	0.00, 0.00, 0.00,
	0.00, 0.00, 0.00,
	DATE '2025-12-31',
	TRUE
)
RETURNING detail_id;
```

Notes

- `paysheet_detail.gross_salary` has a CHECK `>= 0`. Let the trigger maintain its value from `income_register` inserts.
- `recalc_needed` indicates downstream calculations (deductions/taxes) must still run.

### 2) Define income concepts (catalog)

```sql
INSERT INTO hr_schema.income_concept (concept_name, calculation_type, ccss_apply, tax_apply)
VALUES ('Base Salary', 'Fixed', FALSE, FALSE)
ON CONFLICT DO NOTHING;
```

### 3) Register income for a detail (trigger updates gross salary)

```sql
-- Add/modify income components for the employee detail
INSERT INTO hr_schema.income_register (detail_id, concept_id, base_quantity, calculated_amount)
VALUES (<detail_id>, <concept_id>, 1.00, 2500.00);

-- The trigger `update_gross_salary` runs AFTER insert/update/delete on income_register:
-- - Sums all `calculated_amount` by detail into `paysheet_detail.gross_salary`
-- - Sets `recalc_needed = TRUE`

-- Quick check
SELECT gross_salary, recalc_needed
FROM hr_schema.paysheet_detail
WHERE detail_id = <detail_id>;
```

### 4) Apply deductions and finalize detail

The calculation engine should compute and update:

- `ccss_employee_deduction`, `ccss_tenant_deduction`
- `income_tax_amount`, `total_deduction`
- `net_salary`
- Set `recalc_needed = FALSE`

```sql
UPDATE hr_schema.paysheet_detail
SET
	ccss_employee_deduction = 150.00,
	ccss_tenant_deduction   = 300.00,
	income_tax_amount       = 0.00,
	total_deduction         = 450.00,
	net_salary              = gross_salary - 450.00,
	recalc_needed           = FALSE
WHERE detail_id = <detail_id>;
```

### 5) Close paysheet (state transition)

```sql
-- Will raise an exception if any detail has recalc_needed = TRUE
SELECT hr_schema.update_paysheet_state(<paysheet_id>);

-- Verify closure
SELECT p.paysheet_id, ps.status_description
FROM hr_schema.paysheet p
JOIN hr_schema.paysheet_status ps ON ps.status_id = p.paysheet_status_id
WHERE p.paysheet_id = <paysheet_id>;
```

### 6) Monthly CCSS report

```sql
SELECT *
FROM hr_schema.generate_monthly_ccss(2025, 12);
-- Returns columns: total_employee, total_tenant, total
```

## Validations, Triggers & Constraints

- Trigger `update_gross_salary` (AFTER I/U/D on `income_register`):
  - Recomputes `paysheet_detail.gross_salary` as the sum of incomes.
  - Marks `paysheet_detail.recalc_needed = TRUE` for downstream recalculation.
- Trigger `protect_net_salary` (BEFORE I/U on `paysheet_detail`):
  - Blocks modifications to `net_salary` when the parent paysheet status is `Completed`.
- Check constraint on `paysheet_detail.gross_salary >= 0` prevents negative gross salary.
- Function `hr_schema.update_paysheet_state(p_paysheet_id)`:
  - Fails if any `paysheet_detail.recalc_needed = TRUE`.
  - Sets `paysheet.paysheet_status_id` to `Completed` otherwise.
- Function `hr_schema.generate_monthly_ccss(year, month)` aggregates CCSS totals from completed paysheets.

## Idempotency & Safety

- Recalculation: any change in `income_register` sets `recalc_needed = TRUE`. Ensuring the engine re-derives deductions and updates details before closing.
- Completion lock: once completed, `net_salary` is protected by trigger; prefer corrective reversals rather than editing completed periods.
- FOREIGN KEYs: ensure referenced `branch_id`, `employee_id`, and `payment_method_id` exist before inserts.

## Common Troubleshooting

- Cannot complete paysheet: some `paysheet_detail.recalc_needed = TRUE` → recompute and update details, setting it to `FALSE`.
- Gross salary not updating: verify the trigger `update_gross_salary` exists and that `income_register` rows target the correct `detail_id`.
- Net salary change blocked: expected when paysheet is `Completed` (trigger `protect_net_salary`).
- Monthly report totals missing: ensure paysheets in the target month are `Completed` and `payment_day` falls within the year-month requested.

## Quick Debugging Queries

- Paysheet status and dates

```sql
SELECT p.paysheet_id, p.period_start_date, p.period_end_date, p.payment_day,
			 ps.status_description
FROM hr_schema.paysheet p
JOIN hr_schema.paysheet_status ps ON ps.status_id = p.paysheet_status_id
WHERE p.paysheet_id = <paysheet_id>;
```

- Details requiring recalculation

```sql
SELECT detail_id, employee_id, gross_salary, net_salary, recalc_needed
FROM hr_schema.paysheet_detail
WHERE paysheet_id = <paysheet_id> AND recalc_needed = TRUE;
```

- Income breakdown for a detail

```sql
SELECT ir.*, ic.concept_name
FROM hr_schema.income_register ir
JOIN hr_schema.income_concept ic ON ic.income_id = ir.concept_id
WHERE ir.detail_id = <detail_id>;
```

## Notes for Integrators / Developers

- Calculation engine: the DB enforces boundaries and aggregation; perform business calculations (deductions/taxes) in your service and persist results before closing.
- Status lifecycle: extend `paysheet_status` as needed; `update_paysheet_state` currently transitions to `Completed` when safe.
- Performance: indexes exist for common filters (period dates, employee/pay date, etc.). Consider additional indexes if reporting grows.
