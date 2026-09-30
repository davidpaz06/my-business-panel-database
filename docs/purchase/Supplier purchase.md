# Supplier Purchase

## Purpose

Describe the end-to-end process for creating and processing a supplier purchase in the purchase module, including automatic behaviors, triggers/functions, validation queries and troubleshooting notes.

## Scope

Covers:

- Creating a purchase order with line items
- Automatic supplier invoice and account payable creation
- Recording and verifying payments
- Order status transitions (Pending → Shipped → Delivered)
- Goods receipt creation (subtotal, tax, total and items)
- Three-way matching (order, invoice, goods receipt) and validation

## Prerequisites

- Schemas: `purchase_schema`, `general_schema`, `inventory_schema`
- general_schema data: tenant, branch, products, payment methods, tax rates
- Installed functions/triggers:
  - `purchase_schema.create_purchase_order(...)`
  - `purchase_schema.calculate_purchase_order_total(...)`
  - `purchase_schema.verify_purchase_order_payment(...)`
  - `purchase_schema.start_goods_receipt(purchase_order_id)` — starts receiving (order must be status 2)
  - `purchase_schema.update_goods_receipt_items(goods_receipt_id, items, tenant_id)` — edits while PENDING
  - `purchase_schema.confirm_goods_receipt(goods_receipt_id)` — locks items, applies inventory, runs matching, sets order to Delivered
  - `purchase_schema.cancel_goods_receipt(goods_receipt_id)` — deletes a PENDING receipt (started by mistake) so it can be restarted clean
  - `purchase_schema.execute_three_way_matching(...)` (called by confirm_goods_receipt)
  - `purchase_schema.guard_purchase_order_delivery_transition()` (trigger — blocks any direct UPDATE to status 3 outside confirm_goods_receipt)

## Key entities

- purchase_order / purchase_order_item
- supplier_invoice / supplier_invoice_item
- purchase_account_payable
- purchase_order_payment
- goods_receipt / goods_receipt_item
- three_way_matching

## Expected automated behaviors

- create_purchase_order():
  - inserts purchase_order and purchase_order_item rows
  - computes subtotal and tax, inserts purchase_account_payable
  - inserts supplier_invoice and supplier_invoice_item when invoice requested
  - For each item being purchased, if the product_variant.supplier_id is NULL,
    it is automatically updated to the supplier_id from the purchase order
  - This ensures that after first purchase from a supplier, the product is now
    associated with that supplier for future efficiency and consistency
  - If any purchased items are composite products (bundles/lotes), the same supplier_id
    is automatically inherited by all their child components that don't have a supplier
- verify_purchase_order_payment(payment_id):
  - marks payment verified and updates purchase_account_payable status/amounts
  - when fully paid, marks supplier_invoice.paid = true
- start_goods_receipt(purchase_order_id) (order must be status 2/Shipped):
  - inserts goods_receipt row (status PENDING, subtotal/tax copied from purchase_account_payable)
  - inserts goods_receipt_item rows pre-filled from purchase_order_item, as an editable checklist
  - idempotent while PENDING: calling it again on the same order returns the same goods_receipt_id
- update_goods_receipt_items(goods_receipt_id, items, tenant_id) (only while status PENDING):
  - deletes and reinserts goods_receipt_item from the given items array (product_variant_id, quantity_received)
  - this is where a receiving discrepancy (wrong/short/damaged shipment) gets corrected
  - purchase_order_item is never touched — it stays the immutable record of what was originally ordered
- confirm_goods_receipt(goods_receipt_id) (only while status PENDING, requires >= 1 item):
  - sets goods_receipt.status = CONFIRMED (locks it — update_goods_receipt_items rejects further edits)
  - applies inventory from goods_receipt_item (not purchase_order_item) via apply_inventory_on_delivery
  - sets purchase_order.purchase_order_status_id = 3 (the only legitimate path there — see guard trigger below)
  - calls execute_three_way_matching(order_id, goods_receipt_id)
  - if quantities_matched or amounts_matched come back false, auto-opens a purchase_dispute
    (MISSING_GOODS / PRICE_MISMATCH) instead of relying on someone reading the matching report
- cancel_goods_receipt(goods_receipt_id) (only while status PENDING):
  - deletes the goods_receipt row (cascade removes its goods_receipt_item rows)
  - purchase_order is left untouched (still status 2/Shipped) — start_goods_receipt can be called again
  - rejects cancelling a CONFIRMED receipt: that one already applied inventory and matching, not reversible here
- execute_three_way_matching():
  - compares subtotals, tax amounts and totals (with tolerance)
  - compares summed quantities across order, invoice and receipt
  - inserts a single three_way_matching row and sets amounts_matched / quantities_matched / is_matched

## Step-by-step flow

1. Create purchase order (application)
   - Provide supplier, warehouse, expected delivery date, items (product_id, quantity_ordered, unit_price)
   - Example:
     SELECT purchase.create_purchase_order(... p_items := jsonb_build_array(...))
   - Result: order + items + purchase_account_payable + supplier_invoice + supplier_invoice_item

2. Validate created records
   - Check order, items, invoice and invoice items exist.

3. Make payments (partial or full)
   - Insert purchase_order_payment rows (verified = false), then call:
     CALL purchase.verify_purchase_order_payment(<payment_id>);
   - Account payable updates account_status (Pending / Partial Paid / Paid) and amounts.
   - When Paid, supplier_invoice.paid = true.

4. Update order status to Shipped (optional)
   - UPDATE purchase_order set purchase_order_status_id = 2

5. Receive the goods (three explicit steps, not a status-change side effect)
   - SELECT purchase_schema.start_goods_receipt('<order-uuid>')
     -> goods_receipt (PENDING) + goods_receipt_item checklist pre-filled from purchase_order_item
   - (optional) CALL purchase_schema.update_goods_receipt_items('<goods-receipt-uuid>', '<items jsonb>', '<tenant-uuid>')
     -> corrects quantity_received / which products actually arrived, before anything is finalized
   - CALL purchase_schema.confirm_goods_receipt('<goods-receipt-uuid>')
     -> locks the receipt, applies inventory, runs three-way matching, sets order status to 3 (Delivered)
   - A direct `UPDATE purchase_order SET purchase_order_status_id = 3` is rejected by
     `guard_purchase_order_delivery_transition_trigger` — status 3 is only reachable via confirm_goods_receipt().

6. Three-way matching
   - execute_three_way_matching() compares:
     - Subtotals (order vs invoice vs receipt)
     - Tax amounts
     - Totals (subtotal + tax)
     - Quantities (sum of quantities by source)
   - If all comparisons within tolerance (e.g., 0.01), sets matched flags true.

## Validation queries

- Check invoice and payable:

`````sql
  SELECT _ FROM purchase.supplier_invoice WHERE purchase_order_id = '<order-uuid>';
  SELECT _ FROM purchase.purchase_account_payable WHERE purchase_order_id = '<order-uuid>';
```

- Check items detail:
````sql
  SELECT p.sku, soi.quantity_ordered FROM purchase.purchase_order_item soi JOIN general_schema.product p USING (product_id) WHERE soi.purchase_order_id = '<order-uuid>' ORDER BY p.sku;
  SELECT p.sku, sii.quantity_billed FROM purchase.supplier_invoice_item sii JOIN general_schema.product p USING (product_id) WHERE sii.supplier_invoice_id = '<invoice-uuid>' ORDER BY p.sku;
  SELECT p.sku, gri.quantity_received FROM purchase.goods_receipt_item gri JOIN general_schema.product p USING (product_id) WHERE gri.goods_receipt_id = '<goods-receipt-uuid>' ORDER BY p.sku;
`````

- Check three-way matching:

  ```sql
  SELECT \* FROM purchase.three_way_matching WHERE purchase_order_id = '<order-uuid>';
  ```

- Totals and quantities:

```sql
  SELECT coalesce(sum(quantity_ordered \* unit_price),0) AS order_subtotal, coalesce(sum(quantity_ordered),0) AS order_qty FROM purchase.purchase_order_item WHERE purchase_order_id = '<order-uuid>';
  SELECT subtotal_amount, tax_amount, total_amount FROM purchase.supplier_invoice WHERE purchase_order_id = '<order-uuid>';
  SELECT subtotal_amount, tax_amount, total_amount FROM purchase.goods_receipt WHERE purchase_order_id = '<order-uuid>';
  SELECT coalesce(sum(quantity_billed),0) AS invoice_qty FROM purchase.supplier_invoice_item WHERE supplier_invoice_id = '<invoice-uuid>';
  SELECT coalesce(sum(quantity_received),0) AS receipt_qty FROM purchase.goods_receipt_item WHERE goods_receipt_id = '<goods-receipt-uuid>';
```

## Common failure modes & troubleshooting

- quantities_matched = false despite matching sums:
  - ensure execute_three_way_matching() runs after all goods_receipt_item rows are inserted (call matching at end of goods_receipt creation function).
  - check for duplicate/missing matching rows (function should be idempotent and return early if matching exists).
  - inspect per-product SKU detail to detect mis-matched product_id or tenant_id mismatches.
- amounts_matched false:
  - verify comparison uses subtotals (without tax) and tax amounts separately; check rounding tolerance.
  - ensure goods_receipt stores correct subtotal and tax (copied from purchase_account_payable or computed consistently).
- quantities_matched always true regardless of what actually arrived (historical bug, fixed in
  migration 037-goods-receipt-workflow): goods_receipt_item used to be an automatic copy of
  purchase_order_item made in the same instant the order flipped to status 3, so there was never a
  human correction step and the receipt-vs-order comparison was a tautology. Receiving is now split
  into start_goods_receipt / update_goods_receipt_items / confirm_goods_receipt precisely so a real
  quantity discrepancy can exist and be caught.
- discrepancy detected but nobody notices: confirm_goods_receipt() auto-opens a purchase_dispute
  (MISSING_GOODS for quantities_matched = false, PRICE_MISMATCH for amounts_matched = false) instead
  of only writing a row to three_way_matching — check `purchase_schema.purchase_dispute` for open items.

## Implementation notes / best practices

- Insert goods_receipt and items within the same transaction, then call matching to guarantee item visibility.
- Use a small tolerance (0.01) for numeric comparisons.
- Keep three_way_matching insertion idempotent (skip if exists).
- Log notices in tests to show per-item details when debugging mismatches.

## Quick example sequence

1. SELECT create_purchase_order(...) → order, items, invoice, payable
2. INSERT payments → CALL verify_purchase_order_payment(...) until paid
3. UPDATE purchase_order SET purchase_order_status_id = 2 (Shipped)
4. SELECT start_goods_receipt(order_id) → goods_receipt (PENDING) + checklist items
5. (optional) CALL update_goods_receipt_items(goods_receipt_id, corrected_items, tenant_id)
6. CALL confirm_goods_receipt(goods_receipt_id) → inventory applied, matching runs, order → Delivered
7. SELECT \* FROM three_way_matching → amounts_matched / quantities_matched reflect what was actually
   confirmed; a false here means confirm_goods_receipt already opened a purchase_dispute automatically

## REFERENCES

- Schema: purchase (purchase_order, supplier_invoice, goods_receipt, three_way_matching)
- Functions: purchase.\* (see repository functions folder)
