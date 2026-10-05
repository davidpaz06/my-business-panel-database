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
├── tenant_id                  UUID FK -> general_schema.tenant (set by trg_invoice_assign_number; NULL on invoices issued before migration 040)
├── invoice_number             INTEGER (per-tenant sequential, shown as 8 digits e.g. 00055703; NULL before migration 040)
├── tenant_customer_id         UUID FK -> general_schema.tenant_customer (required on every NEW invoice -- see "Required customer"; column stays nullable for historical rows, ON DELETE SET NULL)
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
2. Resolves `tenant_customer_id` from `sale.tenant_customer_id`. Only for historical pending sales created without a customer does it fall back to the first customer-linked `customer_payment`. If neither exists the insert is rejected (see "Required customer").
3. `tenant_id` and `invoice_number` are assigned by the `BEFORE INSERT` trigger `trg_invoice_assign_number` (see "Invoice numbering"), not by this function.
4. Copies `currency_id` from the sale.
5. Resolves the branch's active `cash_register_session` / `cash_register` for the sale's branch.
6. Inserts the `invoice` row with placeholder zero totals.
7. Inserts one `invoice_item` row per `sale_item`, resolving `tax_rate_id` via `product_variant.product_id -> product.tax_rate_id -> tax_rate.rate_percentage`, and computing `subtotal`, `tax_rate_percentage`, `tax_amount`, `total_price` per line.
8. Recomputes the invoice's `subtotal_amount` and `tax_amount` as the sum of the just-inserted `invoice_item` rows, and updates the `invoice` row (`total_amount` is then kept in sync by the `calculate_invoice_total` trigger, `subtotal_amount + tax_amount`).
9. Links every **verified** `customer_payment` row for the sale into `invoice_payment` (one row per payment, `payment_amount` copied as-is). This insert fires `award_points()` per row (see below).

Since migration 040 the function no longer wraps its body in `EXCEPTION WHEN OTHERS`: an error during invoice creation propagates and rolls back the sale completion. Before, errors were swallowed and a sale could close without an invoice; with numbering and a required customer that would have been silent data loss.

## Invoice numbering

`invoice.invoice_number` is the business's internal sequential number (what the SENIAT-style ticket prints as `FACTURA: 00055703`). The machine-homologation (MH) code that fiscal-machine receipts carried is not modeled: it is no longer used.

- **Per tenant.** Each tenant has its own counter row in `pos_schema.invoice_counter`.
- **Assigned in the database**, by the `BEFORE INSERT` trigger `trg_invoice_assign_number`, because an invoice is created by two paths: `sale.service` inserts it directly when it creates an already-completed sale, and `create_invoice()` is the fallback for sales completed later by `UPDATE`. One assignment point covers both.
- **Gapless.** The counter is incremented with an upsert that locks the tenant's row until commit; if the transaction rolls back, so does the increment. It also serializes invoice creation per tenant.
- **Historical invoices keep `invoice_number = NULL`** (no renumbering, no backfill). Presentation should hide the number line for those.
- Unique per tenant through the partial index `uq_invoice_tenant_number`. The 8-digit zero padding is presentation-only (`LPAD(invoice_number::text, 8, '0')`).

## Required customer

Anonymous sales no longer exist: `sale` and `invoice` inserts without `tenant_customer_id` are rejected by the `BEFORE INSERT` triggers `trg_sale_require_customer` / `trg_invoice_require_customer` (`pos_schema.require_customer()`). These are insert-time triggers on purpose, not a `CHECK ... NOT VALID`: a not-valid check is still evaluated on every later `UPDATE` of an old row, which would block, for example, refunding a historical anonymous sale. Historical rows without customer stay readable and updatable.

For legal persons (J/G/C) `general_schema.tenant_customer.business_name` holds the razon social printed on the invoice instead of `first_name`/`last_name`. That it is mandatory for those types, and that the customer's address is mandatory, is enforced by the backend, not by the database (existing customers may not have them).

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

- **No invoice after payment**: Confirm `pos_schema.check_sale_payment_completion` actually set `sale.is_completed = true`, and that the `on_sale_completed_create_invoice` trigger exists on `pos_schema.sale`. Since migration 040 `create_invoice()` no longer swallows errors, so a failing insert (including a sale with no customer) raises to the caller and rolls the completion back. In environments built by migrations rather than bootstrap, also check that the legacy `on_sale_completed_create_digital_sale_invoice` trigger is gone (migration 040 drops it): before that, it pointed at a table that no longer exists and the new trigger was never wired. "Fixed while writing this doc" below describes an older insert defect that used to be hidden by the swallowed error.
- **Return fails with "Invoice not found for sale"**: `update_on_return()` requires an `invoice` row to already exist for the sale before any `return_product` can be inserted — this is not swallowed.
- **Points not awarded**: check that the invoice has a non-null `tenant_customer_id` (always true for invoices created after migration 040; only historical invoices from anonymous sales have `NULL`, and `award_points()` skips them silently), and that the tenant has an `is_active = true` `loyalty_program` row.
- **Totals mismatch**: `invoice.total_amount` is recomputed by the `calculate_invoice_total` trigger as `subtotal_amount + tax_amount` on every insert/update — do not set `total_amount` directly and expect it to stick.

### Fixed while writing this doc (were pre-existing defects, unrelated to the CR->VE terminology change)

- `create_invoice()`'s `INSERT INTO pos_schema.invoice (...)` list referenced a `cash_register_id` column that does not exist on `invoice` (only `cash_register_session_id` does), and the resolved variable held the register id rather than the session id. Because the whole function body was then wrapped in `EXCEPTION WHEN OTHERS` (removed in migration 040), this silently broke invoice creation on every sale completion. Fixed: the variable and the inserted column are now both `cash_register_session_id`, sourced from `crs.cash_register_session_id`.
- `pos_schema.get_invoice(_sale_id)` selected `b.created_at`, but `invoice` has no such column (only `invoiced_at`). Fixed: renamed the returned column to `invoiced_at` and select `b.invoiced_at`.

## Notes for Integrators / Developers

- The invoice is created **automatically only** — there is no code path (trigger or otherwise) for creating an invoice manually, and no second invoice type to keep in sync with it.
- `invoice_item.tax_rate_id` is resolved dynamically from `product_variant.product_id -> product.tax_rate_id` at both creation and return time — it is not a static copy, so changing a product's tax rate after the fact does not retroactively change existing invoice items (they are only recomputed by `update_on_return()` when a return touches that line).
- `return_transaction.invoice_id` is `NOT NULL` — a return cannot be recorded before its invoice exists.
- Tests demonstrating the full flow are available in [`test/pos/testInvoice.sql`](../../test/pos/testInvoice.sql).
