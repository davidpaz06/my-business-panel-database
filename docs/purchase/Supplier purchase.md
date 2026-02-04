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

- Schemas: `purchase`, `general_schema`, `inventory_schema`
- general_schema data: tenant, branch, products, payment methods, tax rates
- Installed functions/triggers:
  - `purchase.create_purchase_order(...)`
  - `purchase.calculate_purchase_order_total(...)`
  - `purchase.verify_purchase_order_payment(...)`
  - `purchase.create_goods_receipt()` (trigger on order status change)
  - `purchase.execute_three_way_matching(...)` (called after items are inserted)

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
- verify_purchase_order_payment(payment_id):
  - marks payment verified and updates purchase_account_payable status/amounts
  - when fully paid, marks supplier_invoice.paid = true
- create_goods_receipt() (triggered when purchase_order status → Delivered):
  - inserts goods_receipt row (subtotal, tax)
  - inserts goods_receipt_item rows copying order quantities
  - calls execute_three_way_matching(order_id, goods_receipt_id) after all items inserted
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

5. Update order status to Delivered → goods receipt created automatically
   - UPDATE purchase_order set purchase_order_status_id = 3
   - Trigger create_goods_receipt():
     - Inserts goods_receipt (stores subtotal & tax from purchase_account_payable)
     - Inserts goods_receipt_item rows (quantity_received from purchase_order_item)
     - Calls execute_three_way_matching() only after items exist

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

## Implementation notes / best practices

- Insert goods_receipt and items within the same transaction, then call matching to guarantee item visibility.
- Use a small tolerance (0.01) for numeric comparisons.
- Keep three_way_matching insertion idempotent (skip if exists).
- Log notices in tests to show per-item details when debugging mismatches.

## Quick example sequence

1. SELECT create_purchase_order(...) → order, items, invoice, payable
2. INSERT payments → CALL verify_purchase_order_payment(...) until paid
3. UPDATE purchase_order SET purchase_order_status_id = 3
4. create_goods_receipt() runs, inserts items, then calls execute_three_way_matching()
5. SELECT \* FROM three_way_matching → expect amounts_matched = true, quantities_matched = true, is_matched = true

## REFERENCES

- Schema: purchase (purchase_order, supplier_invoice, goods_receipt, three_way_matching)
- Functions: purchase.\* (see repository functions folder)
