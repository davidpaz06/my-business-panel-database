# Supply Order Complete Workflow Test

## Purpose

Document the end-to-end workflow for the complete supply order lifecycle, from creation through payment verification, status transitions, goods receipt, and three-way matching validation. This document describes the comprehensive test flow demonstrated in `testSupplyPurchase.sql`.

## Scope

Covers the complete supply order workflow including:

- Initial data cleanup (idempotent test setup)
- Master data preparation (tenant, branch, warehouse, supplier, products)
- Supply order creation with automatic invoice generation
- Multi-phase payment processing (40%, 30%, 30% split)
- Automatic account payable status updates
- Order status transitions (Pending → Shipped → Delivered)
- Automatic goods receipt generation on delivery
- Three-way matching reconciliation (order, invoice, receipt)
- Complete workflow validation and verification

## Prerequisites

### Schemas Required

- `supplies_module` - Supply chain management
- `core` - Core entities (tenant, branch, products, payment methods, tax rates)
- `inventory_module` - Warehouse management

### Core Data Requirements

- Tax rates configured (13% for Costa Rica in this example)
- Payment methods configured:
  - Payment method ID 1: Cash
  - Payment method ID 2: Debit Card
  - Payment method ID 3: Credit Card

### Installed Functions and Triggers

- `supplies_module.create_supply_order(...)` - Creates order, items, invoice, and account payable
- `supplies_module.calculate_supply_order_total(...)` - Calculates order totals
- `supplies_module.verify_supply_order_payment(...)` - Verifies and processes payments
- `supplies_module.check_account_payable_completion(...)` - Checks payment completion status
- `supplies_module.recalc_account_payable_on_payment()` - Trigger to update account payable on payment verification
- `supplies_module.update_invoice_paid_status()` - Trigger to mark invoice as paid when fully paid
- `supplies_module.create_goods_receipt()` - Trigger to auto-create goods receipt on delivery status
- `supplies_module.execute_three_way_matching(...)` - Reconciles order, invoice, and receipt
- `supplies_module.update_order_status()` - Trigger to track order status changes

## Key Entities

### Supply Order Entities

- `supply_order` - Main order header
- `supply_order_item` - Order line items with products and quantities
- `supply_order_status` - Status catalog (Pending, Shipped, Delivered, Cancelled)
- `supply_order_tracking` - Audit trail for status changes

### Financial Entities

- `supplier_invoice` - Invoice generated from supply order
- `supplier_invoice_item` - Invoice line items
- `supplies_account_payable` - Account payable tracking with tax amounts
- `supply_order_payment` - Individual payment records

### Receipt and Matching Entities

- `goods_receipt` - Receipt of goods with totals
- `goods_receipt_item` - Received items detail
- `three_way_matching` - Reconciliation between order, invoice, and receipt

## Workflow Steps

### Section 0: Initial Cleanup (Idempotent)

**Purpose**: Ensure test can be run multiple times by cleaning up previous test data.

**Cleanup Order** (respects foreign key constraints):

1. `three_way_matching` records
2. `supply_order_payment` records
3. `goods_receipt_item` records
4. `goods_receipt` records
5. `supplier_invoice_item` records
6. `supplier_invoice` records
7. `supply_order_tracking` records
8. `supplies_account_payable` records
9. `supply_order_item` records
10. `supply_order` records
11. `supplier_branch` records
12. `supplier` records
13. Warehouse, products, branch, and tenant

**Filter**: All deletions filter by supplier name 'Full Flow Supplier'

**Expected Result**: Clean database ready for fresh test execution

---

### Section 1: Master Data Preparation

**Purpose**: Create all prerequisite data needed for the supply order workflow.

**Steps**:

1. **Create Tenant**

   ```sql
   INSERT INTO core.tenant (tenant_name, region_id, contact_email, is_subscribed)
   VALUES ('Full Flow Test Shop', 1, 'fullflow@test.local', true)
   ```

   - Name: 'Full Flow Test Shop'
   - Region ID: 1 (Costa Rica - for 13% tax)
   - Returns: `tenant_id`

2. **Create Branch**

   ```sql
   INSERT INTO core.branch (tenant_id, branch_name, branch_address, is_main_branch)
   VALUES (v_tenant_id, 'Full Flow Branch', 'Calle Full Flow 123', true)
   ```

   - Main branch flag: `true`
   - Returns: `branch_id`

3. **Create Warehouse**

   ```sql
   INSERT INTO inventory_module.warehouse (warehouse_name, branch_id, warehouse_address)
   VALUES ('Full Flow Warehouse', v_branch_id, 'Bodega Full Flow')
   ```

   - Checks if `inventory_module` schema exists, creates if needed
   - Checks if `warehouse` table exists, creates if needed
   - Returns: `warehouse_id`

4. **Create Supplier**

   ```sql
   INSERT INTO supplies_module.supplier (supplier_name, supplier_contact_info, supplier_address)
   VALUES ('Full Flow Supplier', 'contact@fullflow.local', 'Proveedor Full Flow')
   ```

   - Unique constraint on supplier_name
   - Returns: `supplier_id`

5. **Link Supplier to Branch**

   ```sql
   INSERT INTO supplies_module.supplier_branch (supplier_id, branch_id)
   VALUES (v_supplier_id, v_branch_id)
   ```

6. **Create Products**

   ```sql
   INSERT INTO core.product (tenant_id, sku, product_name, unit_price)
   VALUES
     (v_tenant_id, 'FF-001', 'Producto Flow A', 500.00),
     (v_tenant_id, 'FF-002', 'Producto Flow B', 300.00),
     (v_tenant_id, 'FF-003', 'Producto Flow C', 200.00)
   ```

   - Creates 3 test products with different unit prices
   - Returns: `product_id` for each

**Expected Result**: All master data created successfully with valid UUIDs returned.

---

### Section 2: Create Supply Order with Invoice

**Purpose**: Create a complete supply order that automatically generates invoice, invoice items, and account payable.

**Input Data**:

- Supplier: 'Full Flow Supplier'
- Warehouse: 'Full Flow Warehouse'
- Expected delivery: Current date + 10 days
- Items:
  - FF-001: 2 units × $500.00 = $1,000.00
  - FF-002: 3 units × $300.00 = $900.00
  - FF-003: 5 units × $200.00 = $1,000.00
- **Subtotal**: $2,900.00
- Payment condition: 'CREDIT'
- Invoice requested: `true`

**Process**:

```sql
v_supply_order_id := supplies_module.create_supply_order(
    v_supplier_id,
    v_warehouse_id,
    (current_date + interval '10 days')::date,
    v_items_jsonb,
    true,  -- create_invoice
    'CREDIT'
);
```

**Automatic Behaviors**:

1. **Supply Order Created**

   - Status: Pending (status_id = 1)
   - Returns: `supply_order_id`

2. **Supply Order Items Created**

   - 3 items inserted with quantities and prices
   - Linked to tenant and products via composite FK

3. **Supplier Invoice Created**

   - Invoice number generated
   - Subtotal: $2,900.00
   - Tax (13%): $377.00
   - Total: $3,277.00
   - Paid flag: `false`
   - Payment condition: 'CREDIT'

4. **Supplier Invoice Items Created**

   - 3 items mirroring order quantities

5. **Account Payable Created**
   - Core account payable entry created
   - Supplies account payable extension created with:
     - Subtotal: $2,900.00
     - Tax amount: $377.00
     - Total: $3,277.00
     - Status: 1 (Pending)
     - Amount paid: $0.00
     - Due date calculated based on payment terms

**Validation Queries**:

```sql
-- Verify order
SELECT * FROM supplies_module.supply_order WHERE supply_order_id = '<uuid>';

-- Verify invoice
SELECT * FROM supplies_module.supplier_invoice WHERE supply_order_id = '<uuid>';

-- Verify account payable
SELECT ap.*, sap.*
FROM supplies_module.supplies_account_payable sap
JOIN core.account_payable ap ON sap.account_payable_id = ap.account_payable_id
WHERE sap.supply_order_id = '<uuid>';

-- Verify items match
SELECT COUNT(*) FROM supplies_module.supply_order_item WHERE supply_order_id = '<uuid>';
SELECT COUNT(*) FROM supplies_module.supplier_invoice_item WHERE supplier_invoice_id = '<uuid>';
```

**Expected Result**:

- Supply order: ✅ Created
- Invoice: ✅ Generated automatically
- Account payable: ✅ Created with calculated tax
- All items: ✅ Recorded in order and invoice

---

### Section 3: Initial Payment (40%)

**Purpose**: Record first partial payment covering 40% of total amount.

**Calculation**:

- Total due: $3,277.00
- Payment amount: $3,277.00 × 0.40 = $1,310.80

**Process**:

1. **Insert Payment Record**

   ```sql
   INSERT INTO supplies_module.supply_order_payment (
       tenant_id,
       supplies_account_payable_id,
       payment_date,
       amount_paid,
       payment_method_id,  -- 1 = Cash
       payment_reference,
       verified
   ) VALUES (
       v_tenant_id,
       v_supplies_account_payable_id,
       current_timestamp,
       1310.800,  -- 40%
       1,
       'PAY-40PCT-CASH',
       false  -- Not verified yet
   )
   RETURNING payment_id
   ```

2. **Verify Payment**

   ```sql
   CALL supplies_module.verify_supply_order_payment(v_payment_id);
   ```

**Automatic Behaviors on Verification**:

1. **Payment marked as verified**

   ```sql
   UPDATE supply_order_payment SET verified = true
   ```

2. **Trigger: `recalc_account_payable_on_payment()`**

   - Calls `check_account_payable_completion()`
   - Updates account payable:

     ```sql
     UPDATE supplies_module.supplies_account_payable
     SET account_payable_status = 2,  -- Partial Paid
         updated_at = current_timestamp

     ```

   - Updates core account payable:

     ```sql
     UPDATE core.account_payable
     SET amount_paid = 1310.800,
         is_paid = false
     ```

**Validation**:

```sql
SELECT
    sap.account_payable_status,
    aps.status_name,
    ap.amount_paid,
    (ap.subtotal + sap.tax_amount - ap.amount_paid) as balance_remaining
FROM supplies_module.supplies_account_payable sap
JOIN core.account_payable ap ON sap.account_payable_id = ap.account_payable_id
JOIN core.account_payable_status aps ON sap.account_payable_status = aps.status_id
```

**Expected Result**:

- Payment: ✅ Verified
- Account payable status: 2 (Partial Paid)
- Amount paid: $1,310.80
- Balance remaining: $1,966.20
- Invoice paid flag: `false` (not fully paid yet)

---

### Section 4: Change Status to Shipped

**Purpose**: Update order status to reflect shipment, demonstrating status transition tracking.

**Process**:

```sql
UPDATE supplies_module.supply_order
SET supply_order_status_id = 2  -- Shipped
WHERE supply_order_id = v_supply_order_id
```

**Automatic Behaviors**:

1. **Trigger: `update_order_status()`**

   - Inserts tracking record:

   ```sql
   INSERT INTO supplies_module.supply_order_tracking (
       supply_order_id,
       previous_status_id,  -- 1 (Pending)
       new_status_id,       -- 2 (Shipped)
       notes,
       changed_at
   )
   ```

**Validation**:

```sql
SELECT
    so.supply_order_status_id,
    sos.status_name,
    sot.previous_status_id,
    sot.new_status_id,
    sot.changed_at
FROM supplies_module.supply_order so
JOIN supplies_module.supply_order_status sos ON so.supply_order_status_id = sos.status_id
LEFT JOIN supplies_module.supply_order_tracking sot ON so.supply_order_id = sot.supply_order_id
WHERE so.supply_order_id = v_supply_order_id
```

**Expected Result**:

- Order status: 2 (Shipped)
- Tracking record: ✅ Created
- Previous status: 1 (Pending)
- New status: 2 (Shipped)

---

### Section 5: Second Payment (30%)

**Purpose**: Record second partial payment covering 30% of total amount.

**Calculation**:

- Total due: $3,277.00
- Payment amount: $3,277.00 × 0.30 = $983.10

**Process**:

1. **Insert Payment Record**

   ```sql
   INSERT INTO supplies_module.supply_order_payment (
       tenant_id,
       supplies_account_payable_id,
       payment_date,
       amount_paid,
       payment_method_id,  -- 2 = Debit Card
       payment_reference,
       verified
   ) VALUES (
       v_tenant_id,
       v_supplies_account_payable_id,
       current_timestamp,
       983.100,  -- 30%
       2,
       'PAY-30PCT-DEBIT',
       false
   )
   RETURNING payment_id
   ```

2. **Verify Payment**

   ```sql
   CALL supplies_module.verify_supply_order_payment(v_payment_id);
   ```

**Automatic Behaviors**:

- Payment verified
- Account payable updated:
  - Status remains: 2 (Partial Paid)
  - Amount paid: $1,310.80 + $983.10 = $2,293.90
  - Balance: $3,277.00 - $2,293.90 = $983.10

**Expected Result**:

- Cumulative paid: $2,293.90
- Remaining: $983.10
- Status: Still 2 (Partial Paid)
- Invoice paid: Still `false`

---

### Section 6: Final Payment (30% - Remaining Balance)

**Purpose**: Complete payment of remaining balance, triggering full payment status updates.

**Calculation**:

- Remaining balance: $983.10
- Final payment: $983.10 (exactly the remaining amount)

**Process**:

1. **Calculate Exact Remaining Balance**

   ```sql
   v_remaining := round(v_total_amount - coalesce(v_paid_so_far, 0), 3);
   v_pay := v_remaining;  -- Pay exactly what's left
   ```

2. **Insert Payment Record**

   ```sql
   INSERT INTO supplies_module.supply_order_payment (
       tenant_id,
       supplies_account_payable_id,
       payment_date,
       amount_paid,
       payment_method_id,  -- 3 = Credit Card
       payment_reference,
       verified
   ) VALUES (
       v_tenant_id,
       v_supplies_account_payable_id,
       current_timestamp,
       983.100,  -- Final 30%
       3,
       'PAY-FINAL-CREDIT',
       false
   )
   RETURNING payment_id
   ```

3. **Verify Payment**

   ```sql
   CALL supplies_module.verify_supply_order_payment(v_payment_id);
   ```

**Automatic Behaviors - Critical Payment Completion Flow**:

1. **Payment marked verified**

2. **Trigger: `recalc_account_payable_on_payment()`**

   - Calculates total paid: $3,277.00
   - Detects full payment condition
   - Calls `check_account_payable_completion()`

3. **Function: `check_account_payable_completion()`**

   - Validates: `amount_paid >= (subtotal + tax)`
   - Updates supplies account payable:

   ```sql
   UPDATE supplies_module.supplies_account_payable
   SET account_payable_status = 3,  -- Paid
       updated_at = current_timestamp
   WHERE account_payable_id = _account_payable_id
   ```

   - Updates core account payable:

   ```sql
   UPDATE core.account_payable
   SET amount_paid = 3277.000,
       is_paid = true
   WHERE account_payable_id = _account_payable_id
   ```

4. **Trigger: `update_invoice_paid_status()`**

   - Fired when account_payable_status changes to 3
   - Updates supplier invoice:

   ```sql
   UPDATE supplies_module.supplier_invoice
   SET paid = true
   WHERE supply_order_id = (
       SELECT supply_order_id
       FROM supplies_account_payable
       WHERE account_payable_id = new.account_payable_id
   )
   ```

5. **Trigger: `auto_resolve_payment_alerts()`** (if alerts exist)
   - Resolves any pending payment alerts
   - Marks alerts as resolved for this account payable

**Validation - Critical Checks**:

```sql
-- Check account payable status
SELECT
    sap.account_payable_status,  -- Should be 3 (Paid)
    aps.status_name,             -- Should be 'Paid'
    ap.amount_paid,              -- Should be 3277.000
    ap.is_paid,                  -- Should be true
    (ap.subtotal + sap.tax_amount - ap.amount_paid) as balance  -- Should be 0
FROM supplies_module.supplies_account_payable sap
JOIN core.account_payable ap ON sap.account_payable_id = ap.account_payable_id
JOIN core.account_payable_status aps ON sap.account_payable_status = aps.status_id

-- Check invoice paid status
SELECT paid  -- Should be true
FROM supplies_module.supplier_invoice
WHERE supply_order_id = v_supply_order_id
```

**Expected Result**:

- Account payable status: 3 (Paid) ✅
- Amount paid: $3,277.00 ✅
- Balance: $0.00 ✅
- `is_paid` flag (core): `true` ✅
- Invoice `paid` flag: `true` ✅
- Payment count: 3 verified payments ✅

**Error Conditions**:

- If status ≠ 3: Raise exception "Account payable should be Paid"
- If `is_paid` ≠ true: Raise exception "Should be marked as paid in core.account_payable"
- If invoice `paid` ≠ true: Raise exception "Invoice should be marked as paid"

---

### Section 7: Change Status to Delivered - Auto Goods Receipt

**Purpose**: Update order status to Delivered, triggering automatic goods receipt creation.

**Process**:

```sql
UPDATE supplies_module.supply_order
SET supply_order_status_id = 3  -- Delivered
WHERE supply_order_id = v_supply_order_id
```

**Automatic Behaviors - Goods Receipt Creation Flow**:

1. **Trigger: `create_goods_receipt()`**

   - Fires when supply_order_status_id changes to 3 (Delivered)
   - Condition: `new.supply_order_status_id = 3 AND old.supply_order_status_id IS DISTINCT FROM 3`

2. **Goods Receipt Creation**:

   ```sql
   INSERT INTO supplies_module.goods_receipt (
       supply_order_id,
       receipt_date,
       subtotal_amount,  -- Copied from supplies_account_payable
       tax_amount,       -- Copied from supplies_account_payable
       total_amount,     -- Calculated: subtotal + tax
       notes
   )
   RETURNING goods_receipt_id
   ```

   - Retrieves subtotal and tax from `supplies_account_payable`
   - Calculates total amount

3. **Goods Receipt Items Creation**:

   ```sql
   INSERT INTO supplies_module.goods_receipt_item (
       goods_receipt_id,
       tenant_id,
       product_id,
       quantity_received,  -- Copied from supply_order_item.quantity_ordered
       unit_price,         -- Copied from supply_order_item.unit_price
       notes
   )
   SELECT
       v_goods_receipt_id,
       tenant_id,
       product_id,
       quantity_ordered as quantity_received,
       unit_price,
       'Auto-generated from supply order'
   FROM supplies_module.supply_order_item
   WHERE supply_order_id = new.supply_order_id
   ```

   - Creates one goods_receipt_item per supply_order_item
   - Copies quantities directly (assuming full delivery)

4. **Three-Way Matching Invocation**:

   ```sql
   PERFORM supplies_module.execute_three_way_matching(
       new.supply_order_id,
       v_goods_receipt_id
   );
   ```

   - Called **after** all goods_receipt_items are inserted
   - Ensures items exist for quantity comparison

**Validation**:

```sql
-- Verify goods receipt created
SELECT * FROM supplies_module.goods_receipt
WHERE supply_order_id = v_supply_order_id;

-- Verify items count matches
SELECT COUNT(*) FROM supplies_module.goods_receipt_item
WHERE goods_receipt_id = v_goods_receipt_id;

SELECT COUNT(*) FROM supplies_module.supply_order_item
WHERE supply_order_id = v_supply_order_id;

-- Verify amounts
SELECT
    gr.subtotal_amount,
    gr.tax_amount,
    gr.total_amount,
    (SELECT subtotal FROM core.account_payable ap
     JOIN supplies_module.supplies_account_payable sap
         ON ap.account_payable_id = sap.account_payable_id
     WHERE sap.supply_order_id = gr.supply_order_id) as ap_subtotal,
    (SELECT tax_amount FROM supplies_module.supplies_account_payable
     WHERE supply_order_id = gr.supply_order_id) as ap_tax
FROM supplies_module.goods_receipt gr
WHERE supply_order_id = v_supply_order_id
```

**Expected Result**:

- Order status: 3 (Delivered) ✅
- Goods receipt: ✅ Created automatically
- Goods receipt items: 3 items (matching order items) ✅
- Subtotal matches account payable: $2,900.00 ✅
- Tax matches account payable: $377.00 ✅
- Total: $3,277.00 ✅
- Three-way matching: ✅ Executed (see Section 8)

---

### Section 8: Three-Way Matching Verification

**Purpose**: Verify that automatic three-way matching reconciliation was successful.

**What is Three-Way Matching?**

A control process that compares three documents to ensure consistency:

1. **Supply Order** - What was ordered
2. **Supplier Invoice** - What the supplier billed
3. **Goods Receipt** - What was actually received

**Comparison Criteria**:

1. **Amount Matching**:

   - Order subtotal (sum of item quantities × unit prices)
   - Invoice subtotal
   - Receipt subtotal
   - Tolerance: ±0.01 (accounting for rounding)

2. **Quantity Matching**:
   - Order total quantity (sum of quantities_ordered)
   - Invoice total quantity (sum of quantities_billed)
   - Receipt total quantity (sum of quantities_received)
   - Must match exactly

**Process Flow**:

The matching is executed automatically at the end of `create_goods_receipt()` trigger:

```sql
PERFORM supplies_module.execute_three_way_matching(
    p_supply_order_id := new.supply_order_id,
    p_goods_receipt_id := v_goods_receipt_id
);
```

**Matching Algorithm**:

1. **Retrieve IDs**:

   ```sql
   SELECT supplier_invoice_id INTO v_supplier_invoice_id
   FROM supplies_module.supplier_invoice
   WHERE supply_order_id = p_supply_order_id
   ```

2. **Calculate Subtotals**:

   ```sql
   -- Order subtotal
   SELECT COALESCE(SUM(quantity_ordered * unit_price), 0)
   FROM supply_order_item

   -- Invoice subtotal
   SELECT subtotal_amount
   FROM supplier_invoice

   -- Receipt subtotal
   SELECT subtotal_amount
   FROM goods_receipt
   ```

3. **Calculate Total Quantities**:

   ```sql
   -- Order quantity
   SELECT COALESCE(SUM(quantity_ordered), 0)
   FROM supply_order_item

   -- Invoice quantity
   SELECT COALESCE(SUM(quantity_billed), 0)
   FROM supplier_invoice_item

   -- Receipt quantity
   SELECT COALESCE(SUM(quantity_received), 0)
   FROM goods_receipt_item
   ```

4. **Compare with Tolerance**:

   ```sql
   v_amounts_matched := (
       ABS(v_order_subtotal - v_invoice_subtotal) <= 0.01 AND
       ABS(v_invoice_subtotal - v_receipt_subtotal) <= 0.01 AND
       ABS(v_order_subtotal - v_receipt_subtotal) <= 0.01
   );

   v_quantities_matched := (
       v_order_quantity = v_invoice_quantity AND
       v_invoice_quantity = v_receipt_quantity
   );

   v_is_matched := (v_amounts_matched AND v_quantities_matched);
   ```

5. **Insert Matching Record**:

   ```sql
   INSERT INTO supplies_module.three_way_matching (
       supply_order_id,
       goods_receipt_id,
       supplier_invoice_id,
       order_subtotal,
       invoice_subtotal,
       receipt_subtotal,
       order_quantity,
       invoice_quantity,
       receipt_quantity,
       amounts_matched,
       quantities_matched,
       is_matched,
       matched_at,
       tolerance_used
   ) VALUES (
       p_supply_order_id,
       p_goods_receipt_id,
       v_supplier_invoice_id,
       v_order_subtotal,
       v_invoice_subtotal,
       v_receipt_subtotal,
       v_order_quantity,
       v_invoice_quantity,
       v_receipt_quantity,
       v_amounts_matched,
       v_quantities_matched,
       v_is_matched,
       CURRENT_TIMESTAMP,
       0.01
   )
   ```

**Validation Queries**:

```sql
-- Check matching result
SELECT
    matching_id,
    amounts_matched,
    quantities_matched,
    is_matched,
    matched_at
FROM supplies_module.three_way_matching
WHERE supply_order_id = v_supply_order_id;

-- Compare subtotals
SELECT
    'Order' as source,
    COALESCE(SUM(quantity_ordered * unit_price), 0) as subtotal
FROM supplies_module.supply_order_item
WHERE supply_order_id = v_supply_order_id

UNION ALL

SELECT
    'Invoice' as source,
    subtotal_amount
FROM supplies_module.supplier_invoice
WHERE supply_order_id = v_supply_order_id

UNION ALL

SELECT
    'Receipt' as source,
    subtotal_amount
FROM supplies_module.goods_receipt
WHERE supply_order_id = v_supply_order_id;

-- Compare quantities
SELECT
    'Order' as source,
    COALESCE(SUM(quantity_ordered), 0) as total_quantity
FROM supplies_module.supply_order_item
WHERE supply_order_id = v_supply_order_id

UNION ALL

SELECT
    'Invoice' as source,
    COALESCE(SUM(quantity_billed), 0)
FROM supplies_module.supplier_invoice_item
WHERE supplier_invoice_id = v_supplier_invoice_id

UNION ALL

SELECT
    'Receipt' as source,
    COALESCE(SUM(quantity_received), 0)
FROM supplies_module.goods_receipt_item
WHERE goods_receipt_id = v_goods_receipt_id;

-- Per-product detail comparison
SELECT
    p.sku,
    soi.quantity_ordered as order_qty,
    sii.quantity_billed as invoice_qty,
    gri.quantity_received as receipt_qty
FROM supplies_module.supply_order_item soi
JOIN supplies_module.supplier_invoice_item sii ON soi.product_id = sii.product_id
JOIN supplies_module.goods_receipt_item gri ON soi.product_id = gri.product_id
JOIN core.product p ON soi.product_id = p.product_id
WHERE soi.supply_order_id = v_supply_order_id
  AND sii.supplier_invoice_id = v_supplier_invoice_id
  AND gri.goods_receipt_id = v_goods_receipt_id
ORDER BY p.sku;
```

**Expected Results - Successful Matching**:

| Comparison         | Expected Value |
| ------------------ | -------------- |
| Order Subtotal     | $2,900.00      |
| Invoice Subtotal   | $2,900.00      |
| Receipt Subtotal   | $2,900.00      |
| Amounts Matched    | `true` ✅      |
| Order Quantity     | 10 units       |
| Invoice Quantity   | 10 units       |
| Receipt Quantity   | 10 units       |
| Quantities Matched | `true` ✅      |
| **Overall Match**  | `true` ✅      |

**Per-Product Breakdown**:

| SKU    | Order Qty | Invoice Qty | Receipt Qty | Match |
| ------ | --------- | ----------- | ----------- | ----- |
| FF-001 | 2         | 2           | 2           | ✅    |
| FF-002 | 3         | 3           | 3           | ✅    |
| FF-003 | 5         | 5           | 5           | ✅    |

**Failure Scenarios**:

1. **Amounts Don't Match**:

   - `amounts_matched = false`
   - Check for:
     - Incorrect unit prices in invoice
     - Calculation errors
     - Rounding issues beyond tolerance

2. **Quantities Don't Match**:

   - `quantities_matched = false`
   - Check for:
     - Missing items in invoice or receipt
     - Partial deliveries
     - Data entry errors
     - Wrong product_id mappings

3. **Items Missing**:
   - If matching was not called, check that:
     - `create_goods_receipt()` trigger executed
     - Goods receipt items were inserted before matching call
     - No exceptions occurred during receipt creation

**Troubleshooting**:

- Always inspect per-product SKU detail to identify specific mismatches
- Verify tenant_id consistency across all items
- Check that matching is called after all items are inserted
- Ensure rounding is applied consistently (3 decimal places)

---

### Section 9: Final Workflow Summary

**Purpose**: Provide comprehensive validation of entire workflow completion.

**Summary Report Includes**:

1. **Supply Order**:

   - Order ID
   - Current status (should be: Delivered)

2. **Account Payable**:

   - Subtotal amount
   - Tax amount
   - Total amount
   - Amount paid (should equal total)
   - Balance (should be 0)
   - Status (should be: Paid)
   - Core `is_paid` flag (should be: true)
   - Number of verified payments (should be: 3)

3. **Supplier Invoice**:

   - Total amount (with tax)
   - Paid flag (should be: true)

4. **Goods Receipt**:

   - Exists (should be: true)
   - Total received amount
   - Number of items received

5. **Three-Way Matching**:
   - Exists (should be: true)
   - Match result (should be: true - SUCCESS)

**Final Validation Query**:

```sql
SELECT
    so.supply_order_id,
    sos.status_name as order_status,
    aps.status_name as account_status,
    ap.is_paid,
    si.paid as invoice_paid,
    ap.subtotal,
    sap.tax_amount,
    ap.amount_paid,
    (ap.subtotal + sap.tax_amount - ap.amount_paid) as balance,
    si.total_amount as invoice_total,
    gr.total_amount as receipt_total,
    (SELECT COUNT(*) FROM supply_order_payment sop
     WHERE sop.supplies_account_payable_id = sap.supplies_account_payable_id
       AND sop.verified = true) as verified_payments,
    (SELECT is_matched FROM three_way_matching
     WHERE supply_order_id = so.supply_order_id) as matching_result
FROM supplies_module.supply_order so
JOIN supplies_module.supply_order_status sos ON so.supply_order_status_id = sos.status_id
JOIN supplies_module.supplies_account_payable sap ON so.supply_order_id = sap.supply_order_id
JOIN core.account_payable ap ON sap.account_payable_id = ap.account_payable_id
JOIN core.account_payable_status aps ON sap.account_payable_status = aps.status_id
JOIN supplies_module.supplier_invoice si ON so.supply_order_id = si.supply_order_id
JOIN supplies_module.goods_receipt gr ON so.supply_order_id = gr.supply_order_id
WHERE so.supply_order_id = v_supply_order_id
```

**Expected Complete Workflow State**:

```sql
┌─────────────────────────────────────────────────────┐
│           COMPLETE WORKFLOW STATUS                  │
└─────────────────────────────────────────────────────┘

📦 SUPPLY ORDER:
   Status: Delivered ✅

💰 ACCOUNT PAYABLE:
   Subtotal: $2,900.00
   Tax (13%): $377.00
   Total: $3,277.00
   Paid: $3,277.00 ✅
   Balance: $0.00 ✅
   Status: Paid ✅
   Is Paid (core): true ✅
   Verified Payments: 3 ✅

🧾 SUPPLIER INVOICE:
   Total (with tax): $3,277.00
   Paid: true ✅

📦 GOODS RECEIPT:
   Exists: true ✅
   Total Received: $3,277.00
   Items: 3 ✅

🔍 THREE-WAY MATCHING:
   Exists: true ✅
   Result: SUCCESS ✅
   Amounts Matched: true ✅
   Quantities Matched: true ✅
```

---

## Complete Workflow Diagram

```sql
┌──────────────────────────────────────────────────────────────┐
│                    SUPPLY ORDER LIFECYCLE                    │
└──────────────────────────────────────────────────────────────┘

1. CREATION
   ├─► create_supply_order()
   ├─► supply_order (status: Pending)
   ├─► supply_order_item (3 items)
   ├─► supplier_invoice (auto-generated)
   ├─► supplier_invoice_item (auto-generated)
   └─► supplies_account_payable (status: Pending)

2. PAYMENT PHASE 1 (40%)
   ├─► Insert payment record (verified: false)
   ├─► verify_supply_order_payment()
   ├─► TRIGGER: recalc_account_payable_on_payment()
   └─► Account status → Partial Paid

3. STATUS UPDATE: SHIPPED
   ├─► Update status to Shipped
   └─► TRIGGER: update_order_status() → tracking record

4. PAYMENT PHASE 2 (30%)
   ├─► Insert payment record
   ├─► verify_supply_order_payment()
   └─► Account status → Still Partial Paid

5. PAYMENT PHASE 3 (30% - Final)
   ├─► Insert payment record
   ├─► verify_supply_order_payment()
   ├─► TRIGGER: recalc_account_payable_on_payment()
   ├─► FUNCTION: check_account_payable_completion()
   ├─► Account status → Paid
   ├─► Core is_paid → true
   ├─► TRIGGER: update_invoice_paid_status()
   └─► Invoice paid → true

6. STATUS UPDATE: DELIVERED
   ├─► Update status to Delivered
   ├─► TRIGGER: create_goods_receipt()
   ├─► goods_receipt (auto-generated)
   ├─► goods_receipt_item (auto-generated, 3 items)
   └─► FUNCTION: execute_three_way_matching()
       ├─► Compare subtotals (±0.01 tolerance)
       ├─► Compare quantities (exact match)
       └─► three_way_matching record (is_matched: true)

7. VERIFICATION
   └─► Complete workflow validated ✅
```

---

## Key Success Criteria

✅ **Order Creation**

- Supply order created with status Pending
- All items recorded correctly
- Invoice generated automatically
- Account payable created with tax calculated

✅ **Payment Processing**

- Multiple partial payments accepted
- Status transitions: Pending → Partial Paid → Paid
- Core account payable synchronized
- Invoice marked as paid when complete

✅ **Status Transitions**

- Status change tracking working
- Delivered status triggers goods receipt

✅ **Goods Receipt**

- Auto-generated on delivery
- All items copied from order
- Amounts match account payable

✅ **Three-Way Matching**

- Executed automatically after receipt
- Amounts match within tolerance
- Quantities match exactly
- Overall match result: true

---

## Common Issues and Solutions

### Issue 1: Quantities Don't Match

**Symptom**: `quantities_matched = false`

**Troubleshooting**:

```sql
-- Check per-product quantities
SELECT
    p.sku,
    soi.quantity_ordered,
    sii.quantity_billed,
    gri.quantity_received
FROM supply_order_item soi
JOIN supplier_invoice_item sii USING (product_id)
JOIN goods_receipt_item gri USING (product_id)
JOIN product p USING (product_id)
WHERE soi.supply_order_id = '<uuid>';
```

**Common Causes**:

- Missing items in invoice or receipt
- Wrong product_id in items
- Partial delivery not reflected
- Data entry errors

### Issue 2: Three-Way Matching Not Created

**Symptom**: No record in `three_way_matching` table

**Troubleshooting**:

```sql
-- Check if goods receipt was created
SELECT * FROM goods_receipt WHERE supply_order_id = '<uuid>';

-- Check if items exist
SELECT COUNT(*) FROM goods_receipt_item WHERE goods_receipt_id = '<uuid>';
```

**Common Causes**:

- `create_goods_receipt()` trigger didn't fire
- Order status wasn't changed to Delivered
- Exception occurred during receipt creation
- Matching called before items were inserted

### Issue 3: Invoice Not Marked as Paid

**Symptom**: `supplier_invoice.paid = false` even though fully paid

**Troubleshooting**:

```sql
-- Check account payable status
SELECT account_payable_status
FROM supplies_account_payable
WHERE supply_order_id = '<uuid>';

-- Check if trigger exists
SELECT * FROM pg_trigger
WHERE tgname = 'update_invoice_paid_status_trigger';
```

**Common Causes**:

- Account payable status not updated to 3 (Paid)
- `update_invoice_paid_status()` trigger not installed
- Trigger disabled
- Exception during trigger execution

### Issue 4: Amounts Don't Match

**Symptom**: `amounts_matched = false`

**Troubleshooting**:

```sql
-- Compare subtotals
SELECT 'Order' as source,
       SUM(quantity_ordered * unit_price) as subtotal
FROM supply_order_item
WHERE supply_order_id = '<uuid>'

UNION ALL

SELECT 'Invoice', subtotal_amount
FROM supplier_invoice
WHERE supply_order_id = '<uuid>'

UNION ALL

SELECT 'Receipt', subtotal_amount
FROM goods_receipt
WHERE supply_order_id = '<uuid>';
```

**Common Causes**:

- Price discrepancies between order and invoice
- Goods receipt copied wrong amounts
- Rounding errors beyond tolerance
- Tax included in subtotal incorrectly

---

## Performance Considerations

- **Batch Operations**: Order creation with multiple items uses JSONB for efficiency
- **Trigger Efficiency**: Triggers only fire on specific status changes
- **Indexing**: Ensure foreign keys are indexed for fast lookups
- **Transaction Scope**: All operations within sections are atomic

---

## References

### Related Documentation

- [Supplier Purchase.md](Supplier%20purchase.md) - Detailed supplier purchase process
- Schema: `supplies_module` - All supply chain tables
- Schema: `core` - Core entities and payment tracking
- Schema: `inventory_module` - Warehouse management

### Database Objects

- Functions: `supplies_functions.sql`
- Schemas: `supplies_schema.sql`, `core_schema.sql`
- Test: `testSupplyPurchase.sql`

### Key Functions

- `create_supply_order()` - Main order creation
- `verify_supply_order_payment()` - Payment processing
- `check_account_payable_completion()` - Payment completion check
- `execute_three_way_matching()` - Reconciliation logic
- `create_goods_receipt()` - Receipt generation trigger
