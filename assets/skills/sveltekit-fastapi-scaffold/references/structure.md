# 만들어지는 폴더 지도

```text
<project>/
├── .env                      포트 5개 · DB 이름/사용자/비밀번호 (scaffold 가 생성, 600, git 제외)
├── .pgdata/                  프로젝트 전용 PostgreSQL 데이터 (bootstrap 이 생성, git 제외)
├── logs/                     pm2 로그 (git 제외)
├── package.json              프론트 의존성 + 실행 스크립트(bootstrap·migrate·start:dev …)
├── pnpm-workspace.yaml       설치 스크립트를 허용할 패키지 (embedded-postgres·pm2·esbuild)
├── ecosystem.config.cjs      pm2 앱 3개: db · backend · frontend (dev/prod 네임스페이스)
├── svelte.config.js · vite.config.js · jsconfig.json · components.json(shadcn-svelte)
├── scripts/
│   ├── bootstrap.mjs         uv sync → initdb·DB 생성(첫 실행) → alembic upgrade head
│   ├── db-run.mjs            pm2 가 돌리는 PostgreSQL 프로세스(종료 신호에 정상 종료)
│   ├── pm2-start.cjs         프로젝트 안 pm2 로 start/restart (prod 는 먼저 build)
│   ├── env.cjs               .env 읽기 (ecosystem·scripts 공용)
│   └── uv.sh                 PATH 밖의 uv(~/.local/bin) 를 찾아 실행
├── src/
│   ├── app.html · app.css    Tailwind 4 + shadcn 토큰, 다크 모드
│   ├── lib/
│   │   ├── utils.js          cn() — shadcn 컴포넌트용
│   │   ├── utils/api.js      fetch 래퍼: 봉투 해석, 토큰 저장, 401 시 갱신 1회
│   │   ├── stores/auth.svelte.js   로그인 사용자 상태(runes)
│   │   ├── features/<기능>/  api.js + index.js(배럴) — 기능마다 폴더 하나
│   │   ├── components/layout/      Navbar · Sidebar · index.js(배럴)
│   │   └── styles/variables.scss   SCSS 전역 변수(모든 <style lang="scss"> 에 자동 주입)
│   └── routes/
│       ├── +layout.svelte · +layout.js(ssr=false) · +page.js(→ /dashboard)
│       ├── (auth)/login/+page.svelte
│       └── (dashboard)/+layout.svelte(로그인 확인) · dashboard/+page.svelte(서버 상태)
└── backend/
    ├── .env                  DATABASE_URL · SECRET_KEY · ALLOWED_ORIGINS (scaffold 생성, 600)
    ├── .venv/                uv 가 만든 프로젝트 전용 파이썬 환경
    ├── pyproject.toml        의존성 + dev 그룹(pytest·httpx·aiosqlite·ruff) + pytest/ruff 설정
    ├── alembic.ini · alembic/env.py(async) · alembic/versions/0001_create_users.py
    ├── app/
    │   ├── main.py           create_app(): CORS · 봉투 미들웨어 · 라우터
    │   ├── core/             config(설정) · database(엔진·세션·Base) · security(bcrypt·JWT) · envelope(봉투)
    │   ├── models/           user.py · __init__.py(배럴)
    │   ├── schemas/          auth.py · __init__.py(배럴)
    │   ├── api/              deps(현재 사용자) · health(/health, /api/health) · auth(login·refresh·me)
    │   └── cli/create_user.py   첫 사용자 만들기·비밀번호 재설정
    └── tests/                conftest(SQLite 메모리) · test_health · test_auth
```

## 기능 하나 더하기

1. `backend/app/models/<x>.py` → `models/__init__.py` 에 등록 → `uv run alembic revision --autogenerate -m "<x>"` → 생성 파일 검토 → `corepack pnpm migrate`
2. `backend/app/schemas/<x>.py` · `backend/app/api/<x>.py`(prefix `/api/<x>`) → `main.py` 에 `include_router`
3. `src/lib/features/<x>/{api.js,index.js}` → `src/routes/(dashboard)/<x>/+page.svelte` → `Sidebar.svelte` 의 `items` 에 한 줄
