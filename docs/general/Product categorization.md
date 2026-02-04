# Product categorization

## Product Category Hierarchy (Self-Referencing)

The `product_category` table supports hierarchical (tree-like) organization of categories through a self-referencing foreign key:

- `parent_category_id` (nullable): Points to another `product_category_id` in the same table, allowing categories to be nested.
- Root categories have `parent_category_id IS NULL`.
- This enables unlimited category depth (e.g., Electronics > Computers > Laptops).

**Example:**

```sql
-- Create a root category
INSERT INTO general_schema.product_category (category_name) VALUES ('Electronics') RETURNING product_category_id;

-- Create a subcategory
INSERT INTO general_schema.product_category (category_name, parent_category_id)
VALUES ('Laptops', <electronics_id>);

-- Query full hierarchy (recursive)
WITH RECURSIVE cat_tree AS (
      SELECT product_category_id, category_name, parent_category_id
      FROM general_schema.product_category
      WHERE category_name = 'Laptops'
      UNION ALL
      SELECT c.product_category_id, c.category_name, c.parent_category_id
      FROM general_schema.product_category c
      INNER JOIN cat_tree t ON c.product_category_id = t.parent_category_id
)
SELECT * FROM cat_tree;
```

## Common queries

### 1. Create Product Category

```sql
-- Check if category exists (idempotent)
INSERT INTO general_schema.product_category (category_name)
VALUES ('Electronics')
ON CONFLICT (category_name) DO NOTHING
RETURNING product_category_id;

-- Query existing category
SELECT product_category_id FROM general_schema.product_category WHERE category_name = 'Electronics';
```

### 2. List all categories in a hierarchy

```sql
WITH RECURSIVE cat_tree AS (
      SELECT product_category_id, category_name, parent_category_id
      FROM general_schema.product_category
      WHERE parent_category_id IS NULL
      UNION ALL
      SELECT c.product_category_id, c.category_name, c.parent_category_id
      FROM general_schema.product_category c
      INNER JOIN cat_tree t ON c.parent_category_id = t.product_category_id
)
SELECT * FROM cat_tree;
```
