# Inventory - Counting / Discrepancy Report Workflow

## High-level principles

- Use transactions and row-level locking (`SELECT ... FOR UPDATE`) to prevent race conditions.
- Validate inputs (quantity > 0, warehouse/product exist).
- Check and enforce stock constraints before reducing stock.
- Record every physical change in the inventory table and an audit row in `inventory_movement` (or your project's movement/log table).

## 1 Count all products in a warehouse

With a single query, the user is able to extract the count of al the products in a given warehouse

### Query flow:

```sql
SELECT
    i.product_id,
    p.product_name,
    SUM(i.stock) AS total_stock,
    COUNT(*) AS inventory_rows
FROM inventory_module.inventory i
JOIN core.product p
    ON i.tenant_id = p.tenant_id
    AND i.product_id = p.product_id
WHERE i.warehouse_id = '<warehouse_id>'
GROUP BY i.product_id, p.product_name
ORDER BY p.product_name;
```

## 2 Creating a discrepancy report

If there is any discrepancy between the product count in the system and the physical count, the user must submit a discrepancy report, detailing both counts, this operation must be done for all the individual products that create a discrepancy

### Query flow:

```sql
INSERT INTO inventory_module.discrepancy_count (
    warehouse_id,
    product_id,
    stored_quantity,
    physical_cuantity,
    discrepancy_reason
)
VALUES (
    '<warehouse_id>',
    '<product_id>',
    <stored_quantity>,
    <physical_cuantity>,
    '<discrepancy_reason>'
)

```
