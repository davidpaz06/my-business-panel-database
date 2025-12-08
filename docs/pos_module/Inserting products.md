# Product Management — End-to-End Flow

This document explains the end-to-end flow for creating product categories and inserting products (single and batch) in a multi-tenant POS system. The goal is to demonstrate that a tenant can define product categories, insert individual products, and perform bulk product imports while maintaining data integrity through partitioning and constraints.

**Scope:** product catalog management where each tenant maintains its own isolated product inventory with global and custom attributes, full-text search capabilities, and partition-based storage for scalability.

## Prerequisites

- Tenant exists in `core.tenant` with an active subscription.
- Database schema deployed with:
  - Tables: `core.product`, `core.product_category`, `core.global_attribute`, `core.tenant_attribute`, `core.product_attribute`.
  - Partitions: `core.product` partitioned by hash on `tenant_id` (8 partitions: `product_p0` through `product_p7`).
  - Indexes: unique constraint on `(tenant_id, sku)`, full-text search index on `product_name_tsv`, partition-aware btree index on `tenant_id`.
  - Triggers: `update_product_tsv` (auto-generates tsvector for Spanish full-text search), `update_product_timestamp`.

## High-level Flow

1. **Create Product Categories** (optional but recommended for organization).
2. **Insert Single Product** — create one product at a time with unique SKU per tenant.
3. **Batch Insert Products** — bulk insert multiple products in a single transaction or loop.
4. **Assign Attributes** — link global or custom tenant-specific attributes to products.
5. **Search & Query** — use full-text search or standard filters to retrieve products.
6. **Update/Delete** — modify or remove products as needed (with CASCADE behavior for attributes).

## Detailed Steps & SQL snippets

### 1. Create Product Category

Categories help organize products. Multiple products can share the same category.

```sql
-- Check if category exists (idempotent)
INSERT INTO core.product_category (category_name)
VALUES ('Electronics')
ON CONFLICT (category_name) DO NOTHING
RETURNING product_category_id;

-- Query existing category
SELECT product_category_id FROM core.product_category WHERE category_name = 'Electronics';
```
