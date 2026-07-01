---
name: fastapi-patterns
description: FastAPI application patterns — routing, Pydantic v2, dependency injection, error handling, async DB sessions, middleware.
---

# FastAPI Patterns

Production FastAPI patterns with Pydantic v2 and async-first design.

## When to Activate

- Designing or editing FastAPI routes / routers
- Writing Pydantic models (request/response, validation)
- Dependency injection, background tasks, middleware
- Async database sessions, transaction scoping
- Error handling, exception handlers, status codes
- OpenAPI schema customization

## Project Layout

```
backend/
├── app/
│   ├── main.py              # FastAPI() + router mounting
│   ├── config.py            # Settings (pydantic-settings)
│   ├── deps.py              # Shared Depends() — DB session, current_user
│   ├── api/
│   │   ├── users/
│   │   │   ├── router.py    # APIRouter
│   │   │   ├── schemas.py   # Pydantic models
│   │   │   └── service.py   # Business logic (pure funcs, takes session)
│   │   └── ...
│   ├── db/
│   │   ├── base.py          # engine, session factory
│   │   └── models.py        # SQLAlchemy ORM
│   └── core/
│       ├── security.py      # JWT, password hashing
│       └── errors.py        # AppException hierarchy
└── tests/
```

Router per feature. Service layer takes an `AsyncSession` explicitly — no hidden globals.

## Pydantic v2 Schemas

```python
from pydantic import BaseModel, Field, EmailStr, ConfigDict
from datetime import datetime

class UserCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    email: EmailStr
    name: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=8, exclude=True)  # never echoed back

class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)  # ORM mode

    id: int
    email: EmailStr
    name: str
    created_at: datetime
```

**Rules:**
- Separate `*Create` / `*Update` / `*Read` schemas. Never reuse DB models as response models.
- `from_attributes=True` for ORM → schema conversion.
- `Field(exclude=True)` or separate internal model for sensitive fields.
- Use `EmailStr`, `HttpUrl`, `UUID4` etc. for built-in validation.

## Routing & Response Models

```python
from fastapi import APIRouter, Depends, status, HTTPException
from .schemas import UserCreate, UserRead
from .service import create_user, get_user
from app.deps import get_db, require_user

router = APIRouter(prefix="/users", tags=["users"])

@router.post(
    "",
    response_model=UserRead,
    status_code=status.HTTP_201_CREATED,
)
async def create(
    payload: UserCreate,
    db: AsyncSession = Depends(get_db),
) -> UserRead:
    user = await create_user(db, payload)
    return user  # FastAPI serializes via response_model

@router.get("/{user_id}", response_model=UserRead)
async def read(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_user),  # auth
) -> UserRead:
    user = await get_user(db, user_id)
    if not user:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    return user
```

- **Always set `response_model`** — prevents leaking fields, drives OpenAPI schema.
- **Use proper status codes** via `status.HTTP_*` constants.
- **Async handlers by default**. Sync CPU-bound work → `fastapi.concurrency.run_in_threadpool`.

## Dependency Injection

```python
# app/deps.py
from typing import AsyncGenerator
from fastapi import Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.base import async_session

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise

async def require_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    user = await verify_token(db, token)
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")
    return user
```

- Session lifecycle tied to request. Commit on success, rollback on exception.
- Dependencies are plain async functions — easy to unit test.
- Override in tests with `app.dependency_overrides[get_db] = fake_get_db`.

## Error Handling

```python
# app/core/errors.py
class AppException(Exception):
    status_code: int = 500
    code: str = "internal_error"

class NotFoundError(AppException):
    status_code = 404
    code = "not_found"

class ConflictError(AppException):
    status_code = 409
    code = "conflict"

# app/main.py
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI()

@app.exception_handler(AppException)
async def app_exception_handler(request: Request, exc: AppException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"code": exc.code, "message": str(exc)},
    )
```

Domain code raises `AppException` subclasses. HTTP concerns stay in routers / exception handlers.

## Background Tasks

```python
from fastapi import BackgroundTasks

@router.post("/invite")
async def invite(
    payload: InviteIn,
    tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    user = await create_pending_user(db, payload)
    tasks.add_task(send_invite_email, user.email, user.token)
    return {"status": "queued"}
```

- For short, fire-and-forget work. For anything > a few seconds or needing retries → proper queue (Celery, RQ, ARQ, Dramatiq).

## Middleware & CORS

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,  # explicit list, never "*" in prod with credentials
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

- Request ID / logging middleware for tracing.
- Never put business logic in middleware — only cross-cutting concerns.

## Config (pydantic-settings)

```python
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    cors_origins: list[str] = []

settings = Settings()
```

- Typed, validated, env-backed. No raw `os.getenv()` scattered around.

## Anti-patterns

- ❌ Returning raw SQLAlchemy ORM objects without `response_model`
- ❌ `def` handlers doing blocking IO (use `async def` + async driver, or `run_in_threadpool`)
- ❌ Opening DB sessions inside handlers with `Session()` directly — use `Depends(get_db)`
- ❌ Catching broad `Exception` in handlers and returning 200 with `{"error": ...}` — use proper status codes
- ❌ Mutating Pydantic models in place as if they were dataclasses — prefer `model_copy(update=...)`
- ❌ `response_model=UserCreate` on a create endpoint — leaks password. Use `UserRead`.
- ❌ Global DB session / engine created at import time without proper async lifecycle

**Remember**: FastAPI's power is the router → schema → dependency pipeline. Keep business logic in service functions that take a session explicitly — routers just orchestrate.
