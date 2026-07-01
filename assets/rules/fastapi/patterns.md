---
paths:
  - "**/app/**/*.py"
  - "**/backend/**/*.py"
  - "**/routers/**/*.py"
  - "**/api/**/*.py"
---
# FastAPI Patterns

> Extends [python/patterns.md](../python/patterns.md). See skills: `fastapi-patterns`, `fastapi-testing`.

## Handlers

- `async def` by default. Blocking IO → `fastapi.concurrency.run_in_threadpool`.
- Always set `response_model=` on routes. Never return raw ORM objects without it.
- Use `status.HTTP_*` constants, not bare integers.
- Raise `HTTPException` or a domain exception handled by `@app.exception_handler`.

## Pydantic v2

- Separate `*Create` / `*Update` / `*Read` schemas. Never reuse DB models as response models.
- `ConfigDict(from_attributes=True)` for ORM → schema conversion.
- Mark sensitive fields (passwords, tokens) so they never appear in responses.

## Dependencies

- DB session via `Depends(get_db)` with a single commit/rollback in the dependency — never open `Session()` inside handlers.
- Auth via `Depends(require_user)` (or similar). Keep per-route authz checks explicit.
- Override dependencies in tests with `app.dependency_overrides`.

## Layout

- Router per feature under `app/api/<feature>/router.py`.
- Business logic in `service.py` functions that take an `AsyncSession` explicitly.
- Routers orchestrate, services do the work, schemas define the contract.

## Don't

- ❌ Return raw ORM objects without `response_model`
- ❌ `def` handler doing sync IO
- ❌ Global session / engine created at module import time without async lifecycle
- ❌ Business logic inside middleware
