# Client Pay (In Full) — End-to-End Flow

This document explains the full customer payment flow in a POS (point-of-sale) environment: how a sale is created, how payments are recorded and verified, how the system issues a bill/invoice automatically, and how loyalty points are awarded. The explanations reference the database tables and server-side functions/triggers used in the project.

**Scope**: retail checkout where a customer pays in full at point of sale (single or hybrid payments). The same flow applies when a sale triggers invoice generation and loyalty point accrual.

## Prerequisites

- **Tenant, Branch, Products, and Customer**: these must exist in `core.tenant`, `core.branch`, `core.product`, and `core.tenant_customer`.
- **POS tables & functions**: `pos_module.sale`, `pos_module.sale_item`, `pos_module.customer_payment`, `pos_module.bill`, `pos_module.tenant_customer_score`, and functions such as `pos_module.verify_customer_payment`, `pos_module.create_bill`, and `pos_module.link_sale_to_session` must be present and deployed.

## High-level Flow

1. Customer selects products → cashier creates a `sale` and `sale_item` rows.
2. Cashier registers payments (single or multiple `customer_payment` rows) — payments can be cash, card, or hybrid.
3. Each `customer_payment` is verified via `pos_module.verify_customer_payment(payment_id)` (or automatically by a verification process). Verified payments update the sale's paid amount.
4. When paid amount >= sale total, `sale.is_completed` becomes true. Triggers run to:
   - create a `bill`/invoice (`pos_module.create_bill`)
   - link the sale to the active `cash_register_session` (`pos_module.link_sale_to_session`)
   - award loyalty points (via `pos_module.tenant_customer_score` and `pos_module.score_transaction`)

## Detailed Steps & SQL snippets

### 1. Create Sale and Items (cashier)

```sql
-- create sale (subtotal/tax/total computed as needed)
INSERT INTO pos_module.sale (branch_id, user_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
VALUES (<branch_id>, <user_id>, <currency_id>, 100.00, 0.00, 100.00, false)
RETURNING sale_id;

-- add items
INSERT INTO pos_module.sale_item (sale_id, tenant_id, product_id, quantity, unit_price, total_price)
VALUES (<sale_id>, <tenant_id>, <product_id>, 1, 100.00, 100.00);
```

Notes:

- `subtotal_amount`, `tax_amount`, and `total_amount` may be calculated client-side or via triggers (see `pos_module.calculate_total_price`/`calculate_bill_total`).

### 2. Register Payment(s)

```sql
INSERT INTO pos_module.customer_payment (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
VALUES (<tenant_customer_id>, <sale_id>, <payment_method_id>, 100.00, <currency_id>, false)
RETURNING customer_payment_id;

-- Verify the payment (this calls server logic which updates payment verified flag and recalculates sale status)
CALL pos_module.verify_customer_payment(<customer_payment_id>);
```

Notes:

- Hybrid payments are multiple `customer_payment` rows for same `sale_id` (e.g., cash + card). Verify each one.

### 3. Payment Verification → Sale Completion

- The `verify_customer_payment` procedure performs these actions:
  - marks the `customer_payment.verified = true`;
  - recalculates total verified payments for the sale;
  - if verified total >= `sale.total_amount`, it sets `sale.is_completed = true`.

### 4. Bill / Invoice Creation (trigger)

- The system creates a `bill` when `sale.is_completed` transitions to true. The `create_bill` trigger/function:
  - collects sale and payment data;
  - inserts a `pos_module.bill` record and `pos_module.bill_payment` rows referencing the `customer_payment` entries used for the sale;
  - totals and taxes are copied into the bill for accounting.

Example: bill creation is triggered automatically — if you need to create it manually, use the `pos_module.get_bill(<sale_id>)` function or mimic the trigger behavior.

### 5. Linking to Cash Register Session

- When `sale.is_completed` is set, the `link_sale_to_session` trigger associates the sale with the currently open `cash_register_session` (so reporting and reconciliation reflect the session and cashier).

### 6. Loyalty Points (earn & redeem)

- Loyalty configuration lives in `pos_module.loyalty_program` (fields include `points_per_dollar` and `points_per_currency_unit`).
- Customer points are stored in `pos_module.tenant_customer_score` and transaction history in `pos_module.score_transaction`.

Earning points:

- On verified payment and sale completion, the system calculates points using `points_per_dollar` (or equivalent) and inserts a `score_transaction` and updates `tenant_customer_score.score` and `lifetime_score`.

Redeeming points:

- Points redemption is modeled as a special `customer_payment` record with `is_points_redemption = true` and `points_redeemed` fields. Verification rejects redemption that exceeds available points.

Example (redeem partial points + cash):

```sql
-- redeem points
INSERT INTO pos_module.customer_payment(..., is_points_redemption, points_redeemed, payment_amount, verified)
VALUES (..., true, 500, 5.00, false) RETURNING customer_payment_id;
CALL pos_module.verify_customer_payment(<customer_payment_id>);

-- remaining amount paid as normal customer_payment record
```

## Idempotency & Safety

- Tests and scripts should be idempotent: check for existing `sale`, `product`, or `tenant_customer` records before inserting, or use `ON CONFLICT` where unique constraints exist.
- Triggers are implemented to avoid infinite loops (example: `WHEN` clauses and avoiding updating the same row inside a trigger).

## Common Troubleshooting

- If no bill is created after payment, confirm `pos_module.verify_customer_payment` updated `sale.is_completed` and that the `create_bill` trigger exists on `pos_module.sale`.
- If points are not awarded, check `pos_module.loyalty_program` and `pos_module.tenant_customer_score` existence and that `verify_customer_payment` calls the points logic.

## Quick Debugging Queries

- Check sale and completion status:

```sql
SELECT sale_id, total_amount, is_completed FROM pos_module.sale WHERE sale_id = '<sale_id>';
```

- List payments for a sale:

```sql
SELECT * FROM pos_module.customer_payment WHERE sale_id = '<sale_id>' ORDER BY payment_date;
```

- Verify bill created:

```sql
SELECT * FROM pos_module.bill WHERE sale_id = '<sale_id>';
```

- Check customer points:

```sql
SELECT * FROM pos_module.tenant_customer_score WHERE tenant_customer_id = '<tenant_customer_id>' AND tenant_id = '<tenant_id>';
```

## Notes for Integrators / Developers

- Keep client code to compute prices consistent with server-side triggers. Server-side functions (`calculate_total_price`, `calculate_bill_total`) will enforce totals if used.
- When modifying payment flows (e.g., new payment methods), ensure that `verify_customer_payment` still recognizes and correctly aggregates verified payments.
- Tests shipped under `test/pos_module/` in the repository demonstrate idempotent scenarios and can be used as references.

If you want, I can also add a step-by-step runnable test script (idempotent) that exercises the entire flow in your local DB environment and prints the key verification points.
