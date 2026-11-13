---
name: sveltekit-fastapi-scaffold
description: 새 웹 프로젝트에 SvelteKit(JavaScript) + FastAPI + PostgreSQL + pm2 기본 골격을 한 번에 깐다 — 프로젝트 전용 PostgreSQL(embedded-postgres, sudo 없음)·backend/.venv(uv)·pm2(devDependency)까지 프로젝트 폴더 안에 자동 설치하고, 빈 포트를 골라 .env 를 쓰고, JWT 로그인·응답 봉투 {ok,status,data}·Tailwind+shadcn-svelte·Alembic 첫 마이그레이션까지 넣는다. 사용자가 "사이트 만들자", "웹앱 시작하자", "스벨트킷이랑 파이썬으로 세팅해", "프론트 백엔드 골격 잡아", "새 프로젝트 기본 세팅", "korea-tsukiji 처럼 세팅", "관리자 페이지 만들 준비" 처럼 새 프로젝트의 기본 구조를 요청하면, 단어가 scaffold 가 아니어도 반드시 이 스킬을 쓴다. 이미 골격이 있는 프로젝트에 기능을 더하는 일은 svelte-patterns·fastapi-patterns 가 맡는다. Scaffold a project-local SvelteKit + FastAPI + PostgreSQL + pm2 skeleton.
---

# SvelteKit + FastAPI 기본 골격

기준 예시는 사용자의 `korea-tsukiji-admin` 이다. 같은 모양(라우트 그룹 `(auth)`/`(dashboard)`, `src/lib/features/<기능>/`, pm2 dev/prod 분리, 응답 봉투)을 따르되, 아래는 그 프로젝트와 다르게 정했다(2026-11-13 사용자 결정):

- 백엔드 DB 는 **async SQLAlchemy + Alembic**(tsukiji 는 동기 + 손 스크립트)
- 파이썬은 **uv** 가 `backend/.venv` 를 만든다(tsukiji 는 venv + requirements.txt)
- PostgreSQL·pm2·파이썬 환경이 **전부 프로젝트 안**에 깔린다. 사용자는 프로젝트마다 설정이 다르고, 포맷·이관 때 프로젝트 폴더만 있으면 되기를 원한다.
- 프론트는 JavaScript(tsukiji 와 같음)

## 왜 이렇게 하나

- `sudo apt install postgresql` 은 비밀번호를 물어 자동 세팅이 멈추고, PC 의 모든 프로젝트가 한 DB 서버를 같이 쓰게 된다. `embedded-postgres` 는 PostgreSQL 실제 바이너리를 `node_modules` 에 받아 `.pgdata/` 에서 돌린다.
- 운영으로 옮길 때는 `pg_dump` → 운영 DB 복원 → `backend/.env` 의 `DATABASE_URL` 교체. 코드는 그대로다. (embedded-postgres 에는 `pg_dump`·`psql` 이 없다 — 이관 때 따로 준비.)

## 순서

명령은 프로젝트 루트에서. `uv`·`corepack` 이 `~/.local/bin` 에만 있을 수 있으니 PATH 에 없으면 `export PATH="$HOME/.local/bin:$PATH"` 를 앞에 붙인다.

1. **사전 점검** — 설치하지 않고 보고만 한다.
   `bash <skill>/scripts/precheck.sh` → node ≥ 20 · corepack pnpm · uv · python ≥ 3.11. 빠진 것이 있으면 멈추고 사용자에게 값으로 보고한다. 전역 설치(`npm i -g`, `sudo apt`, `pip install --user`)를 대신 실행하지 않는다.
2. **이름 정하기** — 프로젝트 폴더 이름(소문자·숫자·하이픈)을 기본으로 쓴다.
3. **골격 복사** — 먼저 `--dry-run` 으로 충돌을 본다.
   `python3 <skill>/scripts/scaffold.py --name <이름> --dest <프로젝트 루트> --dry-run`
   - exit 2 + `existing` 목록이면: 그 파일들을 덮어쓰지 않는다. 사용자에게 목록을 보이고 어떻게 할지 묻는다. (`.gitignore` 는 충돌이 아니라 빠진 줄만 덧붙인다. 이미 있는 `.env` 는 그대로 둔다.)
   - 통과하면 `--dry-run` 없이 다시 실행한다. 출력의 `ports` 를 사용자에게 알린다.
4. **설치** — 길다(처음 1~3분). `run_in_background` 로 돌리고 로그를 지켜본다.
   `COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack pnpm install`
5. **부트스트랩** — `corepack pnpm bootstrap`: `uv sync`(backend/.venv) → `.pgdata` 초기화·DB 생성(첫 실행만) → `alembic upgrade head`. 다시 돌려도 안전하다.
6. **확인** — `corepack pnpm test:backend`(SQLite 메모리로 돈다) · `corepack pnpm build`.
7. **첫 사용자** — 사용자에게 이메일·비밀번호를 받아 `corepack pnpm create-user <email> <password>`. 비밀번호를 대화·파일·커밋에 남기지 않는다.
8. **기동** — `corepack pnpm start:dev` → pm2 가 db·backend·frontend 세 앱을 띄운다. `curl -s localhost:<API_PORT_DEV>/health` 와 브라우저 `http://localhost:<VITE_FRONTEND_PORT_DEV>/login` 으로 확인한다.
9. **문서** — 프로젝트 `ARCHITECTURE.md` §2 디렉터리 지도·§5 외부 의존을 [references/structure.md](references/structure.md) 를 보고 채운다.

## 만들어지는 것

폴더 지도와 파일별 책임은 [references/structure.md](references/structure.md). 핵심만:

| 영역 | 내용 |
|---|---|
| 프론트 | SvelteKit 2 · Svelte 5 runes · Vite 7 · Tailwind 4 · shadcn-svelte 토큰(slate) · lucide · mode-watcher · svelte-sonner · 별칭 `$components $features $styles $stores` |
| 인증 | `/login` → JWT access(30분)·refresh(7일), localStorage, 401 이면 한 번 갱신 후 재시도 |
| 백엔드 | FastAPI · async SQLAlchemy(asyncpg) · Alembic(async env) · PyJWT · bcrypt · pydantic-settings |
| 응답 봉투 | `/api/*` JSON 응답은 HTTP 200 + `{ok, status, data, error}`. `/health` 는 감싸지 않는다 |
| 실행 | pm2 앱 3개 `<이름>-dev-{db,backend,frontend}` · prod 는 빌드 후 `vite preview` + uvicorn 2 workers |

## 하지 않는 것

- 기능 화면·API(예시 tsukiji 의 재고·채팅·OCR 등). 골격까지만.
- 회원가입 API. 공개 가입은 보안 결정이라 기본에서 뺐다. 사용자는 `create-user` 로 만든다.
- 배포(도메인·HTTPS). shadcn 컴포넌트는 필요할 때 `npx shadcn-svelte@latest add <이름>`.

## 문제가 생기면

- `pnpm install` 이 `ERR_PNPM_IGNORED_BUILDS` → `pnpm-workspace.yaml` 의 `allowBuilds:` 에 그 패키지를 `true` 로 넣고, `node_modules` 를 지운 뒤 다시 설치. (pnpm 12 는 예전 `onlyBuiltDependencies` 를 무시한다 — 2026-11-13 실측.) 이 단계가 빠지면 bootstrap 이 `Missing symlink "native/lib/libecpg.so"` 로 죽는다.
- `db-run` 이 바로 죽음 → `corepack pnpm bootstrap` 을 먼저 했는지, `DB_PORT` 를 다른 프로세스가 쓰는지(`ss -ltn | grep <포트>`) 본다.
- 포트를 바꾸려면 루트 `.env` 의 포트와 `backend/.env` 의 `DATABASE_URL`·`ALLOWED_ORIGINS` 를 같이 바꾼다.
