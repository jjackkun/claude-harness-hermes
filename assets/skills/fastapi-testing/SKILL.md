---
name: fastapi-testing
description: Testing FastAPI apps with pytest-asyncio and httpx.AsyncClient — fixtures, dependency overrides, DB isolation, auth.
---

# FastAPI Testing

Async-first testing patterns for FastAPI with pytest-asyncio and httpx.

## When to Activate

- Writing tests for FastAPI routes, services, or dependencies
- Setting up test fixtures (DB, client, auth)
- Integration tests with a real test database
- Mocking external services or dependencies

## Stack

- `pytest` + `pytest-asyncio` (mode = "auto" recommended)
- `httpx.AsyncClient` with `ASGITransport` — **not** TestClient (which is sync)
- Separate test DB, cleaned per-test via transactions or truncate

## Baseline Configuration

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
```

## Core Fixtures

```python
# tests/conftest.py
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from app.main import app
from app.db.base import Base
from app.deps import get_db

TEST_DB_URL = "postgresql+asyncpg://test:test@localhost:5432/test_db"

@pytest.fixture(scope="session")
async def engine():
    engine = create_async_engine(TEST_DB_URL, future=True)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()

@pytest.fixture
async def db(engine) -> AsyncSession:
    """Per-test session wrapped in a rollback so nothing persists."""
    connection = await engine.connect()
    trans = await connection.begin()
    session = AsyncSession(bind=connection, expire_on_commit=False)
    try:
        yield session
    finally:
        await session.close()
        await trans.rollback()
        await connection.close()

@pytest.fixture
async def client(db) -> AsyncClient:
    async def override_get_db():
        yield db

    app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()
```

**Key points:**
- Rollback-per-test fixture → full isolation, no manual cleanup.
- `dependency_overrides[get_db]` routes the app to the test session.
- `ASGITransport` runs the app in-process — no network, no uvicorn.

## Route Tests

```python
# tests/api/test_users.py
import pytest

async def test_create_user(client):
    res = await client.post("/users", json={
        "email": "a@b.com",
        "name": "Alice",
        "password": "secret123",
    })
    assert res.status_code == 201
    body = res.json()
    assert body["email"] == "a@b.com"
    assert "password" not in body  # response_model should strip it

async def test_create_user_duplicate(client):
    payload = {"email": "a@b.com", "name": "A", "password": "secret123"}
    await client.post("/users", json=payload)
    res = await client.post("/users", json=payload)
    assert res.status_code == 409
    assert res.json()["code"] == "conflict"

async def test_get_user_not_found(client):
    res = await client.get("/users/99999")
    assert res.status_code == 404
```

## Authenticated Requests

```python
@pytest.fixture
async def auth_headers(db, client) -> dict[str, str]:
    # Create a user directly via service, then mint a token
    from app.api.users.service import create_user
    from app.core.security import create_access_token
    from app.api.users.schemas import UserCreate

    user = await create_user(db, UserCreate(
        email="test@test.com", name="Test", password="secret123",
    ))
    token = create_access_token(user.id)
    return {"Authorization": f"Bearer {token}"}

async def test_protected_route(client, auth_headers):
    res = await client.get("/me", headers=auth_headers)
    assert res.status_code == 200
```

## Mocking External Services

```python
from unittest.mock import AsyncMock

async def test_invite_triggers_email(client, monkeypatch):
    sent = AsyncMock()
    monkeypatch.setattr("app.api.users.service.send_invite_email", sent)

    res = await client.post("/invite", json={"email": "x@y.com"})
    assert res.status_code == 200
    sent.assert_awaited_once()
```

For HTTP clients, use `respx` (httpx mocking) or `aioresponses` (aiohttp).

## Service-Layer Unit Tests

```python
# tests/services/test_user_service.py
async def test_create_user_hashes_password(db):
    from app.api.users.service import create_user
    from app.api.users.schemas import UserCreate

    user = await create_user(db, UserCreate(
        email="a@b.com", name="A", password="plain",
    ))
    assert user.password_hash != "plain"
    assert user.password_hash.startswith("$2b$")  # bcrypt
```

Service tests are faster and more focused than route tests. Prefer them for business-logic coverage; use route tests for the HTTP contract.

## Parametrize for Validation

```python
@pytest.mark.parametrize("field,value,error_loc", [
    ("email", "not-an-email", ["body", "email"]),
    ("name",  "",              ["body", "name"]),
    ("password", "short",      ["body", "password"]),
])
async def test_create_user_validation(client, field, value, error_loc):
    payload = {"email": "a@b.com", "name": "A", "password": "longenough"}
    payload[field] = value
    res = await client.post("/users", json=payload)
    assert res.status_code == 422
    assert res.json()["detail"][0]["loc"] == error_loc
```

## Anti-patterns

- ❌ `TestClient` (sync) for async app — serializes requests, doesn't test async paths
- ❌ Hitting the real production DB — always a separate test DB
- ❌ `time.sleep()` waiting for background tasks — await them directly or mock
- ❌ Shared fixture state without rollback — tests become order-dependent
- ❌ Mocking the DB layer — use a real test DB. Mocks hide SQL/schema bugs.
- ❌ Asserting on full response body dicts — assert specific fields; tolerate server-added metadata (timestamps, ids)
- ❌ Forgetting `app.dependency_overrides.clear()` — leaks overrides into other tests

**Remember**: FastAPI's test story is only good if you commit to async end-to-end. Mixed sync/async tests become flaky fast.
