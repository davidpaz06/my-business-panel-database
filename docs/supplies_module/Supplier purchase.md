# Supplier Purchase

## Purpose

Describe the end-to-end process for creating and processing a supplier purchase in the Supplies module, including automatic behaviors, triggers/functions, validation queries and troubleshooting notes.

## Scope

Covers:

- Creating a supply order with line items
- Automatic supplier invoice and account payable creation
- Recording and verifying payments
- Order status transitions (Pending → Shipped → Delivered)
- Goods receipt creation (subtotal, tax, total and items)
- Three-way matching (order, invoice, goods receipt) and validation

## Prerequisites

- Schemas: `supplies_module`, `core`, `inventory_module`
- Core data: tenant, branch, products, payment methods, tax rates
- Installed functions/triggers:
  - `supplies_module.create_supply_order(...)`
  - `supplies_module.calculate_supply_order_total(...)`
  - `supplies_module.verify_supply_order_payment(...)`
  - `supplies_module.create_goods_receipt()` (trigger on order status change)
  - `supplies_module.execute_three_way_matching(...)` (called after items are inserted)

## Key entities

- supply_order / supply_order_item
- supplier_invoice / supplier_invoice_item
- account_payable
- supply_order_payment
- goods_receipt / goods_receipt_item
- three_way_matching

## Expected automated behaviors

- create_supply_order():
  - inserts supply_order and supply_order_item rows
  - computes subtotal and tax, inserts account_payable
  - inserts supplier_invoice and supplier_invoice_item when invoice requested
- verify_supply_order_payment(payment_id):
  - marks payment verified and updates account_payable status/amounts
  - when fully paid, marks supplier_invoice.paid = true
- create_goods_receipt() (triggered when supply_order status → Delivered):
  - inserts goods_receipt row (subtotal, tax)
  - inserts goods_receipt_item rows copying order quantities
  - calls execute_three_way_matching(order_id, goods_receipt_id) after all items inserted
- execute_three_way_matching():
  - compares subtotals, tax amounts and totals (with tolerance)
  - compares summed quantities across order, invoice and receipt
  - inserts a single three_way_matching row and sets amounts_matched / quantities_matched / is_matched

## Step-by-step flow

1. Create supply order (application)

   - Provide supplier, warehouse, expected delivery date, items (product_id, quantity_ordered, unit_price)
   - Example:
     SELECT supplies_module.create_supply_order(... p_items := jsonb_build_array(...))
   - Result: order + items + account_payable + supplier_invoice + supplier_invoice_item

2. Validate created records

   - Check order, items, invoice and invoice items exist.

3. Make payments (partial or full)

   - Insert supply_order_payment rows (verified = false), then call:
     CALL supplies_module.verify_supply_order_payment(<payment_id>);
   - Account payable updates account_status (Pending / Partial Paid / Paid) and amounts.
   - When Paid, supplier_invoice.paid = true.

4. Update order status to Shipped (optional)

   - UPDATE supply_order set supply_order_status_id = 2

5. Update order status to Delivered → goods receipt created automatically

   - UPDATE supply_order set supply_order_status_id = 3
   - Trigger create_goods_receipt():
     - Inserts goods_receipt (stores subtotal & tax from account_payable)
     - Inserts goods_receipt_item rows (quantity_received from supply_order_item)
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
  SELECT _ FROM supplies_module.supplier_invoice WHERE supply_order_id = '<order-uuid>';
  SELECT _ FROM supplies_module.account_payable WHERE supply_order_id = '<order-uuid>';
```

- Check items detail:
````sql
  SELECT p.sku, soi.quantity_ordered FROM supplies_module.supply_order_item soi JOIN core.product p USING (product_id) WHERE soi.supply_order_id = '<order-uuid>' ORDER BY p.sku;
  SELECT p.sku, sii.quantity_billed FROM supplies_module.supplier_invoice_item sii JOIN core.product p USING (product_id) WHERE sii.supplier_invoice_id = '<invoice-uuid>' ORDER BY p.sku;
  SELECT p.sku, gri.quantity_received FROM supplies_module.goods_receipt_item gri JOIN core.product p USING (product_id) WHERE gri.goods_receipt_id = '<goods-receipt-uuid>' ORDER BY p.sku;
`````

- Check three-way matching:

  ```sql
  SELECT \* FROM supplies_module.three_way_matching WHERE supply_order_id = '<order-uuid>';
  ```

- Totals and quantities:

```sql
  SELECT coalesce(sum(quantity_ordered \* unit_price),0) AS order_subtotal, coalesce(sum(quantity_ordered),0) AS order_qty FROM supplies_module.supply_order_item WHERE supply_order_id = '<order-uuid>';
  SELECT subtotal_amount, tax_amount, total_amount FROM supplies_module.supplier_invoice WHERE supply_order_id = '<order-uuid>';
  SELECT subtotal_amount, tax_amount, total_amount FROM supplies_module.goods_receipt WHERE supply_order_id = '<order-uuid>';
  SELECT coalesce(sum(quantity_billed),0) AS invoice_qty FROM supplies_module.supplier_invoice_item WHERE supplier_invoice_id = '<invoice-uuid>';
  SELECT coalesce(sum(quantity_received),0) AS receipt_qty FROM supplies_module.goods_receipt_item WHERE goods_receipt_id = '<goods-receipt-uuid>';
```

## Common failure modes & troubleshooting

- quantities_matched = false despite matching sums:
  - ensure execute_three_way_matching() runs after all goods_receipt_item rows are inserted (call matching at end of goods_receipt creation function).
  - check for duplicate/missing matching rows (function should be idempotent and return early if matching exists).
  - inspect per-product SKU detail to detect mis-matched product_id or tenant_id mismatches.
- amounts_matched false:
  - verify comparison uses subtotals (without tax) and tax amounts separately; check rounding tolerance.
  - ensure goods_receipt stores correct subtotal and tax (copied from account_payable or computed consistently).

## Implementation notes / best practices

- Insert goods_receipt and items within the same transaction, then call matching to guarantee item visibility.
- Use a small tolerance (0.01) for numeric comparisons.
- Keep three_way_matching insertion idempotent (skip if exists).
- Log notices in tests to show per-item details when debugging mismatches.

## Quick example sequence

1. SELECT create_supply_order(...) → order, items, invoice, payable
2. INSERT payments → CALL verify_supply_order_payment(...) until paid
3. UPDATE supply_order SET supply_order_status_id = 3
4. create_goods_receipt() runs, inserts items, then calls execute_three_way_matching()
5. SELECT \* FROM three_way_matching → expect amounts_matched = true, quantities_matched = true, is_matched = true

## References

- Schema: supplies_module (supply_order, supplier_invoice, goods_receipt, three_way_matching)
- Functions: supplies_module.\* (see repository functions folder)
