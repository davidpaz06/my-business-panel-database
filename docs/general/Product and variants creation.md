# Product and variants creation

## Product (CABYS Catalog)

The `product` table is a **global, shared catalog** based on CABYS (Catálogo de Bienes y
Servicios) — the official Costa Rican classification of goods and services used for
electronic invoicing and tax compliance.

### Key Characteristics

- **Global catalog**: not partitioned or tenant-specific. All tenants share the same CABYS entries.
- **Primary key**: `cabys_code VARCHAR(13)` — the 13-digit CABYS classification code.
- **Tax linkage**: references `tax_rate_id` for the corresponding tax rate and supports `is_exonerated` flag.
- **Measurement units**: references `unit_measure_id` and `commercial_unit_measure_id` for standard and commercial units.
- **Full-text search**: `product_name_tsv` is a `GENERATED ALWAYS AS` tsvector column (Spanish config) for efficient search.
- **Category support**: optional `product_category_id` for hierarchical organization.

A product record contains:

- cabys_code: 13-digit CABYS classification code (PK)
- product_name: Display name
- product_name_tsv: Auto-generated tsvector for Spanish FTS
- product_category_id: Optional classification
- tax_rate_id: Associated tax rate
- unit_measure_id: Standard unit of measure (FK to `unit_measure`)
- commercial_unit_measure_id: Commercial unit of measure (FK to `commercial_unit_measure`)
- is_exonerated: Whether the product is tax-exonerated (default false)
- Timestamps: created_at, updated_at

## Product Variant (Tenant's Sellable Items)

When tenants add products to their catalog, they create entries in the `product_variant`
table. Each variant is the actual sellable SKU and optionally references a CABYS catalog
entry via `cabys_code`.

**Scope:** Tenants manage their inventory through `product_variant`. The `product` table
is the read-only CABYS reference catalog. All sales, purchases, and inventory operations
use `product_variant_id`.

## Data Model Overview

```bash
product (CABYS catalog — global, not partitioned)
  └── product_variant (tenant sellable SKU) [partitioned x8 by tenant_id]
        └── attribute_assignation (many-to-many) [partitioned x8]
              └── attribute_value (e.g., "Red", "XL")
                    └── tenant_attribute (e.g., "Color", "Size")
                          └── global_attribute (template)

unit_measure ──────────┐
commercial_unit_measure ┼──► product (FK references)
tax_rate ──────────────┘
```

## Prerequisites

- Tenant exists in `general_schema.tenant` with an active subscription.
- Database schema deployed with:
  - Tables: `general_schema.product`, `general_schema.product_variant`, `general_schema.product_category`, `general_schema.unit_measure`, `general_schema.commercial_unit_measure`, `general_schema.global_attribute`, `general_schema.tenant_attribute`, `general_schema.attribute_value`, `general_schema.attribute_assignation`.
  - Partitions: `general_schema.product_variant` partitioned by hash on `tenant_id` (8 partitions). Same for `attribute_assignation`. The `product` table is **not** partitioned.
  - Indexes: unique constraint on `(tenant_id, sku)` for `product_variant`, GIN index on `product_name_tsv`, index on `product_variant(cabys_code)`.
  - Triggers: `update_product_timestamp`, `update_product_variant_timestamp`, `update_unit_measure_timestamp`, `update_commercial_unit_measure_timestamp`.

## High-level Flow

1. **Populate CABYS Catalog** — seed the `product` table with CABYS entries (cabys_code, product_name, tax_rate, units).
2. **Create Product Categories** (optional but recommended for organization).
3. **Create Product Variants** — tenant creates sellable SKUs, optionally referencing a CABYS entry via `cabys_code`.
4. **Create Attributes** — define global attributes (Color, Size) and tenant-specific values (Red, Blue, S, M, L).
5. **Assign Attributes to Variants** — link attribute values to product variants.
6. **Search & Query** — use full-text search on the CABYS catalog or standard filters on variants.
7. **Update/Delete** — modify or remove product variants as needed (with CASCADE behavior for attributes).

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

### 2. Find all variants linked to a CABYS entry

```sql
SELECT pv.*
FROM general_schema.product_variant pv
WHERE pv.cabys_code = '<cabys_code>';
```

### 3. List all enabled attributes for a tenant

```sql
SELECT ta.tenant_attribute_id, ga.attribute_name, ta.display_name
FROM general_schema.tenant_attribute ta
JOIN general_schema.global_attribute ga ON ta.global_attribute_id = ga.global_attribute_id
WHERE ta.tenant_id = '<tenant_id>';
```

### 4. Search CABYS catalog by name (full-text search)

```sql
SELECT p.cabys_code, p.product_name
FROM general_schema.product p
WHERE p.product_name_tsv @@ plainto_tsquery('spanish', 'camiseta');
```

### 5. Get a tenant's variants with their CABYS info

```sql
SELECT pv.product_variant_id, pv.sku, pv.variant_name, p.cabys_code, p.product_name AS cabys_name
FROM general_schema.product_variant pv
LEFT JOIN general_schema.product p ON pv.cabys_code = p.cabys_code
WHERE pv.tenant_id = '<tenant_id>';
```
