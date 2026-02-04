# Product and variants creation

## Product (Base Product Definition)

A product is a fundamental catalog record stored in the `product` table that represents
a base product entity within the system. It serves as the central reference point for all
business operations including sales transactions, inventory management, and variant management.

### Key Characteristics

- Represents a single, sellable item with core attributes (name, description, price, category)
- Acts as the parent entity for product variants, which are the actual SKU-specific units
- Tenant-isolated: each tenant maintains its own independent product catalog through hash partitioning
- Supports hierarchical organization through product categories
- Enables multi-variant sales models (e.g., one base product "T-Shirt" with variants for size/color combinations)

A product record contains:

- tenant_id: Identifies the tenant owner (enables multi-tenancy)
- product_id: Unique identifier (UUID)
- sku: Base product SKU
- product_name: Display name with full-text search support
- product_description: Detailed product information
- product_category_id: Classification for organization
- unit_price: Base pricing reference
- Timestamps: created_at, updated_at for audit trails

**Scope:** product catalog management where each tenant maintains its own isolated product inventory with global and custom attributes, sellable variants, full-text search capabilities, and partition-based storage for scalability.

## Data Model Overview

```bash
product (base product)
  └── product_variant (sellable SKU) [partitioned x8]
        └── attribute_assignation (many-to-many) [partitioned x8]
              └── attribute_value (e.g., "Red", "XL")
                    └── tenant_attribute (e.g., "Color", "Size")
                          └── global_attribute (template)
```

## Prerequisites

- Tenant exists in `general_schema.tenant` with an active subscription.
- Database schema deployed with:
  - Tables: `general_schema.product`, `general_schema.product_variant`, `general_schema.product_category`, `general_schema.global_attribute`, `general_schema.tenant_attribute`, `general_schema.attribute_value`, `general_schema.attribute_assignation`.
  - Partitions: `general_schema.product` partitioned by hash on `tenant_id` (8 partitions). Same for `product_variant` and `attribute_assignation`.
  - Indexes: unique constraint on `(tenant_id, sku)` for both product and product_variant, full-text search index on `product_name_tsv`, partition-aware btree indexes.

---

- Triggers: `update_product_tsv` (auto-generates tsvector for Spanish full-text search), `update_product_timestamp`, `update_product_variant_timestamp`.

## High-level Flow

1. **Create Product Categories** (optional but recommended for organization).
2. **Insert Base Product** — create one base product with its product_category.
3. **Create Attributes** — define global attributes (Color, Size) and tenant-specific values (Red, Blue, S, M, L).
4. **Create Product Variants** — create sellable SKUs referencing the base product.
5. **Assign Attributes to Variants** — link attribute values to product variants.
6. **Search & Query** — use full-text search or standard filters to retrieve products/variants.
7. **Update/Delete** — modify or remove products as needed (with CASCADE behavior for variants and attributes).

---

## EAV Model: Attributes, Values, and Variants

The system uses an Entity-Attribute-Value (EAV) model to support flexible product variants and custom attributes per tenant.

### Table Roles in the EAV Model

- **global_attribute**: Defines the master list of possible attributes (e.g., Color, Size) available to all tenants. These are templates and not directly assigned to products.
- **tenant_attribute**: Each tenant can enable or customize global attributes for their catalog. This table links a tenant to a global attribute, allowing for tenant-specific naming, visibility, or constraints.
- **attribute_value**: Stores the possible values for each tenant_attribute (e.g., "Red", "Blue" for Color). Values are tenant-specific.
- **attribute_assignation**: Many-to-many join table linking product_variant to attribute_value. Each row assigns a value (e.g., "Red") to a variant (e.g., T-Shirt Large Red).
- **product_variant**: Represents a specific sellable SKU, defined by a unique combination of attribute values (e.g., T-Shirt, Size L, Color Red).

### How Attribute Applicability Works

- **Global attributes** are defined once and can be enabled per tenant via `tenant_attribute`.
- Each tenant can choose which attributes to use, rename them, or restrict their values.
- When creating a product variant, the system assigns attribute values (from `attribute_value`) via `attribute_assignation`.
- This allows each tenant to have a custom set of attributes and values, while still supporting global reporting and analytics.

---

## Common Queries

### 1. Get all attributes and values for a product variant

```sql
SELECT ta.tenant_attribute_id, ga.attribute_name, av.value
FROM general_schema.attribute_assignation aa
JOIN general_schema.attribute_value av ON aa.attribute_value_id = av.attribute_value_id
JOIN general_schema.tenant_attribute ta ON av.tenant_attribute_id = ta.tenant_attribute_id
JOIN general_schema.global_attribute ga ON ta.global_attribute_id = ga.global_attribute_id
WHERE aa.product_variant_id = '<variant_id>';
```

### 2. Find all variants for a base product

```sql
SELECT * FROM general_schema.product_variant
WHERE product_id = '<base_product_id>';
```

### 3. List all enabled attributes for a tenant

```sql
SELECT ta.tenant_attribute_id, ga.attribute_name, ta.display_name
FROM general_schema.tenant_attribute ta
JOIN general_schema.global_attribute ga ON ta.global_attribute_id = ga.global_attribute_id
WHERE ta.tenant_id = '<tenant_id>';
```

### 4. Search products by attribute value (e.g., all "Red" T-Shirts)

```sql
SELECT p.product_id, p.product_name, pv.product_variant_id
FROM general_schema.product p
JOIN general_schema.product_variant pv ON p.product_id = pv.product_id
JOIN general_schema.attribute_assignation aa ON pv.product_variant_id = aa.product_variant_id
JOIN general_schema.attribute_value av ON aa.attribute_value_id = av.attribute_value_id
WHERE av.value = 'Red';
```
