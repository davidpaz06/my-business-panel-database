# Inventory - Add / Move / Remove Workflow

## High-level principles

- Use transactions and row-level locking (`SELECT ... FOR UPDATE`) to prevent race conditions.
- Validate inputs (quantity > 0, warehouse/product exist).
- Check and enforce stock constraints before reducing stock.
- Record every physical change in the inventory table and an audit row in `inventory_movement` (or your project's movement/log table).

## 1 Add stock to a warehouse (receipts / manual adjustments)

- Purpose: increase available stock for a product in a specific warehouse.
- Safety: always run in a transaction, use `FOR UPDATE` to lock the inventory row if present.

```sql
BEGIN;
-- lock an existing inventory row, if any
SELECT inventory_id, stock
FROM inventory_module.inventory
WHERE tenant_id = '<tenant_id>'
    AND product_id = '<product_id>'
    AND warehouse_id = '<warehouse_id>'
FOR UPDATE;

-- if exists, update; otherwise insert

-- record/insert audit movement
INSERT INTO inventory_module.inventory_movement
    (inventory_movement_id, inventory_movement_type_id, supply_order_id, created_at)
VALUES (
    gen_random_uuid(),
    (
        SELECT inventory_movement_type_id
        FROM inventory_module.inventory_movement_type
        WHERE inventory_movement_type_name = 'IN' LIMIT 1
    ),
    '<supply_order_id_or_null>',
    current_timestamp
);

COMMIT;
```

## 2 Remove stock from a warehouse (sales, adjustments, disposals)

- Purpose: decrease stock; must check available quantity.
- Safety: lock the inventory row and confirm stock >= requested removal quantity.

Transactional pattern:

```sql
BEGIN;
SELECT inventory_id, stock
FROM inventory_module.inventory
WHERE tenant_id = '<tenant_id>' AND product_id = '<product_id>' AND warehouse_id = '<warehouse_id>'
FOR UPDATE;

-- application logic: if no row -> raise 'no inventory' error
-- if stock < <quantity> -> raise 'insufficient stock'

UPDATE inventory_module.inventory
SET stock = stock - <quantity>, updated_at = current_timestamp
WHERE inventory_id = '<inventory_id>';

INSERT INTO inventory_module.inventory_movement (inventory_movement_id, inventory_movement_type_id, supply_order_id, created_at)
VALUES (gen_random_uuid(), (SELECT inventory_movement_type_id FROM inventory_module.inventory_movement_type WHERE inventory_movement_type_name='OUT' LIMIT 1), NULL, current_timestamp);

COMMIT;
```

Notes:

- Raise a clear exception if insufficient stock to prevent silent negative balances.
- Consider a business rule for negative stock (some systems allow backorders); if so, implement explicit policy and compensating records.

## 3 Transfer inventory between warehouses

- Purpose: move physical stock from one warehouse to another while keeping audit and transfer records.
- Approach: perform both a remove and an add in a single transaction and insert a transfer header + lines for reporting.

Transactional pattern:

```sql
BEGIN;
-- lock both inventory rows (order locks consistently to avoid deadlocks)
SELECT inventory_id, stock FROM inventory_module.inventory
WHERE tenant_id = '<tenant_id>' AND product_id = '<product_id>' AND warehouse_id = '<from_warehouse>'
FOR UPDATE;

SELECT inventory_id, stock FROM inventory_module.inventory
WHERE tenant_id = '<tenant_id>' AND product_id = '<product_id>' AND warehouse_id = '<to_warehouse>'
FOR UPDATE;

-- validate stock on source
UPDATE inventory_module.inventory
SET stock = stock - <quantity>, updated_at = current_timestamp
WHERE inventory_id = '<from_inventory_id>' AND stock >= <quantity>;

-- upsert destination
INSERT INTO inventory_module.inventory (inventory_id, tenant_id, product_id, warehouse_id, stock, created_at, updated_at)
VALUES (gen_random_uuid(), '<tenant_id>', '<product_id>', '<to_warehouse>', <quantity>, current_timestamp, current_timestamp)
ON CONFLICT (tenant_id, product_id, warehouse_id)
DO UPDATE SET stock = inventory_module.inventory.stock + EXCLUDED.stock, updated_at = current_timestamp;

-- create transfer header and product line for audit
INSERT INTO inventory_module.inventory_transfer (inventory_transfer_id, from_warehouse_id, to_warehouse_id, inventory_transfer_departure_date, transfer_date, created_at, updated_at)
VALUES (gen_random_uuid(), '<from_warehouse>', '<to_warehouse>', current_timestamp, current_timestamp, current_timestamp, current_timestamp)
RETURNING inventory_transfer_id;

INSERT INTO inventory_module.inventory_transfer_product (inventory_transfer_product_id, inventory_transfer_id, tenant_id, product_id, quantity, created_at, updated_at)
VALUES (gen_random_uuid(), '<returned_transfer_id>', '<tenant_id>', '<product_id>', <quantity>, current_timestamp, current_timestamp);

-- optional: insert inventory_movement rows for both OUT and IN movements
INSERT INTO inventory_module.inventory_movement (inventory_movement_id, inventory_movement_type_id, supply_order_id, created_at)
VALUES (gen_random_uuid(), (SELECT inventory_movement_type_id FROM inventory_module.inventory_movement_type WHERE inventory_movement_type_name='OUT' LIMIT 1), NULL, current_timestamp);

INSERT INTO inventory_module.inventory_movement (inventory_movement_id, inventory_movement_type_id, supply_order_id, created_at)
VALUES (gen_random_uuid(), (SELECT inventory_movement_type_id FROM inventory_module.inventory_movement_type WHERE inventory_movement_type_name='IN' LIMIT 1), NULL, current_timestamp);

COMMIT;
```

Notes:

- Lock rows with a deterministic order (e.g., lock the row with the smaller warehouse_id first) to reduce deadlock risk.
- If `inventory` rows don't exist for the destination, the `ON CONFLICT` upsert creates them.

## Idempotency & Safety

- Wrap multi-step operations in single transactions to ensure atomicity.
- Use `SELECT ... FOR UPDATE` to prevent lost updates.
- Prefer explicit existence and bounds checks (raise helpful errors on insufficient stock).
- For idempotent external calls, include an operation identifier and skip duplicates in business logic if needed.

## Troubleshooting queries

- Check inventory for product in a warehouse:

```sql
SELECT inventory_id, tenant_id, product_id, warehouse_id, stock, updated_at
FROM inventory_module.inventory
WHERE tenant_id = '<tenant_id>' AND product_id = '<product_id>' AND warehouse_id = '<warehouse_id>';
```

- Sum inventory across warehouses for a product:

```sql
SELECT SUM(stock) AS total_stock FROM inventory_module.inventory WHERE tenant_id = '<tenant_id>' AND product_id = '<product_id>';
```

s

- List recent inventory movements:

```sql
SELECT im.inventory_movement_id, im.created_at, im.inventory_movement_type_id, im.supply_order_id, t.inventory_movement_type_name
FROM inventory_module.inventory_movement im
LEFT JOIN inventory_module.inventory_movement_type t USING (inventory_movement_type_id)
ORDER BY im.created_at DESC LIMIT 100;
```
