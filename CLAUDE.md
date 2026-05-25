# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Workspace context (sibling repos, cross-repo feature order, branching) lives in `../CLAUDE.md`. This file covers database-only conventions.

## Role

**Source of truth for the PostgreSQL schema.** Pure SQL — no ORM, no migrations framework. The backend reads from / mutates this schema; it does not own it. Domain: multi-tenant ERP for Costa Rica (POS, inventory, purchase, HR, accounting, Hacienda e-invoicing).

## Folder responsibilities

| Folder                                 | Holds                                         | Notes                                                             |
| -------------------------------------- | --------------------------------------------- | ----------------------------------------------------------------- |
| `schemas/<name>/<name>_schema.sql`     | Canonical DDL per schema                      | **Single source of truth.** One file per schema.                  |
| `migrations/<name>/NNN-kebab-case.sql` | Append-only structural change history         | 3-digit prefix, never modified after merge, DDL only (no INSERT). |
| `functions/<name>/`                    | Functions, triggers, stored procedures, views | Loaded after schemas, before seeds.                               |
| `sql/queries/`                         | Reusable analytical / complex queries         | Reference material — backend keeps its own query strings.         |
| `seeds/catalog/<schema>/`              | Catalog / reference data                      | e.g. roles, regions, document types.                              |
| `seeds/dev/`                           | Dev/sample data                               | Not loaded in prod.                                               |
| `test/`                                | Idempotent flow test scripts                  | See "Tests" below.                                                |
| `docs/`                                | Business flow docs                            | `flow-<name>.md`.                                                 |
| `backup/`                              | Manual SQL backups                            | Read-only artifacts.                                              |
| `bootstrap.sql`                        | Generated full-state bootstrap                | **Never hand-edit.** Built by `build-bootstrap.ps1`.              |

Schemas in load order (see `schema_exec_order.md`): `general → pos → purchase → inventory → hr → accounting`. The same order is reflected in `bootstrap.sql`.

## Commands

```powershell
# Regenerate bootstrap.sql from schemas/ + functions/ + sql/ + seeds/
./build-bootstrap.ps1
```

Bootstrap is auto-run by the backend's Docker compose on first DB container start. To reset locally from the backend repo:

```bash
docker compose -f docker-compose.dev.yml down
rm -rf ./postgres-data
docker compose -f docker-compose.dev.yml up -d
docker logs my-business-panel-postgres | grep -E "(ERROR|Bootstrap completado|ready to accept)"
```

Each dev must run their **own local DB** — no shared databases, no testing against shared environments. Must be able to drop, recreate from `bootstrap.sql`, run seeds + tests, with zero manual steps.

## Workflow for any structural change

For every DDL change, do **all three**:

1. **Edit `schemas/<name>/<name>_schema.sql`** to reflect the new canonical state. This is what new environments build from.
2. **Add a new migration** `migrations/<name>/NNN-kebab-case.sql` for the historical record (next free 3-digit prefix). DDL only. Idempotent (`IF NOT EXISTS`, `IF EXISTS`, guarded `ALTER`s). Include commented rollback and an audit comment header.
3. **Rebuild bootstrap**: `./build-bootstrap.ps1`. Never hand-edit `bootstrap.sql`.

If the change adds/edits a function, view, or trigger, place the body under `functions/<schema>/` (loaded between schemas and seeds).

If the change adds catalog data, add SQL to `seeds/catalog/<schema>/`. **Migrations never contain `INSERT`** — that belongs in seeds.

After the change is merged, update `schema_exec_order.md` if the migration carries non-obvious impact, and append a `docs/flow-<name>.md` if it implements/changes a business flow.

## Migration rules

- **Append-only.** Once a migration is merged, never edit it. Fix forward with a new migration.
- **DDL only.** `CREATE`, `ALTER`, `DROP`, `TRUNCATE`. No `INSERT` (use `seeds/`).
- **Idempotent guards.** `IF NOT EXISTS` / `IF EXISTS` on every object.
- **Audit comment header** at top: what + why + ticket/context.
- **Commented rollback block** at bottom — what would undo this change. Commented because we do not auto-roll back; this is documentation.
- **3-digit prefix, kebab-case** — `NNN-short-description.sql`. Next prefix = highest current + 1, taken across all schemas (numbering is global, folders are organizational).
- **Partitioned tables**: `product_variant` and `attribute_assignation` are partitioned x8. Indexes and FKs must include the partition key or target each partition explicitly.

## Naming + style

- Schema suffix `<name>_schema` (e.g. `general_schema`, `pos_schema`).
- `snake_case` for tables, columns, functions, indexes.
- PKs: `<table>_id` (e.g. `product_id`). Surrogate keys via `SERIAL`/`BIGSERIAL`/`UUID DEFAULT gen_random_uuid()` (pgcrypto enabled in bootstrap).
- Audit columns where applicable: `created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`, `updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`.
- Tenant scoping: any tenant-owned table carries `tenant_id`; FKs `REFERENCES general_schema.tenant(tenant_id)`. Index on `tenant_id` for query paths used by the backend.
- Money: `NUMERIC(precision, scale)` — never `FLOAT`/`REAL`/`DOUBLE PRECISION`.
- Spanish identifiers / comments in business-domain tables are intentional — keep that convention.
- **No emojis** anywhere — schema, comments, migrations, docs.

## Tests

Any change to a business process must include a test script in `test/`.

- **Idempotent**: clean → seed → execute flow → assert. Must run repeatedly on the same DB without conflict.
- File name: `test/test-<name>.md` (script + expected results documented together).
- Without a test, the change is incomplete. Without a `docs/flow-<name>.md`, it is technical debt.

## Hacienda / e-invoicing context

`accounting/` schema + corresponding migrations carry Costa Rica electronic invoicing structures. Spec PDFs live in `../my-business-panel-docs/` — read them (especially `Resolucion Comprobantes Electronicos DGT-R-48-2016.pdf`) before designing or altering those tables.

## Forbidden

- Editing a merged migration.
- Hand-editing `bootstrap.sql`.
- Putting `INSERT` in a migration (use `seeds/`).
- Sharing a database between developers.
- Adding emojis or English-only copy where Spanish is the existing convention in that area.
- NO emojis
- Direct push to upstream `development`, `staging`, `master`. PR via personal fork only (see `contributing.md`).
