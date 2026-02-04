# Payment Alerts System

## Purpose

Describe the end-to-end process for managing payment alerts in the purchase module, including automatic alert generation, monitoring, and resolution behaviors. This system helps track upcoming, urgent, and overdue payments to ensure timely payment of supplier invoices.

## Scope

Covers:

- Configuring payment alert thresholds per tenant
- Creating purchase orders with varying due dates
- Automatic alert generation based on due date proximity
- Viewing and monitoring pending payment alerts
- Alert statistics and reporting
- Automatic alert resolution when payments are made
- Alert type categorization (Warning, Urgent, Overdue)

## Prerequisites

- Schemas: `purchase`, `general_schema`, `inventory_schema`
- general_schema data: tenant, branch, supplier, products, payment methods
- Installed functions/triggers:
  - `purchase.initialize_payment_alert_config(...)` - Sets up alert configuration per tenant
  - `purchase.generate_payment_alerts()` - Generates alerts based on due dates
  - `purchase.get_pending_payment_alerts(tenant_id)` - Retrieves active alerts
  - `purchase.get_payment_alert_stats(tenant_id)` - Provides alert statistics
  - `purchase.resolve_payment_alert(alert_id)` - Manually resolves an alert
  - `purchase.auto_resolve_payment_alerts()` - Trigger that auto-resolves alerts on payment completion

## Key Entities

### Alert Configuration

- `purchase_order_payment_alert_config` - Tenant-specific alert configuration (warning/urgent thresholds)

### Alert Management

- `purchase_order_payment_alert_type` - Alert type catalog (Upcoming, Urgent, Overdue, Reconciliation)
- `purchase_order_payment_alert` - Active payment alert records
- `purchase_account_payable` - Account payable with due dates
- `general_schema.account_payable` - general_schema account payable data

### Related Entities

- `purchase_order` - purchase orders linked to payables
- `supplier_invoice` - Invoices linked to orders
- `purchase_order_payment` - Payment records

## Expected Automated Behaviors

### Alert Configuration

- `initialize_payment_alert_config(tenant_id, warning_days, urgent_days, email_enabled, sms_enabled)`:
  - Creates tenant-specific alert configuration
  - Sets warning threshold (default: 7 days before due date)
  - Sets urgent threshold (default: 3 days before due date)
  - Enables/disables notification channels
  - Returns `config_id`

### Alert Generation

- `generate_payment_alerts()`:
  - Scans all unpaid accounts payable across all tenants
  - Calculates days until due date
  - Generates alerts based on thresholds:
    - **Overdue**: due_date < current_date (Alert type: Overdue Payment)
    - **Urgent**: due_date between current_date and (current_date + urgent_days) (Alert type: Urgent Payment)
    - **Warning**: due_date between (current_date + urgent_days) and (current_date + warning_days) (Alert type: Upcoming Due Date)
  - Prevents duplicate alerts (idempotent)
  - Skips already-paid accounts

### Alert Retrieval

- `get_pending_payment_alerts(tenant_id)`:
  - Returns table with columns:
    - `payment_alert_id`, `purchase_account_payable_id`, `purchase_order_id`
    - `supplier_name`, `invoice_number`
    - `alert_type`, `alert_type_description`
    - `due_date`, `days_until_due`
    - `balance_remaining`
    - `alert_date`, `created_at`
  - Filters by tenant and unresolved alerts only
  - Orders by due_date ascending (most urgent first)

### Alert Statistics

- `get_payment_alert_stats(tenant_id)`:
  - Returns aggregated statistics:
    - `total_alerts` - Total pending alerts
    - `overdue_count` - Count of overdue payments
    - `urgent_count` - Count of urgent payments
    - `warning_count` - Count of warning alerts
    - `total_amount_at_risk` - Sum of all balances with alerts

### Auto-Resolution

- `auto_resolve_payment_alerts()` (trigger on purchase_account_payable):
  - Fires when account_payable_status changes to 3 (Paid)
  - Automatically marks all related alerts as resolved
  - Sets `is_resolved = true` and updates `updated_at`
  - No manual intervention required

## Step-by-Step Flow

### 1. Initialize Alert Configuration (One-time per tenant)

**Action**: Set up alert thresholds for a tenant

```sql
SELECT purchase.initialize_payment_alert_config(
    p_tenant_id := '<tenant-uuid>',
    p_warning_days_before_due := 7,      -- Alert 7 days before due
    p_urgent_days_before_due := 3,        -- Alert 3 days before due
    p_email_notifications_enabled := true,
    p_sms_notifications_enabled := false
);
```

**Result**:

- Configuration record created in `purchase_order_payment_alert_config`
- Returns `payment_alert_config_id`
- Configuration is tenant-specific and unique per tenant

**Validation**:

```sql
SELECT * FROM purchase.purchase_order_payment_alert_config
WHERE tenant_id = '<tenant-uuid>';
```

---

### 2. Create purchase Orders with Due Dates

**Action**: Create orders that will trigger alerts at different times

**Example Scenarios**:

```sql
-- Scenario 1: Overdue payment (due 5 days ago)
SELECT purchase.create_purchase_order(
    p_supplier_id := '<supplier-uuid>',
    p_warehouse_id := '<warehouse-uuid>',
    p_expected_delivery_date := current_date,
    p_items := jsonb_build_array(
        jsonb_build_object('product_id', '<product-uuid>', 'quantity_ordered', 10, 'unit_price', 100.00)
    ),
    p_has_invoice := true,
    p_payment_condition := 'CREDIT'
);

-- Manually adjust due date to simulate overdue
UPDATE general_schema.account_payable
SET due_date = current_date - interval '5 days'
WHERE account_payable_id = (
    SELECT account_payable_id
    FROM purchase.purchase_account_payable
    WHERE purchase_order_id = '<order-uuid>'
);
```

**Alert Trigger Conditions**:

| Scenario | Due Date   | Days Until Due | Alert Type        | Generated? |
| -------- | ---------- | -------------- | ----------------- | ---------- |
| Overdue  | 5 days ago | -5             | Overdue Payment   | ✅ Yes     |
| Urgent   | In 2 days  | 2              | Urgent Payment    | ✅ Yes     |
| Warning  | In 5 days  | 5              | Upcoming Due Date | ✅ Yes     |
| OK       | In 15 days | 15             | N/A               | ❌ No      |

**Key Points**:

- Orders with `due_date < current_date` trigger overdue alerts
- Orders with `due_date` within urgent threshold trigger urgent alerts
- Orders with `due_date` within warning threshold trigger warning alerts
- Orders beyond warning threshold do not generate alerts (yet)

---

### 3. Generate Payment Alerts

**Action**: Run alert generation to scan all accounts payable

```sql
PERFORM purchase.generate_payment_alerts();
```

**Process Flow**:

1. **Retrieve Active Configurations**:

   ```sql
   SELECT * FROM purchase_order_payment_alert_config WHERE tenant_id IS NOT NULL
   ```

2. **For Each Tenant Configuration**:
   - Calculate threshold dates:
     - `warning_date = current_date + warning_days`
     - `urgent_date = current_date + urgent_days`

3. **Scan Unpaid Accounts**:

   ```sql
   SELECT sap.purchase_account_payable_id, ap.due_date
   FROM purchase_account_payable sap
   JOIN general_schema.account_payable ap ON sap.account_payable_id = ap.account_payable_id
   WHERE sap.account_payable_status != 3  -- Not paid
   AND ap.due_date IS NOT NULL
   ```

4. **Determine Alert Type**:
   - If `due_date < current_date`: **Overdue Payment** (type_id = 3)
   - Else if `due_date <= urgent_date`: **Urgent Payment** (type_id = 2)
   - Else if `due_date <= warning_date`: **Upcoming Due Date** (type_id = 1)
   - Else: No alert

5. **Insert Alert** (if not exists):

   ```sql
   INSERT INTO purchase_order_payment_alert (
       purchase_account_payable_id,
       payment_alert_type_id,
       alert_date,
       is_resolved
   ) VALUES (
       sap_id,
       alert_type_id,
       current_timestamp,
       false
   )
   ON CONFLICT DO NOTHING;  -- Prevents duplicates
   ```

**Expected Results**:

- Overdue order: Alert created with type "Overdue Payment"
- Urgent order: Alert created with type "Urgent Payment"
- Warning order: Alert created with type "Upcoming Due Date"
- OK order: No alert created

**Idempotency**:

- Running `generate_payment_alerts()` multiple times does not create duplicate alerts
- Existing unresolved alerts are not recreated
- Only new qualifying accounts trigger new alerts

---

### 4. View Pending Payment Alerts

**Action**: Retrieve all active alerts for a tenant

```sql
SELECT * FROM purchase.get_pending_payment_alerts('<tenant-uuid>');
```

**Returned Columns**:

| Column                        | Description                          | Example                      |
| ----------------------------- | ------------------------------------ | ---------------------------- |
| `payment_alert_id`            | Alert UUID                           | uuid                         |
| `purchase_account_payable_id` | Related account payable              | uuid                         |
| `purchase_order_id`           | Related purchase order               | uuid                         |
| `supplier_name`               | Supplier name                        | 'Alert Test Supplier'        |
| `invoice_number`              | Invoice number                       | 'INV-2026-001'               |
| `alert_type`                  | Alert type name                      | 'Overdue Payment'            |
| `alert_type_description`      | Type description                     | 'Alert for overdue payments' |
| `due_date`                    | Payment due date                     | 2026-01-08                   |
| `days_until_due`              | Days until due (negative if overdue) | -5                           |
| `balance_remaining`           | Amount still owed                    | 1130.00                      |
| `alert_date`                  | When alert was created               | 2026-01-13 10:30:00          |
| `created_at`                  | Alert creation timestamp             | 2026-01-13 10:30:00          |

**Sorting**: Results are ordered by:

1. `due_date ASC` (most urgent first)
2. `alert_date DESC` (newest first within same due date)

**Filtering**:

- Only returns alerts where `is_resolved = false`
- Only returns alerts for the specified tenant
- Only returns alerts for unpaid accounts

**Example Output**:

```sql
Alert #1:
  Type: Overdue Payment (Alert for overdue payments)
  Supplier: Alert Test Supplier
  Invoice: INV-2026-001
  Due date: 2026-01-08
  Days until due: -5
  Balance: $1,130.00
  Alert created: 2026-01-13 10:30:00

Alert #2:
  Type: Urgent Payment (Alert for urgent payments)
  Supplier: Alert Test Supplier
  Invoice: INV-2026-002
  Due date: 2026-01-15
  Days until due: 2
  Balance: $1,060.00
  Alert created: 2026-01-13 10:30:00
```

---

### 5. View Alert Statistics

**Action**: Get aggregated statistics for all alerts

```sql
SELECT * FROM purchase.get_payment_alert_stats('<tenant-uuid>');
```

**Returned Columns**:

| Column                 | Description                     | Example  |
| ---------------------- | ------------------------------- | -------- |
| `total_alerts`         | Total pending alerts            | 3        |
| `overdue_count`        | Count of overdue payments       | 1        |
| `urgent_count`         | Count of urgent payments        | 1        |
| `warning_count`        | Count of warning alerts         | 1        |
| `total_amount_at_risk` | Sum of all outstanding balances | 3,490.00 |

**Calculation Logic**:

```sql
-- Total alerts
COUNT(*) WHERE is_resolved = false

-- Overdue count
COUNT(*) WHERE payment_alert_type_id = 3 AND is_resolved = false

-- Urgent count
COUNT(*) WHERE payment_alert_type_id = 2 AND is_resolved = false

-- Warning count
COUNT(*) WHERE payment_alert_type_id = 1 AND is_resolved = false

-- Total amount at risk
SUM(ap.subtotal + sap.tax_amount - ap.amount_paid)
WHERE is_resolved = false
```

**Use Cases**:

- Dashboard widgets showing alert counts
- Financial risk assessment
- KPI tracking for accounts payable management
- Identifying payment bottlenecks

---

### 6. Automatic Alert Resolution on Payment

**Action**: Make a payment and observe automatic alert resolution

**Process**:

1. **Check Alerts Before Payment**:

   ```sql
   SELECT COUNT(*)
   FROM purchase_order_payment_alert
   WHERE purchase_account_payable_id = '<sap-uuid>'
   AND is_resolved = false;
   -- Returns: 1 (alert exists)
   ```

2. **Make Payment**:

   ```sql
   INSERT INTO purchase_order_payment (
       tenant_id,
       purchase_account_payable_id,
       amount_paid,
       payment_method_id,
       payment_reference,
       verified
   ) VALUES (
       '<tenant-uuid>',
       '<sap-uuid>',
       1130.00,  -- Full amount
       1,  -- Cash
       'FULL-PAYMENT-TEST',
       false
   )
   RETURNING payment_id;
   ```

3. **Verify Payment**:

   ```sql
   CALL purchase.verify_purchase_order_payment('<payment-uuid>');
   ```

4. **Automatic Trigger Execution**:

   **a) Payment Verification Updates Account Payable**:
   - `recalc_account_payable_on_payment()` trigger fires
   - Calls `check_account_payable_completion()`
   - Updates `purchase_account_payable.account_payable_status` to 3 (Paid)
   - Updates `general_schema.account_payable.is_paid` to true

   **b) Auto-Resolve Trigger Fires**:
   - `auto_resolve_payment_alerts()` trigger fires on account_payable_status change
   - Detects status changed to 3 (Paid)
   - Executes:

     ```sql
     UPDATE purchase_order_payment_alert
     SET is_resolved = true,
         updated_at = current_timestamp
     WHERE purchase_account_payable_id = '<sap-uuid>'
     AND is_resolved = false;
     ```

5. **Check Alerts After Payment**:

   ```sql
   SELECT COUNT(*)
   FROM purchase_order_payment_alert
   WHERE purchase_account_payable_id = '<sap-uuid>'
   AND is_resolved = false;
   -- Returns: 0 (alert auto-resolved)
   ```

**Expected Behavior**:

- Alert count decreases from 1 to 0
- Alert is marked as `is_resolved = true`
- No manual intervention required
- Works for partial payments too (status changes to 2, no resolution)
- Only resolves when fully paid (status = 3)

**Validation**:

```sql
-- Check resolved alerts
SELECT *
FROM purchase_order_payment_alert
WHERE purchase_account_payable_id = '<sap-uuid>';
-- Shows: is_resolved = true, updated_at = payment timestamp
```

---

## Validation Queries

### Check Alert Configuration

```sql
-- View tenant alert configuration
SELECT * FROM purchase.purchase_order_payment_alert_config
WHERE tenant_id = '<tenant-uuid>';

-- Expected columns: warning_days_before_due, urgent_days_before_due, email_notifications_enabled, sms_notifications_enabled
```

### Check Alert Types

```sql
-- View available alert types
SELECT * FROM purchase.purchase_order_payment_alert_type
ORDER BY payment_alert_type_id;

-- Expected types: Upcoming Due Date, Urgent Payment, Overdue Payment, Reconciliation Mismatch
```

### Check Active Alerts

```sql
-- All pending alerts for a tenant
SELECT
    spa.payment_alert_id,
    s.supplier_name,
    si.invoice_number,
    spat.payment_alert_type_name,
    ap.due_date,
    (ap.due_date - current_date) as days_until_due,
    (ap.subtotal + sap.tax_amount - ap.amount_paid) as balance,
    spa.is_resolved,
    spa.alert_date
FROM purchase.purchase_order_payment_alert spa
JOIN purchase.purchase_account_payable sap ON spa.purchase_account_payable_id = sap.purchase_account_payable_id
JOIN general_schema.account_payable ap ON sap.account_payable_id = ap.account_payable_id
JOIN purchase.purchase_order so ON sap.purchase_order_id = so.purchase_order_id
JOIN purchase.supplier s ON so.supplier_id = s.supplier_id
JOIN purchase.supplier_invoice si ON so.purchase_order_id = si.purchase_order_id
JOIN purchase.purchase_order_payment_alert_type spat ON spa.payment_alert_type_id = spat.payment_alert_type_id
JOIN purchase.supplier_branch sb ON s.supplier_id = sb.supplier_id
JOIN general_schema.branch b ON sb.branch_id = b.branch_id
WHERE b.tenant_id = '<tenant-uuid>'
AND spa.is_resolved = false
ORDER BY ap.due_date ASC;
```

### Check Alert History

```sql
-- All alerts (including resolved) for an account payable
SELECT
    payment_alert_id,
    payment_alert_type_id,
    alert_date,
    is_resolved,
    created_at,
    updated_at
FROM purchase.purchase_order_payment_alert
WHERE purchase_account_payable_id = '<sap-uuid>'
ORDER BY created_at DESC;
```

### Check Accounts Needing Alerts

```sql
-- Accounts that should have alerts but don't
SELECT
    sap.purchase_account_payable_id,
    ap.due_date,
    (ap.due_date - current_date) as days_until_due,
    sap.account_payable_status,
    (ap.subtotal + sap.tax_amount - ap.amount_paid) as balance
FROM purchase.purchase_account_payable sap
JOIN general_schema.account_payable ap ON sap.account_payable_id = ap.account_payable_id
WHERE sap.account_payable_status != 3  -- Not paid
AND ap.due_date IS NOT NULL
AND ap.due_date < (current_date + interval '7 days')  -- Within warning period
AND NOT EXISTS (
    SELECT 1 FROM purchase_order_payment_alert spa
    WHERE spa.purchase_account_payable_id = sap.purchase_account_payable_id
    AND spa.is_resolved = false
);
```

### Verify Alert Resolution

```sql
-- Check if alerts were auto-resolved after payment
SELECT
    spa.payment_alert_id,
    spa.is_resolved,
    spa.updated_at,
    sap.account_payable_status,
    ap.is_paid
FROM purchase.purchase_order_payment_alert spa
JOIN purchase.purchase_account_payable sap ON spa.purchase_account_payable_id = sap.purchase_account_payable_id
JOIN general_schema.account_payable ap ON sap.account_payable_id = ap.account_payable_id
WHERE spa.purchase_account_payable_id = '<sap-uuid>';

-- Expected: is_resolved = true, account_payable_status = 3, is_paid = true
```

---

## Common Failure Modes & Troubleshooting

### Issue 1: Alerts Not Generated

**Symptom**: `generate_payment_alerts()` runs but no alerts are created

**Troubleshooting**:

1. **Check if configuration exists**:

   ```sql
   SELECT * FROM purchase_order_payment_alert_config WHERE tenant_id = '<tenant-uuid>';
   ```

   - If no config: Run `initialize_payment_alert_config()`

2. **Check if accounts qualify for alerts**:

   ```sql
   -- Check unpaid accounts with due dates
   SELECT
       sap.purchase_account_payable_id,
       ap.due_date,
       (ap.due_date - current_date) as days_until_due,
       sap.account_payable_status
   FROM purchase_account_payable sap
   JOIN general_schema.account_payable ap ON sap.account_payable_id = ap.account_payable_id
   WHERE sap.account_payable_status != 3
   AND ap.due_date < (current_date + interval '7 days');
   ```

   - If empty: No accounts qualify for alerts

3. **Check if alerts already exist**:

   ```sql
   SELECT COUNT(*) FROM purchase_order_payment_alert WHERE is_resolved = false;
   ```

   - If count > 0: Alerts may already exist (idempotent function)

4. **Check tenant_id linkage**:
   - Ensure purchase_order → supplier → supplier_branch → branch → tenant linkage is intact
   - Verify tenant_id in configuration matches tenant_id in purchase chain

**Common Causes**:

- No alert configuration initialized
- All accounts already paid
- Due dates are far in the future (beyond warning threshold)
- Duplicate alert prevention (alerts already exist)

---

### Issue 2: Alerts Not Showing in get_pending_payment_alerts()

**Symptom**: Alerts exist in table but don't appear in query results

**Troubleshooting**:

1. **Check if alerts are resolved**:

   ```sql
   SELECT is_resolved FROM purchase_order_payment_alert WHERE payment_alert_id = '<alert-uuid>';
   ```

   - If `true`: Alert was already resolved

2. **Check tenant_id filter**:

   ```sql
   -- Get tenant for an alert
   SELECT b.tenant_id
   FROM purchase_order_payment_alert spa
   JOIN purchase_account_payable sap ON spa.purchase_account_payable_id = sap.purchase_account_payable_id
   JOIN purchase_order so ON sap.purchase_order_id = so.purchase_order_id
   JOIN supplier s ON so.supplier_id = s.supplier_id
   JOIN supplier_branch sb ON s.supplier_id = sb.supplier_id
   JOIN branch b ON sb.branch_id = b.branch_id
   WHERE spa.payment_alert_id = '<alert-uuid>';
   ```

   - Verify this matches the tenant_id used in query

3. **Check for data integrity issues**:

   ```sql
   -- Check for orphaned alerts
   SELECT spa.payment_alert_id
   FROM purchase_order_payment_alert spa
   LEFT JOIN purchase_account_payable sap ON spa.purchase_account_payable_id = sap.purchase_account_payable_id
   WHERE sap.purchase_account_payable_id IS NULL;
   ```

   - If results exist: Data integrity issue, cleanup needed

**Common Causes**:

- Wrong tenant_id passed to function
- Alerts were auto-resolved
- FOREIGN KEY relationships broken

---

### Issue 3: Alerts Not Auto-Resolving

**Symptom**: Payment made but alerts still show as unresolved

**Troubleshooting**:

1. **Check payment verification status**:

   ```sql
   SELECT verified FROM purchase_order_payment WHERE payment_id = '<payment-uuid>';
   ```

   - If `false`: Payment not verified, call `verify_purchase_order_payment()`

2. **Check account payable status**:

   ```sql
   SELECT account_payable_status
   FROM purchase_account_payable
   WHERE purchase_account_payable_id = '<sap-uuid>';
   ```

   - If not `3`: Not fully paid, alerts won't resolve

3. **Check if trigger exists**:

   ```sql
   SELECT * FROM pg_trigger WHERE tgname = 'auto_resolve_payment_alerts_trigger';
   ```

   - If empty: Trigger not installed, reinstall from purchase_functions.sql

4. **Check trigger execution**:
   - Look for errors in PostgreSQL logs
   - Test trigger manually:

     ```sql
     UPDATE purchase_account_payable
     SET account_payable_status = 3
     WHERE purchase_account_payable_id = '<sap-uuid>';

     -- Check if alerts resolved
     SELECT is_resolved FROM purchase_order_payment_alert
     WHERE purchase_account_payable_id = '<sap-uuid>';
     ```

**Common Causes**:

- Payment not verified
- Partial payment (status not fully paid)
- Trigger not installed or disabled
- Transaction rolled back
- Error in trigger code

---

### Issue 4: Duplicate Alerts Created

**Symptom**: Multiple alerts for the same account payable

**Troubleshooting**:

1. **Check for duplicate alerts**:

   ```sql
   SELECT
       purchase_account_payable_id,
       payment_alert_type_id,
       COUNT(*) as count
   FROM purchase_order_payment_alert
   WHERE is_resolved = false
   GROUP BY purchase_account_payable_id, payment_alert_type_id
   HAVING COUNT(*) > 1;
   ```

2. **Check alert generation logic**:
   - `generate_payment_alerts()` should use `ON CONFLICT DO NOTHING` or check for existence
   - Review function code for idempotency

3. **Clean up duplicates** (if needed):

   ```sql
   -- Keep only the most recent alert per account payable
   DELETE FROM purchase_order_payment_alert
   WHERE payment_alert_id NOT IN (
       SELECT DISTINCT ON (purchase_account_payable_id, payment_alert_type_id)
       payment_alert_id
       FROM purchase_order_payment_alert
       ORDER BY purchase_account_payable_id, payment_alert_type_id, created_at DESC
   );
   ```

**Common Causes**:

- Function called multiple times without idempotency check
- Race condition in concurrent execution
- Bug in alert generation logic

---

### Issue 5: Alert Statistics Incorrect

**Symptom**: `get_payment_alert_stats()` returns wrong counts or amounts

**Troubleshooting**:

1. **Verify manual count matches**:

   ```sql
   -- Manual count of overdue
   SELECT COUNT(*)
   FROM purchase_order_payment_alert spa
   WHERE spa.payment_alert_type_id = 3 AND spa.is_resolved = false;

   -- Compare with function result
   SELECT overdue_count FROM get_payment_alert_stats('<tenant-uuid>');
   ```

2. **Check amount calculation**:

   ```sql
   -- Manual calculation of total at risk
   SELECT SUM(ap.subtotal + sap.tax_amount - ap.amount_paid) as manual_total
   FROM purchase_order_payment_alert spa
   JOIN purchase_account_payable sap ON spa.purchase_account_payable_id = sap.purchase_account_payable_id
   JOIN general_schema.account_payable ap ON sap.account_payable_id = ap.account_payable_id
   WHERE spa.is_resolved = false;
   ```

3. **Check for data type issues**:
   - Ensure numeric columns use proper precision
   - Check for NULL VALUES affecting aggregations

**Common Causes**:

- JOIN logic in function excludes some records
- Incorrect WHERE clause filtering
- NULL VALUES not handled with COALESCE
- Rounding errors in numeric calculations

---

## Implementation Notes / Best Practices

### Alert Configuration

- **One config per tenant**: Use unique constraint on tenant_id
- **Reasonable thresholds**: Warning 7 days, Urgent 3 days are good defaults
- **Allow customization**: Different businesses have different payment cycles
- **Document notification channels**: Even if not implemented, config tracks pREFERENCES

### Alert Generation

- **Run periodically**: Schedule `generate_payment_alerts()` to run daily (e.g., via cron or pg_cron)
- **Idempotent design**: Function can be called multiple times safely
- **Performance optimization**: Add indexes on `due_date`, `account_payable_status`
- **Batch processing**: Function processes all tenants in one call

### Alert Monitoring

- **Dashboard integration**: Use `get_payment_alert_stats()` for real-time dashboards
- **Prioritize by type**: Show overdue first, then urgent, then warnings
- **Color coding**: Red (overdue), Orange (urgent), Yellow (warning)
- **Email notifications**: Use alert_date to send daily digest emails

### Alert Resolution

- **Trust auto-resolution**: Trigger handles resolution automatically
- **Manual resolution option**: Provide `resolve_payment_alert(alert_id)` for special cases
- **Audit trail**: Keep resolved alerts for historical analysis
- **Don't delete**: Use `is_resolved` flag instead of deleting records

### Data Integrity

- **FOREIGN KEY constraints**: Ensure ON DELETE CASCADE for cleanup
- **Consistent tenant linkage**: Verify supplier → branch → tenant path
- **Regular cleanup**: Archive old resolved alerts periodically
- **Test scenarios**: Use test data with various due date scenarios

---

## Quick Example Sequence

1. **Initialize config** → Set warning (7 days) and urgent (3 days) thresholds
2. **Create orders** → 4 orders with different due dates (overdue, urgent, warning, OK)
3. **Generate alerts** → Run `generate_payment_alerts()` → 3 alerts created
4. **View alerts** → Call `get_pending_payment_alerts()` → See 3 active alerts
5. **Check stats** → Call `get_payment_alert_stats()` → See counts by type
6. **Make payment** → Pay overdue order → Alert auto-resolves
7. **Verify resolution** → Check alerts again → Only 2 alerts remain

---

## REFERENCES

### Related Documentation

- [Supplier Purchase.md](Supplier%20purchase.md) - purchase order creation and payment process

### Database Objects

- Schema: `purchase` - Payment alert tables and functions
- Schema: `general_schema` - Account payable base tables
- Functions: `purchase_functions.sql` - All alert-related functions
- Test: `testPaymentAlerts.sql` - Complete alert system test

### Key Functions

- `initialize_payment_alert_config()` - Setup alert configuration
- `generate_payment_alerts()` - Generate alerts for all tenants
- `get_pending_payment_alerts()` - Retrieve active alerts
- `get_payment_alert_stats()` - Get alert statistics
- `auto_resolve_payment_alerts()` - Auto-resolution trigger
- `resolve_payment_alert()` - Manual alert resolution

### Alert Types

1. **Upcoming Due Date** (ID: 1) - Warning threshold (default 7 days)
2. **Urgent Payment** (ID: 2) - Urgent threshold (default 3 days)
3. **Overdue Payment** (ID: 3) - Past due date
4. **Reconciliation Mismatch** (ID: 4) - Payment reconciliation issues

### Integration Points

- **Dashboard**: Display alert counts and statistics
- **Email Service**: Send alert notifications
- **SMS Service**: Send urgent payment reminders
- **Reporting**: Include alerts in financial reports
- **API**: Expose alert data to frontend applications
