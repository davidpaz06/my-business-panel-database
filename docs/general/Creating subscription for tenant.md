# Creating Subscription for Tenant

This document describes the process for creating and extending a subscription for a tenant, from the initial payment to the activation of the tenant in the system, as well as the logic for subscription renewal. It also provides common queries for managing and inspecting tenant subscriptions.

## Subscription Creation Flow

1. **Initial Payment**
   - The process begins when a tenant makes their first payment using an accepted payment method (see `payment_method` table).
   - A record is inserted into the `tenant_payment` table, capturing payment details such as amount, date, method and reference.
   - Payments are stored initially as unverified while being checked by the stripe service.

2. **Subscription Record Creation**
   - Upon successful payment, a new record is created in the `subscription` table, linked to the tenant and the payment.
   - The subscription includes:
     - `tenant_id`: The tenant receiving the subscription.
     - `start_date`: When the subscription becomes valid (usually payment date).
     - `end_date`: When the subscription expires (calculated based on plan duration).
     - `is_active`: Set to `true` if the subscription is currently valid.
     - `payment_id`: Reference to the payment that triggered the subscription.

3. **Tenant Activation**
   - Once the subscription is created and `is_active = true`, the corresponding tenant record in the `tenant` table is updated:
     - `is_active` is set to `true`.
     - This enables the tenant to access the platform and its services.

**Note:** The process is transactional—if any step fails, the subscription is not activated.

---

## Subscription Extension (Renewal)

When a tenant with an active subscription makes a renewal payment:

1. **Renewal Payment**
   - A new payment is recorded in `tenant_payment`.

2. **Subscription Extension Logic**
   - If the tenant already has an active subscription (`is_active = true` and `end_date > now()`):
     - The new subscription's `start_date` is set to the current `end_date` of the active subscription (no gap in service).
     - The `end_date` is extended by the plan duration from the new `start_date`.
   - If the previous subscription is expired:
     - The new subscription starts from the payment date.

3. **Update Records**
   - The new subscription is inserted into the `subscription` table, linked to the new payment.
   - The tenant's `is_active` remains `true`.

**Note:** Only one subscription per tenant should have `is_active = true` at any time. Expired subscriptions are marked as inactive.

---

## Common Queries

### 1. Get current active subscription for a tenant

```sql
SELECT * FROM general_schema.subscription
WHERE tenant_id = '<tenant_id>' AND is_active = true AND end_date > now();
```

### 2. List all payments for a tenant

```sql
SELECT * FROM general_schema.tenant_payment
WHERE tenant_id = '<tenant_id>'
ORDER BY payment_date DESC;
```

### 3. Check if a tenant is active

```sql
SELECT is_active FROM general_schema.tenant
WHERE tenant_id = '<tenant_id>';
```

### 4. Get subscription history for a tenant

```sql
SELECT * FROM general_schema.subscription
WHERE tenant_id = '<tenant_id>'
ORDER BY start_date DESC;
```

### 5. Find tenants with expired subscriptions

```sql
SELECT t.tenant_id, t.tenant_name
FROM general_schema.tenant t
LEFT JOIN general_schema.subscription s ON t.tenant_id = s.tenant_id AND s.is_active = true
WHERE t.is_active = false OR s.end_date < now();
```

---

## Notes

- All operations should be performed within a transaction to ensure data consistency.
- The subscription logic supports future extension for multiple plans, trial periods, and grace periods.
