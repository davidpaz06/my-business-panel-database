# Hybrid payments

This document describes the end-to-end flow that allows a customer to pay a single sale using multiple payment methods (hybrid payment). The goal is to demonstrate that a customer can split payment across different methods (e.g., cash + card, points + cash) and that the system correctly reconciles sale, bill, payments and loyalty behavior.

**Scope:** retail checkout where partial payments are recorded as multiple customer_payment rows for the same sale and verified independently. The same flow applies when sales generate invoices and loyalty point adjustments.

## Prerequisites

- Tenant, Branch, Products, and Customer exist in `general_schema.tenant`, `general_schema.branch`, `general_schema.product`, and `general_schema.tenant_customer`.
- pos_schema objects and functions deployed:
  - Tables: `pos_schema.sale`, `pos_schema.sale_item`, `pos_schema.customer_payment`, `pos_schema.bill`, `pos_schema.bill_payment`, `pos_schema.tenant_customer_score`, `pos_schema.return_product`.
  - Functions/procedures/triggers: `pos_schema.verify_customer_payment`, `pos_schema.check_sale_payment_completion`, `pos_schema.create_bill`, `pos_schema.link_sale_to_session`, and loyalty-related functions.

## High-level Flow

1. Cashier creates a `sale` and associated `sale_item` rows for the cart.
2. Cashier registers one or more `customer_payment` rows for the same `sale_id` (e.g., cash + card, or points + cash).
3. Each `customer_payment` is verified with `pos_schema.verify_customer_payment(payment_id)`.
4. After verification, the system aggregates verified payments. When verified payments >= sale.total_amount, `sale.is_completed` is set true.
5. On completion triggers run to:
   - create a `bill` (`pos_schema.create_bill`)
   - link sale to the active `cash_register_session` (`link_sale_to_session`)
   - award loyalty points only on the cash/card portion (not on points redemptions)
6. All records (sale, bill, payments, loyalty) remain consistent and auditable.

## Detailed Steps & SQL snippets

### 1. Create Sale and Items (cashier)

Client builds cart → server creates sale + items:

```sql
INSERT INTO pos_schema.sale (branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
VALUES (<branch_id>, 1, 100.00, 13.00, 113.00, false)
RETURNING sale_id;

INSERT INTO pos_schema.sale_item (sale_id, tenant_id, product_id, quantity, unit_price, total_price)
VALUES (<sale_id>, <tenant_id>, <product_id>, 2, 50.00, 100.00);
```

### 2. Register Hybrid Payments (multiple rows)

Record each partial payment as a separate `customer_payment` row for the same `sale_id`.

Examples:

- Cash + Card

```sql
-- Cash partial
INSERT INTO pos_schema.customer_payment (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
VALUES (<customer_id>, <sale_id>, 1, 50.00, 1, false)
RETURNING customer_payment_id;

-- Card remaining
INSERT INTO pos_schema.customer_payment (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
VALUES (<customer_id>, <sale_id>, 3, 63.00, 1, false)
RETURNING customer_payment_id;
```

- Points + Cash

```sql
-- Points redemption (special payment with is_points_redemption)
INSERT INTO pos_schema.customer_payment (tenant_customer_id, sale_id, payment_method_id, is_points_redemption, points_redeemed, points_to_currency_rate, payment_amount, currency_id, verified)
VALUES (<customer_id>, <sale_id>, 4, true, 500, 100.00, 5.00, 1, false)
RETURNING customer_payment_id;

-- Cash for remainder
INSERT INTO pos_schema.customer_payment (..., payment_amount = 108.00, verified = false) RETURNING customer_payment_id;
```

### 3. Verify Each Payment

Call verification per payment. The procedure will:

- Process point redemptions via `pos_schema.redeem_points` (and fail if insufficient).
- Mark `customer_payment.verified = true`.
- Recalculate sum of verified payments and set `sale.is_completed = true` when fully paid.

```sql
CALL pos_schema.verify_customer_payment(<customer_payment_id>);
```

Logs will show partial totals and a final "Sale is COMPLETED" once cumulative verified payments meet the sale total.

### 4. Bill Creation and Linking

When `sale.is_completed` toggles to true a trigger executes `pos_schema.create_bill`:

- Creates `pos_schema.bill` copying sale totals.
- Inserts `pos_schema.bill_payment` rows linking verified `customer_payment` rows.
- Links sale to active `cash_register_session` via `link_sale_to_session`.

Verify bill:

```sql
SELECT * FROM pos_schema.bill WHERE sale_id = <sale_id>;
SELECT * FROM pos_schema.bill_payment WHERE bill_id = <bill_id>;
```

### 5. Loyalty Points Behavior

- Points are awarded only on the monetary portion (cash/card) recorded into `bill_payment` (the procedure `award_points` sums non-points payments).
- Points redemptions are processed at verification time and reduce customer balance (`tenant_customer_score`) and insert `score_transaction` rows.

Important: hybrid flow ensures the part paid with points does not generate new points.

## Idempotency & Safety

- Tests and scripts must be idempotent: check for existing tenant/branch/customer/product records before inserting.
- Recording multiple `customer_payment` rows is atomic per row; each must be verified individually.
- Triggers avoid infinite loops by updating different tables and using `WHEN` clauses.
- Use transactions in client code when you need atomic multi-step operations (create sale, create payments, verify payments).

## Common Troubleshooting

- No bill created: verify that all required payments were marked `verified = true` and `pos_schema.check_sale_payment_completion` returned true leading to `sale.is_completed = true`.
- Points not redeemed: verify `pos_schema.redeem_points` success and that `customer_payment.is_points_redemption` + `points_redeemed` were correct.
- Overpayment/underpayment: logs in `verify_customer_payment` show sale total, payments total and difference.
- Missing cash_register session link: ensure a session is open (`pos_schema.cash_register_session.is_active = true`) for the branch at billing time.

## Quick Debugging Queries

- Check sale status and totals:

```sql
SELECT sale_id, subtotal_amount, tax_amount, total_amount, is_completed FROM pos_schema.sale WHERE sale_id = '<sale_id>';
```

- List payments for a sale:

```sql
SELECT customer_payment_id, payment_method_id, is_points_redemption, points_redeemed, payment_amount, verified
FROM pos_schema.customer_payment
WHERE sale_id = '<sale_id>' ORDER BY payment_date;
```

- List bill and linked payments:

```sql
SELECT * FROM pos_schema.bill WHERE sale_id = '<sale_id>';
SELECT * FROM pos_schema.bill_payment WHERE bill_id = (SELECT bill_id FROM pos_schema.bill WHERE sale_id = '<sale_id>' LIMIT 1);
```

- Check customer points:

```sql
SELECT score, lifetime_score, score_redeemed FROM pos_schema.tenant_customer_score WHERE tenant_customer_id = '<customer_id>' AND tenant_id = '<tenant_id>';
```

## Notes for Integrators / Developers

- Hybrid payments are modeled as multiple `customer_payment` rows. The verification procedure aggregates verified payments — do not attempt to collapse hybrid payments into a single row.
- For point redemptions, ensure UI shows both points and cash components and that amounts match server-side conversion (`points_redeemed_per_currency_unit`).
- Maintain consistent tax calculation between frontend and backend. The backend recomputes totals on sale/bill updates.
- For reporting, use `bill_payment` to determine which portion of a bill was cash/card vs points.

For a runnable example or idempotent test script demonstrating cash+card and points+cash hybrid payments, provide target environment details and the script will be prepared.
