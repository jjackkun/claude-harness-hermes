---
paths:
  - "**/*.sql"
  - "**/migrations/**"
  - "**/alembic/**"
  - "**/models.py"
  - "**/schema.prisma"
---
# PostgreSQL Patterns

> See skills: `postgres-patterns`, `database-migrations`.

## Schema

- `TIMESTAMPTZ` for all time columns. Never `TIMESTAMP WITHOUT TIME ZONE`.
- `TEXT` over `VARCHAR(n)` unless there's a real length constraint.
- `JSONB`, not `JSON`. Only use it when the shape is genuinely dynamic — otherwise normalize.
- Every table: primary key, `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, usually `updated_at`.
- Foreign keys always declared with `ON DELETE` behavior spelled out (CASCADE / RESTRICT / SET NULL).

## Queries

- No `SELECT *`. List columns explicitly — protects against schema drift.
- Parameterized queries only. Never string-interpolate user input into SQL.
- Use `EXPLAIN (ANALYZE, BUFFERS)` before optimizing; don't guess at indexes.
- Default transaction isolation is `READ COMMITTED`. If you change it, leave a comment explaining why.

## Indexes

- Add an index for every foreign key unless the parent table is tiny.
- Production index creation: `CREATE INDEX CONCURRENTLY` to avoid table locks.
- Partial indexes (`WHERE status = 'active'`) are cheap wins when queries always filter on the predicate.
- Don't over-index write-heavy tables — each index costs on every write.

## Migrations

- Code and migration in the same commit/PR. Never out of sync.
- Migrations are append-only. Never edit a merged migration — write a new one.
- Destructive migrations (drop column, rename table) require a multi-step plan: add new → backfill → switch reads → switch writes → drop old.
- Test rollback locally before merging.
- Never touch the production database directly. Always via a migration file.

## Don't

- ❌ `SELECT *`
- ❌ Unparameterized SQL
- ❌ Schema changes outside migrations
- ❌ `CREATE INDEX` (non-concurrently) on large production tables
- ❌ Storing timestamps as strings or without timezone
