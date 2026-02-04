# Partial and Full Returns — End-to-End Flow

This document explains the end-to-end flow for processing partial and full product returns at point-of-sale. The goal is to demonstrate that a customer can return one or more items from a billed sale, that each returned item is recorded in pos.return_product, and that the corresponding bill and original sale are automatically adjusted.

Scope: retail returns where returns create return_transaction + return_product rows and triggers update bill totals and reconcile the sale record.

## Prerequisites

- Tenant/Branch/Customer/Product exist in general_schema.\* tables.
- POS objects and functions deployed:
  - Tables: pos.sale, pos.sale_item, pos.customer_payment, pos.bill, pos.return_transaction, pos.return_product.
  - Triggers / functions: pos.update_on_return (trigger on return_product), pos.create_bill, pos.check_sale_payment_completion, general_schema.update_timestamp.

## High-level Flow

1. Customer requests return (partial or full) for a billed sale.
2. Cashier creates a return_transaction linked to the bill.
3. For each returned product line, a return_product row is inserted referencing the original sale_item (sale_item_id), with quantity and unit_price.
4. The insert fires update_on_return trigger which:
   - validates return quantity,
   - inserts/updates return_product (keeps audit of returned items),
   - updates sale_item (decrease or delete),
   - recalculates and updates bill totals (subtotal, tax, total),
   - recalculates and updates sale totals so sale and bill remain reconciled.
5. Optionally process refund (create a refund payment or update cash/card session).
6. System logs return and updates score/stock as configured.

## Detailed Steps & SQL snippets

### 1. Create return transaction (header)

Create a return transaction pointing to the bill you want to adjust.

```sql
INSERT INTO pos.return_transaction (
  bill_id,
  tenant_customer_id,
  total_refund_amount, -- set 0, trigger/script will update after lines inserted
  refund_method,       -- payment_method_id to refund to (optional)
  return_status_id
)
VALUES (
  '<bill_id>', '<tenant_customer_id>', 0.00, 1, -- 1 = cash (example)
  (SELECT return_status_id FROM pos.return_status WHERE status_name = 'pending' LIMIT 1)
)
RETURNING return_transaction_id;
```

### 2. Insert one or more return_product rows (one per returned sale_item)

Each returned product must reference the original sale_item_id. This creates an auditable record of what was returned.

```sql
-- Example: return 2 units of sale_item X and 1 unit of sale_item Y
INSERT INTO pos.return_product (return_transaction_id, sale_item_id, quantity, unit_price)
VALUES
  ('<return_tx_id>', '<sale_item_id_A>', 2, 10.00),
  ('<return_tx_id>', '<sale_item_id_B>', 1, 20.00);
```

- The trigger calculate_total_price on return_product computes total_price = quantity \* unit_price before insert.
- The after-insert trigger update_on_return will run for each inserted row.

### 3. Trigger behavior: validate and reconcile

On each return_product insert, update_on_return should:

- Verify returned quantity <= original sale_item.quantity, otherwise raise.
- Decrease sale_item.quantity (or delete sale_item if remaining quantity = 0).
- Subtract returned line amount from bill.subtotal; recompute tax and total using tenant/region tax rate.
- Update pos.bill totals and pos.sale totals to keep them consistent.
- Optionally record inventory adjustments or refund movements.

Example checks (pseudocode):

- If return reduces all items: bill.subtotal -> 0, tax -> 0, total -> 0; sale_item rows removed; sale totals updated.

### 4. Update return_transaction.total_refund_amount

After inserting return_product rows, update the header with the sum of returned totals:

```sql
UPDATE pos.return_transaction
SET total_refund_amount = (
  SELECT COALESCE(SUM(total_price), 0) FROM pos.return_product
  WHERE return_transaction_id = '<return_tx_id>'
)
WHERE return_transaction_id = '<return_tx_id>';
```

### 5. Process refund (optional)

Record refund to customer via customer_payment or external refund workflow. Example: create a customer_payment with negative or refund semantics, link to bill/refund procedure, or INSERT INTO a refund table per your finance rules.

## Idempotency & Safety

- Use idempotent test scripts: clean existing return_transaction/return_product rows for the test tenant before running.
- Always reference sale_item_id in return_product so returned items are traceable to the original sale.
- Triggers should be defensive: check quantities, prevent double-counting, and avoid modifying the same row repeatedly.
- Wrap multi-step return operations in a transaction if you need atomicity across header, lines and refund processing.

## Common Troubleshooting

- return_product empty after script: ensure your INSERTs commit and no trigger raises an exception causing rollback.
- Returned quantity > purchased: update_on_return should raise an exception; check error logs for the message.
- Bill not updated: verify update_on_return trigger exists on pos.return_product and that tax rate lookup works for tenant/region.
- Sale totals inconsistent: confirm update_on_return recalculates sale_subtotal from remaining sale_item rows and updates sale.tax/total.

## Quick Debugging Queries

- List returns for a bill:

```sql
SELECT rt.return_transaction_id, rt.total_refund_amount, rt.return_date
FROM pos.return_transaction rt
WHERE rt.bill_id = '<bill_id>';
```

- Show returned lines (auditable):

```sql
SELECT rp.return_product_id, rp.sale_item_id, rp.quantity, rp.unit_price, rp.total_price,
       p.sku, p.product_name
FROM pos.return_product rp
JOIN pos.sale_item si ON rp.sale_item_id = si.sale_item_id
JOIN general_schema.product p ON si.product_id = p.product_id AND si.tenant_id = p.tenant_id
WHERE rp.return_transaction_id = '<return_tx_id>';
```

- Verify bill and sale totals after returns:

```sql
SELECT b.subtotal_amount, b.tax_amount, b.total_amount FROM pos.bill b WHERE b.bill_id = '<bill_id>';
SELECT s.subtotal_amount, s.tax_amount, s.total_amount FROM pos.sale s WHERE s.sale_id = '<sale_id>';
```

## Notes for Integrators / Developers

- Always insert a return_product row per returned sale_item — this is the source of truth for returns.
- Keep tax calculation consistent: use tenant → region tax_rate lookup used by update_on_return.
- Decide refund policy: immediate refund, store credit, or exchange — implement corresponding refund flows and link them to return_transaction.
- Provide clear UI feedback showing which items and quantities were returned and updated totals.
- For reporting, use return_product and return_transaction to audit returns independently of sale/sale_item deletions.

This flow ensures every returned product is recorded, the bill reflects the return immediately, and the original sale record is reconciled so reports remain consistent.
