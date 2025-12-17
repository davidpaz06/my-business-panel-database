# Employee & Contract Insert — End-to-End Flow

This document describes how to create an employee together with its contract in the HR (RRHH) module. It covers the database entities involved, the server-side function used for the operation, validations and constraints, and example SQL snippets. The flow is based on `rrhh_module.create_new_employee` and constraints defined in the schema and triggers.

Scope: insert a new contract and its linked employee in one atomic operation, ensuring referential integrity and business rules (date validation, schedule existence, uniqueness of identifiers).

## Prerequisites

- Core user: a `core.users.user_id` for the employee must already exist (FK on `employee.user_id`).
- Payment schedule: a valid schedule in `rrhh_module.payment_schedule` (e.g., Monthly, Fortnight, Weekly, Daily). Use an existing `payment_schedule_id`.
- RRHH tables & functions deployed: `rrhh_module.contract`, `rrhh_module.employee`, `rrhh_module.payment_schedule`, trigger `rrhh_module.validate_contract_dates`, and function `rrhh_module.create_new_employee`.

## High-level Flow

1. Validate the target payment schedule exists (performed by the function).
2. Create a new `contract` (UUID) with start and end dates, hours, base salary, and duties.
3. Create a new `employee` (UUID) that references the newly created `contract`, a valid `payment_schedule`, and an existing `core.users.user_id`.
4. Return the new `employee_id` to the caller.

## Detailed Steps & SQL snippets

### 1) Create Employee + Contract in one call

Use the server-side function `rrhh_module.create_new_employee` which encapsulates validations and inserts.

Parameters

- Contract: `p_start_date`, `p_end_date`, `p_hours`, `p_base_salary`, `p_duties`
- Employee: `p_user_id`, `p_first_name`, `p_last_name`, `p_doc_number`, `p_phone`, `p_email`, `p_schedule_id`

Example

```sql
-- Ensure you have a user and a valid schedule_id
WITH any_user AS (
	SELECT user_id FROM core.users LIMIT 1
)
SELECT rrhh_module.create_new_employee(
	p_start_date => DATE '2025-10-01',
	p_end_date   => DATE '2026-10-01',
	p_hours      => 45,
	p_base_salary=> 2500.50,
	p_duties     => 'Software Engineer Duties',

	p_user_id    => (SELECT user_id FROM any_user),
	p_first_name => 'Juan',
	p_last_name  => 'Perez',
	p_doc_number => '701230456',
	p_phone      => '88887777',
	p_email      => 'juan.perez@test.com',
	p_schedule_id=> 1
) AS employee_id;
```

On success, returns the `employee_id` (UUID). Internally the function:

- Verifies the `payment_schedule` exists.
- Inserts into `rrhh_module.contract` and obtains `contract_id`.
- Inserts into `rrhh_module.employee` referencing the `contract_id` and the provided `schedule_id` and `user_id`.

### 2) Validations & Constraints enforced

- Contract date logic: trigger `rrhh_module.validate_contract_dates` on `rrhh_module.contract` prevents `end_date < start_date`.
- Foreign keys: `employee.user_id` → `core.users(user_id)`; `employee.schedule_id` → `rrhh_module.payment_schedule(payment_schedule_id)`; `employee.contract_id` → `rrhh_module.contract(contract_id)`.
- Uniqueness: `employee.doc_number` and `employee.email` are unique. Duplicate values raise a unique violation.
- Cascading: `employee.contract_id` references `contract` with `ON DELETE CASCADE` (deleting a contract deletes the employee record referencing it). Use with care in administrative operations.
- Indexing: indexes exist for filtering and joins (e.g., `idx_contract_base_salary`, `idx_employee_user_id`, `idx_employee_is_active`).

### 3) Error handling surfaced by the function

`rrhh_module.create_new_employee` converts database errors into descriptive exceptions:

- Schedule does not exist: `Integrity error: schedule_id (schedule_id: <id>) doesnt exists`.
- Duplicate `doc_number` or `email`: `Data Error: Document Number (<doc_number>) or Email already exists.`
- Missing FK (e.g., `user_id` or `schedule_id`): `Integrity Error: Insert failed, cause of the error a non existent foreign key (user_id or schedule_id).`
- Other failures: `Error creating employee or contract: <detail>`.

## Quick Debugging Queries

- Verify employee by document number or email

```sql
SELECT e.*
FROM rrhh_module.employee e
WHERE e.doc_number = '701230456' OR e.email = 'juan.perez@test.com';
```

- Inspect the linked contract

```sql
SELECT c.*
FROM rrhh_module.contract c
JOIN rrhh_module.employee e ON e.contract_id = c.contract_id
WHERE e.doc_number = '701230456';
```

- Check schedule existence

```sql
SELECT * FROM rrhh_module.payment_schedule WHERE payment_schedule_id = 1;
```

- Validate contract date rule (trigger prevents invalid updates)

```sql
-- This should raise an exception due to end_date < start_date
UPDATE rrhh_module.contract
SET end_date = DATE '2025-01-01'
WHERE contract_id = '<contract_id>'
	AND start_date > DATE '2025-01-01';
```

## Idempotency & Safety Notes

- Pre-checks: to avoid unique violations, check for existing `doc_number` or `email` before calling the function, or catch the raised exception in the application layer.
- Referential integrity: ensure the `core.users.user_id` exists and the `payment_schedule_id` is valid prior to the insert.
- Date integrity: ensure `p_end_date >= p_start_date`; otherwise the contract trigger blocks the transaction.
- Deletion implications: be cautious with `ON DELETE CASCADE` on `employee.contract_id` → deleting a contract deletes the employee.

## Common Troubleshooting

- Error: schedule_id doesn’t exist → Confirm the `payment_schedule_id` in `rrhh_module.payment_schedule`.
- Unique violation (document/email) → Search for existing employee by `doc_number`/`email` and adjust input.
- FK violation (user or schedule) → Create or correct the referenced `core.users` row or schedule.
- Contract date error → Ensure `p_end_date` is on or after `p_start_date`.

## Reference Tests

- Contract and employee creation, and contract date trigger: see test script [test/rrhh_module/testContracts.sql](test/rrhh_module/testContracts.sql).

## Notes for Integrators / Developers

- Function call form: use named parameters for clarity and to avoid ordering mistakes.
- Identity fields: normalize `doc_number` and `email` on the client-side if you enforce formatting elsewhere.
- Auditing: `employee.created_at`/`updated_at` default automatically; update timestamps should be maintained on updates.
- Performance: provided indexes help typical lookups and joins; add additional ones if workload demands specialized filters.
