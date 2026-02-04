# Client pay in POS

This document explains the full customer payment flow in a POS (point-of-sale) environment: how a sale is created, how payments are recorded and verified, how the system issues a bill automatically, and how loyalty points are awarded. The explanations reference the database tables and server-side functions/triggers used in the system.

**Scope**: retail checkout where a customer pays in full at point of sale (single or hybrid payments). The same flow applies when a sale triggers bill generation and loyalty point accrual.

**Terminology Note**: Throughout this document, the term _bill_ refers to customer invoices generated from tenant sales transactions. The term _invoice_ is reserved for purchase orders and supplier billing and is not covered in this guide.

## Prerequisites

- **Tenant, Branch, Products, and Customer**: these must exist in `general_schema.tenant`, `general_schema.branch`, `general_schema.product_variant`, and `general_schema.tenant_customer`.
- **POS tables & functions**: `pos.sale`, `pos.sale_item`, `pos.customer_payment`, `pos.bill`, `pos.cash_register`, `pos.cash_register_session`, `pos.tenant_customer_score`, and functions such as `pos.verify_customer_payment`, `pos.create_bill`, `pos.link_sale_to_session`, and `pos.open_close_cash_register_session` must be present and deployed.
- **Loyalty Program**: A `pos.loyalty_program` record must exist for the tenant with configured earning and redemption rates.

---

## Cash Register Session Management

### Opening a Cash Register Session

A cash register session marks the beginning of a cashier's workday. This session is used to track all sales for reconciliation and accountability.

**Flow:**

1. Cashier calls `pos.open_close_cash_register_session()` with:
   - `_cash_register_id`: The register being opened.
   - `_action = 'open'`: Specifies the opening action.
   - `_amount`: The opening float (initial cash, e.g., $500).
   - `_user_id`: The cashier's user ID.

2. The procedure inserts a new `cash_register_session` record:
   - `opened_at`: Current timestamp.
   - `opening_amount`: The float amount ($500).
   - `is_active`: Set to `true`.
   - `user_id`: Links to the cashier.

**Example:**

```sql
CALL pos.open_close_cash_register_session(
    '<cash_register_id>',
    'open',
    500.00,
    '<user_id>'
);
```

### Linking Sales to a Cash Register Session

As the cashier processes sales, each completed sale is automatically linked to the active `cash_register_session` via the `pos.link_sale_to_session()` trigger.

- When `sale.is_completed = true`, the trigger inserts a `pos.cash_register_sale` record.
- This record ties the sale to the session and ensures all revenue is accounted for during reconciliation.

### Closing a Cash Register Session

At the end of the workday, the cashier closes the session and provides the closing amount (actual cash counted).

**Flow:**

1. Cashier calls `pos.open_close_cash_register_session()` with:
   - `_cash_register_id`: The register being closed.
   - `_action = 'close'`: Specifies the closing action.
   - `_amount`: The closing amount (actual cash counted, e.g., $1,495).
   - `_user_id`: Can be `null` for closing (not required).

2. The procedure:
   - Updates the session's `closed_at` timestamp.
   - Sets `closing_amount` to the counted amount.
   - Sets `is_active = false`.
   - Calculates the difference: `closing_amount - opening_amount = 1495 - 500 = 995` (matches sales).

**Example:**

```sql
CALL pos.open_close_cash_register_session(
    '<cash_register_id>',
    'close',
    1495.00,
    null
);
```

**Reconciliation Query:**

```sql
SELECT
    crs.cash_register_session_id,
    crs.opening_amount,
    crs.closing_amount,
    (crs.closing_amount - crs.opening_amount) as difference,
    COUNT(crs_sale.sale_id) as total_sales,
    COALESCE(SUM(s.total_amount), 0) as sales_total
FROM pos_schema.cash_register_session crs
LEFT JOIN pos_schema.cash_register_sale crs_sale ON crs.cash_register_session_id = crs_sale.cash_register_session_id
LEFT JOIN pos_schema.sale s ON crs_sale.sale_id = s.sale_id
WHERE crs.is_active = false
GROUP BY crs.cash_register_session_id
ORDER BY crs.closed_at DESC;
```

---

## High-level Flow

1. Customer selects products → cashier creates a `sale` and `sale_item` rows.
2. Cashier registers payments (single or multiple `customer_payment` rows) — payments can be cash, card, or hybrid.
3. Each `customer_payment` is verified via `pos_schema.verify_customer_payment(payment_id)` (or automatically by a verification process). Verified payments update the sale's paid amount.
4. When paid amount >= sale total, `sale.is_completed` becomes true. Triggers run to:
   - create a `bill`/invoice (`pos_schema.create_bill`)
   - link the sale to the active `cash_register_session` (`pos_schema.link_sale_to_session`)
   - award loyalty points (via `pos_schema.tenant_customer_score` and `pos_schema.score_transaction`)

## Detailed Steps & SQL snippets

### Pre-Sale: Open Cash Register Session

Before processing sales, the cashier opens a cash register session with an opening float.

```sql
-- Open cash register with $500 float
CALL pos_schema.open_close_cash_register_session(
    '<cash_register_id>',
    'open',
    500.00,
    '<user_id>'  -- Cashier user ID
);

-- Query to verify session is open
SELECT * FROM pos_schema.cash_register_session
WHERE cash_register_id = '<cash_register_id>'
AND is_active = true;
```

### 1. Create Sale and Items (cashier)

The cashier initiates a sale for the customer, selects products (variants), and calculates totals.

```sql
-- Create sale with subtotal, tax, and total
INSERT INTO pos_schema.sale (
    branch_id,
    currency_id,
    subtotal_amount,
    tax_amount,
    total_amount,
    is_completed
)
VALUES (
    '<branch_id>',
    1,  -- Currency (USD)
    995.00,  -- Subtotal (3 items)
    129.35,  -- Tax (13%)
    1124.35, -- Total
    false
)
RETURNING sale_id;

-- Add sale items (product variants)
INSERT INTO pos_schema.sale_item (
    sale_id,
    tenant_id,
    product_variant_id,
    quantity,
    unit_price,
    total_price
)
VALUES
    ('<sale_id>', '<tenant_id>', '<variant_1_id>', 1, 850.00, 850.00),
    ('<sale_id>', '<tenant_id>', '<variant_2_id>', 1, 25.00, 25.00),
    ('<sale_id>', '<tenant_id>', '<variant_3_id>', 1, 120.00, 120.00);
```

**Notes:**

- `subtotal_amount`: Sum of all item prices before tax.
- `tax_amount`: Calculated based on tenant's region and applicable tax rate.
- `total_amount`: Subtotal + tax (this is the customer's total due).
- `is_completed = false`: Sale is pending payment.
- Each item references a `product_variant_id` (the sellable SKU), not a base product.

### 2. Register Payment(s)

The cashier registers one or more payments. A single payment can settle the full amount, or multiple payments (hybrid payments) can be combined (e.g., $500 cash + $624.35 card).

```sql
-- Register a single payment (full amount)
INSERT INTO pos_schema.customer_payment (
    tenant_customer_id,
    sale_id,
    payment_method_id,
    payment_amount,
    currency_id,
    verified
)
VALUES (
    '<tenant_customer_id>',
    '<sale_id>',
    3,  -- Payment method (e.g., credit_card)
    1124.35,  -- Full amount due
    1,  -- USD
    false  -- Not verified yet
)
RETURNING customer_payment_id;

-- For hybrid payments (example: cash + card):
-- Insert first payment (cash)
INSERT INTO pos_schema.customer_payment (...)
VALUES ('<tenant_customer_id>', '<sale_id>', 1, 500.00, 1, false)
RETURNING customer_payment_id;

-- Insert second payment (card)
INSERT INTO pos_schema.customer_payment (...)
VALUES ('<tenant_customer_id>', '<sale_id>', 3, 624.35, 1, false)
RETURNING customer_payment_id;
```

**Notes:**

- Each `customer_payment` is initially `verified = false`.
- Multiple payments for the same sale must sum to or exceed the sale total.
- Payment methods include: 1=cash, 2=check, 3=credit_card, 4=debit_card, 5=points_redemption, etc.

### 3. Payment Verification → Sale Completion

Each payment is verified via a procedure call. The system aggregates verified payments and, if they cover the sale total, marks the sale as completed.

```sql
-- Verify the payment (this triggers server-side logic)
CALL pos_schema.verify_customer_payment('<customer_payment_id>');
```

**What happens during verification:**

1. The procedure marks `customer_payment.verified = true`.
2. It recalculates the total verified payments for the sale:

   ```sql
   SELECT COALESCE(SUM(payment_amount), 0)
   FROM pos_schema.customer_payment
   WHERE sale_id = '<sale_id>' AND verified = true;
   ```

3. If verified total ≥ `sale.total_amount`, it sets `sale.is_completed = true` and triggers the cascade of functions.

**For hybrid payments (example):**

```sql
-- Verify first payment (cash $500)
CALL pos_schema.verify_customer_payment('<payment_1_id>');
-- Verified total: $500 < $1,124.35 → Sale remains incomplete

-- Verify second payment (card $624.35)
CALL pos_schema.verify_customer_payment('<payment_2_id>');
-- Verified total: $1,124.35 = $1,124.35 → Sale now is_completed = true
-- Triggers fire automatically:
--   1. create_bill() → inserts bill record
--   2. link_sale_to_session() → links to cash_register_session
--   3. award_points() → grants loyalty points
```

**Query to check sale status:**

```sql
SELECT
    s.sale_id,
    s.total_amount,
    s.is_completed,
    COALESCE(SUM(cp.payment_amount), 0) as verified_total
FROM pos_schema.sale s
LEFT JOIN pos_schema.customer_payment cp ON s.sale_id = cp.sale_id AND cp.verified = true
WHERE s.sale_id = '<sale_id>'
GROUP BY s.sale_id;
```

### 4. Bill / Invoice Creation (trigger)

When `sale.is_completed` transitions to `true`, the `pos_schema.create_bill()` trigger automatically generates an invoice.

**What the trigger does:**

1. Creates a `pos_schema.bill` record:
   - `sale_id`: References the completed sale.
   - `tenant_customer_id`: Links to the customer.
   - `subtotal_amount`, `tax_amount`, `total_amount`: Copied from the sale.
   - `billed_at`: Current timestamp.
   - `currency_id`: From the sale.

2. Creates `pos_schema.bill_payment` records:
   - For each verified `customer_payment`, inserts a `bill_payment` row linking the bill and payment.
   - This maintains an audit trail of which payments settled which invoices.

**Example (automatic trigger result):**

```sql
-- After sale.is_completed = true, the bill is created automatically
SELECT * FROM pos_schema.bill WHERE sale_id = '<sale_id>';
-- Result:
--   bill_id: <uuid>
--   sale_id: <sale_id>
--   tenant_customer_id: <customer_id>
--   subtotal_amount: 995.00
--   tax_amount: 129.35
--   total_amount: 1124.35
--   billed_at: 2026-02-04 17:06:18

-- Check linked payments
SELECT bp.*, cp.payment_method_id, cp.payment_amount
FROM pos_schema.bill_payment bp
JOIN pos_schema.customer_payment cp ON bp.customer_payment_id = cp.customer_payment_id
WHERE bp.bill_id = '<bill_id>';
```

**For manual bill creation (if needed):**

```sql
-- Use the utility function to fetch and review bill data
SELECT * FROM pos_schema.get_bill('<sale_id>');
```

### 5. Linking to Cash Register Session

- When `sale.is_completed` is set, the `link_sale_to_session` trigger associates the sale with the currently open `cash_register_session` (so reporting and reconciliation reflect the session and cashier).

### 6. Loyalty Points (earn & redeem)

#### Earning Points

Loyalty points are automatically awarded when a sale is completed with verified payment. The system uses the loyalty program configuration to calculate points.

**Loyalty Program Configuration:**

```sql
-- View loyalty program for a tenant
SELECT
    loyalty_program_id,
    tenant_id,
    points_earned_per_currency_unit,
    points_redeemed_per_currency_unit,
    minimum_purchase_for_points,
    is_active
FROM pos_schema.loyalty_program
WHERE tenant_id = '<tenant_id>';

-- Example: 10 points earned per $1 spent, 100 points redeem for $1
```

**Point Earning Calculation:**

When `sale.is_completed = true`, the system:

1. Fetches the tenant's loyalty program configuration.
2. Calculates earned points:

   ```sql
   earned_points = sale.total_amount × points_earned_per_currency_unit
   Example: 1124.35 × 10 = 11,243.5 points (rounded to 11,243)
   ```

3. Inserts a `pos_schema.score_transaction` record (audit trail).
4. Updates `pos_schema.tenant_customer_score`:
   - `score`: Available points (current + earned).
   - `lifetime_score`: Total points ever earned.

**Example Query (automatic via award_points trigger):**

```sql
-- After sale completion, points are awarded
SELECT
    tcs.tenant_customer_id,
    tcs.score as available_points,
    tcs.lifetime_score as total_earned,
    tcs.score_redeemed as total_redeemed,
    tcs.last_earned_at
FROM pos_schema.tenant_customer_score tcs
WHERE tcs.tenant_customer_id = '<tenant_customer_id>'
AND tcs.tenant_id = '<tenant_id>';

-- Audit trail
SELECT
    st.score_transaction_id,
    st.score_change,
    st.transaction_type_id,
    st.created_at
FROM pos_schema.score_transaction st
WHERE st.tenant_customer_id = '<tenant_customer_id>'
ORDER BY st.created_at DESC;
```

#### Redeeming Points

Points can be redeemed as a payment method. A points redemption is recorded as a special `customer_payment` with `is_points_redemption = true`.

**Redemption Flow:**

1. Customer has 500 available points, sale total is $10.
2. Customer decides to redeem points for part of the purchase:

   ```sql
   points_to_redeem = 100 (redeems for $1 per loyalty program)
   remaining_due = $10 - $1 = $9 (to be paid in cash/card)
   ```

3. Register two payments:

   ```sql
   -- Payment 1: Points redemption
   INSERT INTO pos_schema.customer_payment (
       tenant_customer_id,
       sale_id,
       payment_method_id,  -- Special method for points
       payment_amount,     -- $1 (monetary value)
       is_points_redemption,
       points_redeemed,
       verified
   )
   VALUES (
       '<tenant_customer_id>',
       '<sale_id>',
       5,  -- Special payment method for points
       1.00,  -- Monetary equivalent of 100 points
       true,
       100,  -- Points being redeemed
       false
   )
   RETURNING customer_payment_id;

   -- Payment 2: Cash or card for remaining
   INSERT INTO pos_schema.customer_payment (
       tenant_customer_id,
       sale_id,
       payment_method_id,
       payment_amount,
       verified
   )
   VALUES (
       '<tenant_customer_id>',
       '<sale_id>',
       1,  -- Cash
       9.00,  -- Remaining amount
       false
   )
   RETURNING customer_payment_id;
   ```

4. Verify both payments:

   ```sql
   CALL pos_schema.verify_customer_payment('<points_payment_id>');
   CALL pos_schema.verify_customer_payment('<cash_payment_id>');
   ```

5. System validates:
   - Customer has enough available points: `500 >= 100` ✓
   - Total payments cover sale: `$1 + $9 = $10` ✓
   - If valid, deducts points from `tenant_customer_score.score` and updates `score_redeemed`.

**Query to check available points:**

```sql
SELECT
    score as available_for_redemption,
    lifetime_score,
    score_redeemed
FROM pos_schema.tenant_customer_score
WHERE tenant_customer_id = '<tenant_customer_id>' AND tenant_id = '<tenant_id>';
```

---

### 7. Close Cash Register Session

At the end of the day, the cashier closes the session with the counted amount.

```sql
-- Close cash register after all sales are processed
CALL pos_schema.open_close_cash_register_session(
    '<cash_register_id>',
    'close',
    1495.00,  -- Actual amount counted ($500 opening + $995 from sales)
    null
);

-- Verify closure and reconciliation
SELECT
    crs.cash_register_session_id,
    crs.opened_at,
    crs.closed_at,
    crs.opening_amount,
    crs.closing_amount,
    (crs.closing_amount - crs.opening_amount) as difference,
    COUNT(crs_sale.sale_id) as total_sales,
    COALESCE(SUM(s.total_amount), 0) as expected_total
FROM pos_schema.cash_register_session crs
LEFT JOIN pos_schema.cash_register_sale crs_sale ON crs.cash_register_session_id = crs_sale.cash_register_session_id
LEFT JOIN pos_schema.sale s ON crs_sale.sale_id = s.sale_id
WHERE crs.cash_register_id = '<cash_register_id>' AND crs.is_active = false
GROUP BY crs.cash_register_session_id;
```

## Idempotency & Safety

- Tests and scripts should be idempotent: check for existing `sale`, `product_variant`, or `tenant_customer` records before inserting, or use `ON CONFLICT` where unique constraints exist.
- Triggers are implemented to avoid infinite loops (example: `WHEN` clauses and avoiding updating the same row inside a trigger).

---

## Complete Sale-to-Cash Flow Summary

Here is the complete end-to-end journey of a transaction from register open to close:

### 1. Morning: Open Cash Register

```sql
-- Cashier opens register with $500 float
CALL pos_schema.open_close_cash_register_session(
    '<cash_register_id>',
    'open',
    500.00,
    '<cashier_user_id>'
);
```

### 2. Customer Arrives: Create Sale

```sql
-- Create sale for the transaction
INSERT INTO pos_schema.sale (branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
VALUES ('<branch_id>', 1, 995.00, 129.35, 1124.35, false)
RETURNING sale_id;

-- Add items (product variants)
INSERT INTO pos_schema.sale_item (sale_id, tenant_id, product_variant_id, quantity, unit_price, total_price)
VALUES ('<sale_id>', '<tenant_id>', '<variant_id>', 1, 850.00, 850.00), ...;
```

### 3. Payment: Register & Verify

```sql
-- Register payment(s)
INSERT INTO pos_schema.customer_payment (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
VALUES ('<customer_id>', '<sale_id>', 3, 1124.35, 1, false)
RETURNING customer_payment_id;

-- Verify payment (triggers cascade)
CALL pos_schema.verify_customer_payment('<payment_id>');
-- ✓ sale.is_completed = true
-- ✓ bill created automatically
-- ✓ points awarded
-- ✓ linked to cash_register_session
```

### 4. Automatic: Bill & Points

- Bill is created with full audit trail.
- Loyalty points are calculated and awarded: `1124.35 × 10 = 11,243 points`.
- Sale is linked to the active cash register session.

### 5. End of Day: Close Register

```sql
-- Cashier counts cash and closes register
CALL pos_schema.open_close_cash_register_session(
    '<cash_register_id>',
    'close',
    1495.00,  -- Opening $500 + Sales $995
    null
);

-- Reconciliation shows perfect match
```

---

## Common Troubleshooting

- If no bill is created after payment, confirm `pos_schema.verify_customer_payment` updated `sale.is_completed` and that the `create_bill` trigger exists on `pos_schema.sale`.
- If points are not awarded, check `pos_schema.loyalty_program` and `pos_schema.tenant_customer_score` existence and that `verify_customer_payment` calls the points logic.

## Quick Debugging Queries

- Check sale and completion status:

```sql
SELECT sale_id, total_amount, is_completed FROM pos_schema.sale WHERE sale_id = '<sale_id>';
```

- List payments for a sale:

```sql
SELECT
    cp.customer_payment_id,
    cp.payment_method_id,
    cp.payment_amount,
    cp.verified,
    cp.payment_date
FROM pos_schema.customer_payment cp
WHERE cp.sale_id = '<sale_id>'
ORDER BY cp.payment_date;
```

- Verify bill created:

```sql
SELECT
    b.bill_id,
    b.sale_id,
    b.subtotal_amount,
    b.tax_amount,
    b.total_amount,
    b.billed_at
FROM pos_schema.bill b
WHERE b.sale_id = '<sale_id>';
```

- Check customer points:

```sql
SELECT
    tcs.tenant_customer_id,
    tcs.score as available_points,
    tcs.lifetime_score as total_earned,
    tcs.score_redeemed as total_redeemed,
    tcs.last_earned_at
FROM pos_schema.tenant_customer_score tcs
WHERE tcs.tenant_customer_id = '<tenant_customer_id>'
AND tcs.tenant_id = '<tenant_id>';
```

- Verify sale linked to cash register session:

```sql
SELECT
    crs.cash_register_session_id,
    crs.user_id,
    crs.opened_at,
    crs.closed_at,
    crs.is_active,
    COUNT(crs_sale.sale_id) as sales_in_session,
    COALESCE(SUM(s.total_amount), 0) as session_revenue
FROM pos_schema.cash_register_session crs
LEFT JOIN pos_schema.cash_register_sale crs_sale ON crs.cash_register_session_id = crs_sale.cash_register_session_id
LEFT JOIN pos_schema.sale s ON crs_sale.sale_id = s.sale_id
WHERE crs.cash_register_session_id = '<session_id>'
GROUP BY crs.cash_register_session_id;
```

- Reconcile cash register daily:

```sql
SELECT
    crs.cash_register_session_id,
    crs.opening_amount,
    crs.closing_amount,
    (crs.closing_amount - crs.opening_amount) as difference,
    COUNT(DISTINCT crs_sale.sale_id) as total_sales,
    COALESCE(SUM(s.total_amount), 0) as expected_revenue
FROM pos_schema.cash_register_session crs
LEFT JOIN pos_schema.cash_register_sale crs_sale ON crs.cash_register_session_id = crs_sale.cash_register_session_id
LEFT JOIN pos_schema.sale s ON crs_sale.sale_id = s.sale_id
WHERE crs.is_active = false
GROUP BY crs.cash_register_session_id
ORDER BY crs.closed_at DESC;

## Notes for Integrators / Developers

- Keep client code to compute prices consistent with server-side triggers. Server-side functions (`calculate_total_price`, `calculate_bill_total`) will enforce totals if used.
- When modifying payment flows (e.g., new payment methods), ensure that `verify_customer_payment` still recognizes and correctly aggregates verified payments.
- **Product Variants**: All references to sellable items in `sale_item` must use `product_variant_id`, not `product_id`. Base products are templates only.
- **Cash Register Reconciliation**: Always close the cash register session at day-end. The difference between closing and opening amounts should match the sum of all sales in that session (accounting for cash/coin handling).
- **Loyalty Points**: Points are awarded automatically on sale completion. Point redemptions require verification that sufficient available points exist before allowing redemption payment acceptance.
- **Tax Calculation**: Tax rates are tenant-region-specific. Ensure the correct `tax_rate` is fetched based on the tenant's region when calculating `tax_amount` during sale creation.
- Tests shipped under `test/pos/` in the repository demonstrate idempotent scenarios and can be used as REFERENCES.

If you want to run an end-to-end test that exercises the entire flow, refer to [`test/pos/testClientPay.sql`](../test/pos/testClientPay.sql) which includes all steps from cash register open to close, complete with loyalty point accrual and multi-payment scenarios.
```
