---
name: structured-file-layout
description: Use when creating new files, planning features, or writing exec-plans — before any code is written, to ensure each file has a single responsibility and folders are organized by domain
---

# structured-file-layout

코드 작성 전에 파일과 폴더 구조를 책임 단위로 설계한다.

## 핵심 원칙

> **1 파일 = 1 책임. 파일명이 그 책임을 드러낸다.**
> 500줄 차단은 이 원칙이 상류에서 실패했다는 신호다 — 결과를 고치는 것이 아니라 원인을 잡는다.

## 발동 조건

- 새 파일을 만들기 전
- exec-plan 작성 시
- 기존 파일을 크게 수정하기 전
- 새 기능/모듈을 설계할 때

## 설계 순서

### 1단계 — 책임 한 줄 정의

파일을 만들기 전에 "이 파일은 ___만 한다"를 한 문장으로 완성한다.

```
# 올바른 예
auth_service.py   → "JWT 발급과 검증만 한다"
user_router.py    → "유저 CRUD HTTP 라우팅만 한다"
useAuthStore.ts   → "인증 상태(토큰·사용자)만 관리한다"

# 잘못된 예 (책임 2개 이상)
utils.py          → "여러 유틸 함수들"
helpers.ts        → "공통으로 쓰는 것들"
```

한 문장에 "그리고", "또한", "및"이 들어가면 책임이 2개다 → 파일을 나눈다.

### 2단계 — 폴더 배치 결정

파일 타입이 아니라 **도메인/기능 단위**로 폴더를 구성한다.

```
# 올바른 예 (도메인 기준)
features/
  auth/
    auth_service.py
    auth_router.py
    auth_schema.py
  task/
    task_service.py
    task_router.py

# 잘못된 예 (타입 기준 — 도메인 파악 불가)
services/
  auth_service.py
  task_service.py
routers/
  auth_router.py
  task_router.py
```

도메인이 명확히 다르면 폴더로 분리. 같은 폴더 내 파일이 5개를 넘으면 하위 폴더를 검토한다.

### 3단계 — 배럴 파일 계획

각 도메인 폴더에 `index.ts` / `__init__.py`를 두어 import 경로를 단순하게 유지한다.

```python
# features/auth/__init__.py
from .auth_service import AuthService
from .auth_schema import TokenResponse
```

외부에서는 `from features.auth import AuthService`만 알면 된다.

### 4단계 — exec-plan에 파일 트리 명시

계획 문서에 예상 파일 트리와 각 파일의 책임을 한 줄씩 기록한다.

```markdown
## 파일 구조

features/auth/
  auth_service.py   # JWT 발급·검증
  auth_router.py    # 로그인·로그아웃 엔드포인트
  auth_schema.py    # 요청/응답 Pydantic 모델
  __init__.py       # 배럴 export
```

파일 트리 없이 코딩을 시작하지 않는다.

## 500줄 규칙과의 관계

| 상황 | 의미 | 행동 |
|------|------|------|
| 파일이 400줄 경고 | 이 단계를 건너뛴 신호 | 책임 재점검 후 split |
| 파일이 500줄 차단 | 원칙이 상류에서 실패 | split + 이 스킬로 재설계 |
| 한 책임인데 500줄 초과 | 정당한 예외 (큰 스키마 등) | waiver 주석 + docs/audits/ 기록 |

500줄 차단 자체가 목표가 아니다. 이 스킬을 따르면 500줄 차단은 거의 발생하지 않는다.

## 흔한 실수

| 실수 | 올바른 방향 |
|------|------------|
| `utils.py`에 여러 책임 몰아넣기 | 책임별로 `date_utils.py`, `string_utils.py` 분리 |
| 파일 타입 기준 폴더 (`services/`, `schemas/`) | 도메인 기준 폴더 (`features/auth/`) |
| 배럴 없이 깊은 경로 import | `__init__.py`로 공개 API 정의 |
| exec-plan에 파일 목록 없이 바로 코딩 | 파일 트리 먼저, 코드는 그 다음 |
