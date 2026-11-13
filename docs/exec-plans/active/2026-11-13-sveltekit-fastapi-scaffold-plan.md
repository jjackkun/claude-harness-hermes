# 2026-11-13-sveltekit-fastapi-scaffold — SvelteKit + FastAPI 기본 골격 스킬

## 1. 동기 (Why)

- 사용자는 새 웹 프로젝트를 SvelteKit(프론트) + FastAPI(백엔드) + PostgreSQL + pm2 로 시작한다. 예전에 이 골격을 까는 스킬을 만들었으나 PC 포맷 때 저장하지 않아 잃었다(2026-11-13 사용자 확인).
- 지금 apt-curtain(거실 사진 + 커튼 합성 → 사진·영상)을 사이트로 만들려는데 골격이 없다. 매번 손으로 만들면 프로젝트마다 구조가 달라진다.
- 기준 예시는 `~/PROJECT/korea-tsukiji-admin` (사용자: "기본에 가깝다"). 잃지 않도록 이번에는 공장 저장소에 둔다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 스킬 `sveltekit-fastapi-scaffold` 가 `assets/skills/` 에 있고 svelte 프리셋이 깐다 — 검증: `grep -n sveltekit-fastapi-scaffold presets/framework/svelte.conf`
- [x] 빈 폴더에 스크립트 한 번으로 골격이 생긴다(프로젝트 이름·포트 치환, 기존 파일은 덮어쓰지 않고 목록만 보고) — 검증: `python3 assets/skills/sveltekit-fastapi-scaffold/scripts/scaffold.py --name demo --dest /tmp/x` 후 파일 수·치환 누락(`{{`) 0
- [x] 생성된 백엔드 시험이 통과한다(헬스·로그인·토큰 갱신·응답 봉투) — 검증: `cd backend && uv run pytest`
- [x] 생성된 프론트가 빌드된다 — 검증: `corepack pnpm install && corepack pnpm build`
- [x] 공장 시험이 스크립트를 지킨다(덮어쓰기 금지·치환 누락 0·빈 포트) — 검증: `bash tests/sveltekit-fastapi-scaffold-test.sh`
- [ ] apt-curtain 에 실제로 깔아 pm2 dev 로 프론트·백엔드가 뜬다 — 검증: `curl -s localhost:<api>/health`

## 2-bis. 착수 전 확인한 사실 (2026-11-13)

| 확인한 것 | 결과 |
| --------- | ---- |
| 기준 예시 프론트 | SvelteKit 2.49 · Svelte 5.45 · Vite 7 · **JavaScript**(jsconfig, shadcn `typescript:false`) · Tailwind 4 · shadcn-svelte(bits-ui) · lucide · mode-watcher · svelte-sonner · SCSS 전역 변수 · 별칭 `$components $styles $stores $utils` · `src/lib/features/<기능>/{api.js,index.js}` · 라우트 그룹 `(auth)` `(dashboard)` |
| 기준 예시 백엔드 | FastAPI · **동기** SQLAlchemy 2.0 + psycopg2 · Alembic 은 requirements 에만 있고 미사용(손으로 쓴 `migrate_*.py`) · venv + requirements.txt · JWT(python-jose, passlib) · pydantic-settings · `/api` 응답을 `{ok,status,data,error}` 로 감싸는 미들웨어 |
| 기준 예시 pm2 | `ecosystem.config.cjs` 하나로 dev/prod 네임스페이스 분리, 포트 dev/prod 분리(프론트 8876/8866, 백엔드 8877/8867), `.env` 파싱, `logs/` · `scripts/pm2-start.cjs` |
| 이 PC 도구 | Node v22.23 · npm 10.9 · Python 3.12.3 · `~/.local/bin/uv` 0.13.1 (PATH 에 `~/.local/bin` 없음) · pnpm 없음 → `corepack pnpm` 12.18 동작 · **pm2 없음** · **PostgreSQL 없음**(5432 미사용, /etc/postgresql 없음) · docker 없음 |

## 3. 비목표 (Out of Scope)

- apt-curtain 의 실제 기능(합성·영상 화면). 골격까지만.
- 배포(도메인·HTTPS·서버). prod 는 pm2 로 로컬에서 뜨는 것까지.
- TypeScript 판. 사용자 결정으로 JavaScript.
- 전역 설치(pm2·pnpm·postgres·pip). 전부 프로젝트 안에 깐다(§6 결정 참고).

## 4. 영향 영역

- 코드: `assets/skills/sveltekit-fastapi-scaffold/` 신규, `presets/framework/svelte.conf` 에 스킬 1줄 추가, `tests/` 시험 1개.
- **신규 파일 목록**:
  - `assets/skills/sveltekit-fastapi-scaffold/SKILL.md` — 언제 쓰나 · 사전 점검 · 실행 순서 · 끝난 뒤 확인
  - `.../scripts/scaffold.py` — 템플릿 복사 + `{{PROJECT}}`·포트 치환, 기존 파일 보호
  - `.../scripts/free_ports.py` — 쓰이지 않는 포트 4개(프론트 dev/prod, API dev/prod) 고르기
  - `.../scripts/precheck.sh` — node·corepack pnpm·uv·postgres 유무를 값으로 보고
  - `.../templates/root/` — `package.json` · `svelte.config.js` · `vite.config.js` · `jsconfig.json` · `components.json` · `ecosystem.config.cjs` · `scripts/pm2-start.cjs` · `.env.example` · `.gitignore` · `pnpm-workspace.yaml`
  - `.../templates/root/src/` — `app.html` · `app.css` · `lib/utils/api.js`(봉투 해석 + 토큰 갱신) · `lib/utils.js`(cn) · `lib/stores/auth.svelte.js` · `lib/features/auth/{api.js,index.js}` · `lib/components/layout/{Navbar,Sidebar}.svelte + index.js` · `lib/styles/variables.scss` · `routes/+layout.svelte` · `routes/(auth)/login/+page.svelte` · `routes/(dashboard)/+layout.svelte` · `routes/(dashboard)/dashboard/+page.svelte`
  - `.../templates/backend/` — `pyproject.toml` · `.env.example` · `alembic.ini` · `alembic/env.py`(async) · `alembic/versions/0001_users.py` · `app/main.py` · `app/core/{config,database,security,envelope}.py` · `app/models/user.py` · `app/schemas/auth.py` · `app/api/{deps,health,auth}.py` · `tests/{conftest,test_health,test_auth}.py`
  - `.../references/structure.md` — 만들어지는 폴더 지도와 각 파일의 책임
  - `.../templates/scripts/` — `bootstrap.mjs`(uv sync → initdb·DB 생성 → alembic) · `db-run.mjs`(pm2 용 PostgreSQL) · `env.cjs`(.env 읽기) · `uv.sh`(PATH 밖 uv) · `pm2-start.cjs`
  - `tests/sveltekit-fastapi-scaffold-test.sh` — 스크립트 동작 시험(모델 호출 0), `tests/run-all.sh` 에 등록
- 룰: 공장 원칙 "공통 반영은 사용자 승인 후 PR".
- 데이터: 생성물에 Alembic 첫 마이그레이션(users).
- 외부 의존: 템플릿 안 버전은 기준 예시의 버전 범위를 따른다.

## 5. 단계 (Steps)

### Step 1. 템플릿 — 기준 예시에서 골라 옮기기 [Impl]
- 입력: korea-tsukiji-admin. 산출: `templates/`. 기능 특화(fullcalendar·chart.js·OCR·이메일 등)는 뺀다.
- 검증: 템플릿 안 `korea-tsukiji`·`tsukiji` 문자열 0.

### Step 2. 백엔드 async + Alembic + uv [Impl]
- SQLAlchemy 2 async(asyncpg), `get_db` 요청 스코프, Alembic async env. 시험은 SQLite(aiosqlite)로 DB 없이 돈다.
- 검증: 생성물에서 `uv run pytest` 통과.

### Step 3. 스크립트 + 공장 시험 [Impl]
- 검증: `tests/sveltekit-fastapi-scaffold-test.sh` 통과, 덮어쓰기 시도 시 실패 코드.

### Step 4. SKILL.md + 프리셋 등록 [Impl]
- 검증: `claude-md-skill-index-test.sh` 등 기존 공장 시험 통과.

### Step 5. apt-curtain 에 적용 [Review]
- PostgreSQL 이 있어야 백엔드가 실제 DB 로 뜬다 — 사용자 결정 후.

## 6. 의사결정 로그

- 2026-11-13: 프론트 언어 JavaScript — 근거: 사용자 선택(기준 예시와 같게).
- 2026-11-13: DB async SQLAlchemy + Alembic — 근거: 사용자 선택(규칙 "마이그레이션은 파일로").
- 2026-11-13: 파이썬 도구 uv — 근거: 사용자 선택.
- 2026-11-13: 기본 포함 pm2 dev/prod · JWT 로그인 · UI 키트 · 응답 봉투 — 근거: 사용자 선택(4개 모두).
- 2026-11-13: 저장 위치 공장 저장소, 템플릿 + 스크립트, 빈 포트 자동 탐색 — 근거: 사용자 선택.
- 2026-11-13: pm2 는 전역이 아니라 생성 프로젝트의 devDependency — 근거: 전역 설치 금지 규칙, 이 PC 에 pm2 없음.
- 2026-11-13: 백엔드 시험은 SQLite 메모리 DB — 근거: PostgreSQL 없이도 골격 검증이 돌아야 함.
- 2026-11-13: **모든 실행 도구는 프로젝트 전용, 세팅 한 번에 자동 설치** — 근거: 사용자 지시("각 프로젝트마다 세팅이 있으니 프로젝트 전용, venv 도"). 구성:
  - PostgreSQL: npm `embedded-postgres`(devDependency, PostgreSQL 18.6 바이너리) → `node_modules` 안. 데이터는 `.pgdata/`(git 제외). sudo·apt 없음. pm2 에 DB 를 세 번째 앱으로 등록.
  - Python: `uv` 가 `backend/.venv` 를 만든다(`uv sync`). 전역 pip 설치 없음.
  - Node: `corepack pnpm` 으로 `node_modules`. pm2 도 devDependency.
  - 첫 세팅에서 DB 사용자·비밀번호(무작위)·DB 이름을 만들고 `backend/.env` 의 `DATABASE_URL` 에 적는다.
  - 운영 이관: `pg_dump` → 운영 DB 복원 → `DATABASE_URL` 교체. 코드 변경 없음.
- 2026-11-13: `sudo apt install postgresql` 은 쓰지 않는다 — 근거: 비밀번호 입력에서 자동 세팅이 멈춤, 전역 설치 금지 규칙. embedded-postgres 실측이 실패할 때만 대안으로 사용자에게 제시.

## 7. 발견·예외

- **실측 2026-11-13 (임시 폴더)** `npm i -D embedded-postgres@18.6.0-beta.19` 4.6초 → `initialise` 1.1초 · `start` · `createDatabase` · 쿼리 · `stop` 모두 성공. `PostgreSQL 18.6 on x86_64-pc-linux-gnu`. sudo 없음.
- 같은 패키지 bin 에는 `initdb` · `pg_ctl` · `postgres` 만 있다 — **`psql`·`pg_dump` 없음.** 운영 이관 때 덤프 도구는 따로 필요(그때 정함).
- **실측** `uv init --bare` + `uv add fastapi uvicorn sqlalchemy[asyncio] asyncpg alembic pydantic-settings` 3.9초 → `backend/.venv` 생성, FastAPI 0.162.5 · SQLAlchemy 2.1.8 · asyncpg 0.32.0. `uv` 는 `~/.local/bin/uv` 이고 PATH 밖 → 스크립트가 경로를 직접 찾는다.
- 이 PC 에 PostgreSQL·pm2·pnpm 이 없다(포맷 뒤). 스킬은 사전 점검에서 이것을 값으로 보고하고, 전역 설치는 하지 않는다.
- 기준 예시 `database.py` 는 `echo=True` 고정(운영에서도 SQL 로그). 템플릿은 dev 에서만 켠다.

- **실측 2026-11-13 (임시 폴더 demo-app, 끝까지)**:
  - scaffold: 60 파일, 포트 8811~8815, 같은 폴더 재실행은 exit 2·변화 0.
  - `corepack pnpm install` 첫 시도 **실패** `ERR_PNPM_IGNORED_BUILDS` — pnpm 12.18 은 `onlyBuiltDependencies` 를 무시한다. `allowBuilds: {pkg: true}` 로 바꾸고 `node_modules` 를 지운 뒤 재설치해 통과. 이 실패 때 bootstrap 은 `Missing symlink "native/lib/libecpg.so"` 로 죽었다 → SKILL.md 「문제가 생기면」 에 적음.
  - `test:backend` 8 통과(2.5초) · `build` 통과.
  - `bootstrap` 통과(uv sync → initdb → DB 생성 → alembic upgrade), 두 번째 실행도 통과(멱등).
  - `start:dev` → pm2 앱 3개 online, 재시작 0. `create-user` 통과. vite 프록시로 `/api/health` → `{"ok":true,"status":200,"data":{"status":"ok","db":true}}`, `/api/auth/login` → ok·토큰 3개, `/login` HTTP 200.
  - 정리: 시험용 pm2 앱 삭제, 데몬 종료, 포트 8811~8815 비어 있음 확인.
  - 확인 안 함: `start:prod`(빌드 + vite preview + uvicorn workers 2), 브라우저 화면 실제 로그인 클릭.
- `create-user` 실행 때 asyncio 디버그 경고("Executing <Task …> took 0.205 seconds")가 한 줄 나온다. 동작에는 영향 없음, 원인 미확인.
- 공장 시험: `sveltekit-fastapi-scaffold-test.sh` 22 통과 · `claude-md-skill-index-test.sh` 13 통과 · `copy-install-test.sh` 60 통과 · `doc-counts-gate-test.sh` 19 통과(`scripts/sync-doc-counts.sh` 로 148→149 갱신 뒤).

- **apt-curtain 적용 때 발견 (2026-11-13, 커밋 37c9cd1)**: 프로젝트에 이미 `.env`(GEMINI_API_KEY 만)가 있으면 scaffold 가 `.env` 를 통째로 건너뛰어 포트·DB 키가 빠졌다 → bootstrap 이 실패할 상태. 기존 키·값은 지키고 빠진 키만 덧붙이게 고침, 시험 [7] 5단언 추가(고치기 전 코드로 2개 실패 확인). 적용 결과: install·bootstrap·시험 8·build 통과, pm2 3앱 online, `/api/health` db true.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
