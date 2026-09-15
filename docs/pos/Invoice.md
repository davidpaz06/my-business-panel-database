# Invoice

This document describes the single invoice concept in the POS system: `pos_schema.invoice`, its line items (`invoice_item`) and its payment links (`invoice_payment`). It covers the table shape, the automatic creation trigger fired on sale completion, how returns repoint and adjust the invoice, and how loyalty points are awarded from it.

**Context:** Costa Rica's Hacienda electronic invoicing (XML-signed "factura electrónica", key numbers, consecutive numbers, `hacienda_status` polling) has been removed from the system entirely. What used to be called the "digital sale invoice" — the automatic internal invoice generated on sale completion — is now the system's only invoice concept, and its tables were renamed from `digital_sale_invoice(_item/_payment)` to plain `invoice(_item/_payment)`. There is no longer a second, Hacienda-compliant invoice type running alongside it.

## Scope

Retail checkout where a completed sale automatically produces exactly one `invoice`. The same flow applies regardless of whether the sale was paid with a single payment or multiple (hybrid) payments — see [`Hybrid Payments.md`](./Hybrid%20Payments.md) for the payment-side detail. This document focuses on the invoice itself: its shape, its creation, and how returns and loyalty points interact with it.

## Prerequisites

- Tenant, Branch, Products (with a `tax_rate`), Product Variants, and Customer exist in `general_schema.tenant`, `general_schema.branch`, `general_schema.product`, `general_schema.product_variant`, and `general_schema.tenant_customer`.
- `pos_schema` objects deployed: tables `sale`, `sale_item`, `customer_payment`, `invoice`, `invoice_item`, `invoice_payment`, `return_transaction`, `return_product`, `score_transaction`; functions/triggers `check_sale_payment_completion`, `verify_customer_payment`, `create_invoice`, `on_sale_completed_create_invoice`, `update_on_return`, `award_points`, `get_invoice`, `calculate_invoice_total`.
- A `sale` row requires a `sale_condition` code (`pos_schema.sale_condition`, e.g. `'01'` = Contado) — this is unrelated to the old Hacienda "sale condition" field and is just a plain catalog FK on every sale.

## Schema

```sql
pos_schema.invoice
├── invoice_id                 UUID PK
├── tenant_customer_id         UUID FK -> general_schema.tenant_customer (nullable, ON DELETE SET NULL)
├── sale_id                    UUID FK -> pos_schema.sale (NOT NULL, ON DELETE CASCADE)
├── currency_id                INTEGER FK -> general_schema.currency
├── subtotal_amount            NUMERIC(10,2)
├── tax_amount                 NUMERIC(10,2)
├── total_amount                NUMERIC(10,2) (subtotal_amount + tax_amount, kept in sync by a trigger)
├── due_date                   DATE (default current_date)
├── cash_register_session_id   UUID FK -> pos_schema.cash_register_session (nullable, ON DELETE SET NULL)
├── points_accumulated         INTEGER (default 0)
├── ad_message                 TEXT
├── amount_paid                NUMERIC(10,2) (default 0)
├── change_amount              NUMERIC(10,2) (default 0)
├── invoiced_at                TIMESTAMP (default current_timestamp)
└── updated_at                 TIMESTAMP (default current_timestamp)

pos_schema.invoice_item
├── invoice_item_id            UUID PK
├── invoice_id                 UUID FK -> pos_schema.invoice (ON DELETE CASCADE)
├── sale_item_id                UUID FK -> pos_schema.sale_item (ON DELETE CASCADE)
├── tenant_id                  UUID NOT NULL
├── product_variant_id         UUID
├──   (tenant_id, product_variant_id) FK -> general_schema.product_variant
├── tax_rate_id                 INTEGER FK -> general_schema.tax_rate (nullable, ON DELETE SET NULL)
├── description                VARCHAR(255)
├── quantity                   INTEGER
├── unit_price                 NUMERIC(10,2)
├── subtotal                   NUMERIC(10,2) (quantity x unit_price)
├── tax_rate_percentage         NUMERIC(5,2) (resolved from tax_rate.rate_percentage; 0 if null)
├── tax_amount                 NUMERIC(10,2) (subtotal x tax_rate_percentage / 100)
├── total_price                 NUMERIC(10,2) (subtotal + tax_amount)
├── created_at                 TIMESTAMP
└── updated_at                 TIMESTAMP

pos_schema.invoice_payment
├── invoice_payment_id          UUID PK
├── invoice_id                  UUID FK -> pos_schema.invoice (ON DELETE CASCADE)
├── customer_payment_id         UUID FK -> pos_schema.customer_payment (ON DELETE CASCADE)
├── payment_amount               NUMERIC(10,2)
├── created_at                  TIMESTAMP
├── updated_at                  TIMESTAMP
└── UNIQUE (invoice_id, customer_payment_id)
```

`product.product_id`/`product_category.product_category_id` are surrogate UUID keys (CABYS has been removed entirely — `general_schema.product` is no longer keyed by a 13-digit tax code, and `product_variant`/`invoice_item` link to it via plain `product_id`, not a code).

## Auto-Creation Trigger Flow

An invoice is **always** created automatically — there is no manual/application-driven invoice type anymore. The trigger `on_sale_completed_create_invoice` fires `AFTER UPDATE OF is_completed ON pos_schema.sale`, `WHEN (old.is_completed IS FALSE AND new.is_completed IS TRUE)`, and calls `pos_schema.create_invoice()`. That function:

1. Guards against duplicate creation: if an `invoice` already exists for `sale_id`, it logs a notice and returns without doing anything else.
2. Resolves `tenant_customer_id` from the first `customer_payment` row for the sale (not from `sale.tenant_customer_id` directly) — if the sale had no customer-linked payment, the invoice's `tenant_customer_id` ends up `NULL`.
3. Resolves `tenant_id` from `general_schema.tenant_customer` using that customer id.
4. Copies `currency_id` from the sale.
5. Resolves the branch's active `cash_register_session` / `cash_register` for the sale's branch.
6. Inserts the `invoice` row with placeholder zero totals.
7. Inserts one `invoice_item` row per `sale_item`, resolving `tax_rate_id` via `product_variant.product_id -> product.tax_rate_id -> tax_rate.rate_percentage`, and computing `subtotal`, `tax_rate_percentage`, `tax_amount`, `total_price` per line.
8. Recomputes the invoice's `subtotal_amount` and `tax_amount` as the sum of the just-inserted `invoice_item` rows, and updates the `invoice` row (`total_amount` is then kept in sync by the `calculate_invoice_total` trigger, `subtotal_amount + tax_amount`).
9. Links every **verified** `customer_payment` row for the sale into `invoice_payment` (one row per payment, `payment_amount` copied as-is). This insert fires `award_points()` per row (see below).

The whole function body is wrapped in `EXCEPTION WHEN OTHERS` — any error during invoice creation is caught, logged via `RAISE NOTICE`, and swallowed; the sale update itself always succeeds regardless of whether invoice creation succeeded. See "Known issues" below — this currently matters in practice.

## Returns Link to the Invoice

`return_transaction.invoice_id` is `NOT NULL` and `REFERENCES pos_schema.invoice(invoice_id) ON DELETE CASCADE` — every return must point at an existing invoice; there is no longer a nullable/either-or choice between a digital and an electronic invoice id.

Returns are recorded as:

1. The application inserts a `return_transaction` row (`invoice_id`, `tenant_customer_id`, `total_refund_amount`, `refund_method`, `return_status_id`, `description` — `description` is `NOT NULL`).
2. The application inserts one `return_product` row per returned line (`return_transaction_id`, `sale_item_id`, `quantity`, `unit_price`). `total_price` on `return_product` is computed automatically by the `calculate_total_price` trigger (`quantity * unit_price`) — do not set it manually.
3. Each `return_product` insert fires `update_on_return()` (`AFTER INSERT ON pos_schema.return_product`), which:
   - Looks up the underlying `sale_item` and, through it, the invoice for that sale (`SELECT invoice_id FROM pos_schema.invoice WHERE sale_id = ...`) — raises an exception if no invoice exists for the sale (this error is **not** swallowed).
   - Rejects returning more than was purchased.
   - If the return exhausts the line's quantity: explicitly deletes the matching `invoice_item` row, then deletes the `sale_item` row (which would also `CASCADE` the `invoice_item`, but the function deletes it explicitly first).
   - Otherwise: decrements `sale_item.quantity`/`total_price`, and recomputes the matching `invoice_item`'s `quantity`, `subtotal`, `tax_rate_percentage`, `tax_amount`, `total_price` using the same `product_variant.product_id -> product.tax_rate_id` resolution as `create_invoice()`.
   - Recomputes `invoice.subtotal_amount`/`tax_amount`/`total_amount` from the remaining `invoice_item` rows.
   - Recomputes `sale.subtotal_amount`/`tax_amount`/`total_amount` from the remaining `sale_item` rows (with per-item tax resolved the same way).

A full return of every line zeroes the invoice and sale totals and leaves no `sale_item`/`invoice_item` rows; a partial return leaves the invoice and sale reconciled to what remains.

## Loyalty Points via `invoice_payment`

Points are awarded by `award_points()`, fired `AFTER INSERT ON pos_schema.invoice_payment` (trigger `on_invoice_payment_award_points`), once per inserted row:

1. Skips if a `score_transaction` with `transaction_type_id = 1` already exists for the invoice (idempotency guard — matters because `create_invoice()` inserts all of an invoice's `invoice_payment` rows in a single multi-row `INSERT ... SELECT`, which fires this trigger once per row).
2. Resolves `tenant_customer_id` from the invoice; if the invoice has no customer, it logs a notice and skips (no exception).
3. Sums **all** `invoice_payment` amounts for the invoice where the underlying `customer_payment.is_points_redemption = false` — i.e. the cash/card portion only, never the points-redeemed portion.
4. Computes points via `calculate_purchase_score()` (tenant's active `loyalty_program.points_earned_per_currency_unit`, floored) and, if positive, upserts `tenant_customer_score` and inserts one `score_transaction` row (`transaction_type_id = 1`, `points`, `invoice_id`).

Net effect: one invoice produces at most one points-earning `score_transaction`, sized off the full cash/card total of that invoice, regardless of how many `invoice_payment` rows fed it.

## Lifecycle Flow

```
1. Sale created (is_completed = false)
   |
2. Customer payment(s) registered and verified via verify_customer_payment()
   |
3. When verified payments >= sale.total_amount:
   |  sale.is_completed = true
   |
   +--- TRIGGER: create_invoice()
   |    +-- INSERT invoice (placeholder totals)
   |    +-- INSERT invoice_item (per sale_item, per-item tax from product -> tax_rate)
   |    +-- UPDATE invoice (recompute totals from item aggregates)
   |    \-- INSERT invoice_payment (per verified customer_payment)
   |         \-- TRIGGER: award_points() -- once per invoice, sized off cash/card total
   |
   \--- TRIGGER: link_sale_to_session()
        \-- INSERT cash_register_sale
   |
4. (optional) Return recorded:
   |  INSERT return_transaction (invoice_id NOT NULL)
   |  INSERT return_product (per returned line)
   \--- TRIGGER: update_on_return()
        +-- adjusts/removes sale_item and invoice_item
        +-- recomputes invoice totals
        \-- recomputes sale totals
```

## Query Examples

```sql
-- Retrieve the invoice for a sale (via the helper function)
SELECT * FROM pos_schema.get_invoice('<sale_id>');

-- Retrieve the invoice row directly
SELECT * FROM pos_schema.invoice WHERE sale_id = '<sale_id>';

-- List items on an invoice
SELECT * FROM pos_schema.invoice_item WHERE invoice_id = '<invoice_id>' ORDER BY created_at;

-- List payments linked to an invoice
SELECT ip.*, cp.payment_method_id, cp.payment_amount
FROM pos_schema.invoice_payment ip
JOIN pos_schema.customer_payment cp ON ip.customer_payment_id = cp.customer_payment_id
WHERE ip.invoice_id = '<invoice_id>';

-- List returns against an invoice
SELECT rt.*, rp.sale_item_id, rp.quantity, rp.unit_price, rp.total_price
FROM pos_schema.return_transaction rt
JOIN pos_schema.return_product rp ON rp.return_transaction_id = rt.return_transaction_id
WHERE rt.invoice_id = '<invoice_id>';
```

## Common Troubleshooting

- **No invoice after payment**: Confirm `pos_schema.check_sale_payment_completion` actually set `sale.is_completed = true`, and that the `on_sale_completed_create_invoice` trigger exists on `pos_schema.sale`. Because `create_invoice()` swallows all errors (`EXCEPTION WHEN OTHERS`), a broken insert inside it will **not** raise to the caller — the sale still shows `is_completed = true` with no invoice underneath, and the only trace is a `RAISE NOTICE 'Error creating invoice: %'` in the server log. See "Fixed while writing this doc" below for a previously-broken insert that used to trigger exactly this.
- **Return fails with "Invoice not found for sale"**: `update_on_return()` requires an `invoice` row to already exist for the sale before any `return_product` can be inserted — this is not swallowed, unlike invoice creation.
- **Points not awarded**: check that the invoice has a non-null `tenant_customer_id` (an anonymous/walk-in sale with no customer-linked payment produces an invoice with `tenant_customer_id = NULL`, and `award_points()` skips silently), and that the tenant has an `is_active = true` `loyalty_program` row.
- **Totals mismatch**: `invoice.total_amount` is recomputed by the `calculate_invoice_total` trigger as `subtotal_amount + tax_amount` on every insert/update — do not set `total_amount` directly and expect it to stick.

### Fixed while writing this doc (were pre-existing defects, unrelated to the CR->VE terminology change)

- `create_invoice()`'s `INSERT INTO pos_schema.invoice (...)` list referenced a `cash_register_id` column that does not exist on `invoice` (only `cash_register_session_id` does), and the resolved variable held the register id rather than the session id. Because the whole function body is wrapped in `EXCEPTION WHEN OTHERS`, this silently broke invoice creation on every sale completion. Fixed: the variable and the inserted column are now both `cash_register_session_id`, sourced from `crs.cash_register_session_id`.
- `pos_schema.get_invoice(_sale_id)` selected `b.created_at`, but `invoice` has no such column (only `invoiced_at`). Fixed: renamed the returned column to `invoiced_at` and select `b.invoiced_at`.

## Notes for Integrators / Developers

- The invoice is created **automatically only** — there is no code path (trigger or otherwise) for creating an invoice manually, and no second invoice type to keep in sync with it.
- `invoice_item.tax_rate_id` is resolved dynamically from `product_variant.product_id -> product.tax_rate_id` at both creation and return time — it is not a static copy, so changing a product's tax rate after the fact does not retroactively change existing invoice items (they are only recomputed by `update_on_return()` when a return touches that line).
- `return_transaction.invoice_id` is `NOT NULL` — a return cannot be recorded before its invoice exists.
- Tests demonstrating the full flow are available in [`test/pos/testInvoice.sql`](../../test/pos/testInvoice.sql).
