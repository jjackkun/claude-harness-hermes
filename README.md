# 하네스 + 헤르메스 엔지니어링 (Harness + Hermes Engineering)

`setup.sh` (대화형 UI) + `project-claude.sh` + `project-codex.sh` + `public-claude.sh` 로
Claude Code / Codex 의 스킬·에이전트·룰·훅·프로젝트 지침 파일을 일관되게 관리합니다.

- **하네스(Harness)**: 사람이 직접 만드는 규칙·가드레일 시스템 (CLAUDE.md, 훅, 스킬)
- **헤르메스(Hermes)**: 대화에서 반복 패턴을 학습해 스킬을 자동 생성·진화시키는 러닝 루프 (사용자 지적 + 테스트·빌드 실패·git 되돌림 같은 객관적 신호로 학습)

공통 프리셋과 자산은 공유하되, Claude 산출물과 Codex 산출물은 target별로 분리합니다.
자산은 git 리포지토리로 버전 관리되고, 새 기기에서는 `git clone` 한 번이면 환경을 복원할 수 있습니다.

> **Codex 지원 상태 (2026-07 기준):** 최초에는 Claude·Codex 를 번갈아 사용해 두 target 을 함께 지원했으나,
> 현재는 Claude Code 에 치우쳐 개발 중이며 Codex 경로는 **동결(frozen)** 상태입니다. 특히 헤르메스의
> 훅 기반 자동화(러닝 루프·세션 시작 드리밍)는 `claude` CLI 에 의존하므로 **Claude 세션 전용**입니다.
> Codex 인프라(`setup-codex.sh`·`lib/codex_*` 등)는 삭제하지 않고 보존하며, **추후 버전업에서 Codex 지원을 재개**할 예정입니다.

## 아키텍처

```
ai-dev-setting/                       ← 이 디렉터리 (private git repo 권장)
├── setup.sh                          ← 대화형 설치 UI (fzf, 카테고리별 스텝 선택)
├── setup-codex.sh                    ← Codex 전용 대화형 설치 wrapper
├── update-all.sh                     ← 등록된 프로젝트 전체 일괄 업데이트 + 전역 도구 체크
├── update-codex-all.sh               ← Codex 전용 전체 업데이트 wrapper
├── public-claude.sh                  ← 머신 전역 공통 설치 (Claude 전용, 선택)
├── project-claude.sh                 ← 프로젝트 설치 (매번)
├── project-codex.sh                  ← Codex 프로젝트 설치
├── uninstall.sh                      ← 설치물 안전 제거 (사용자 자산은 보존)
├── bin/                              ← 로컬 도구 바이너리 (fzf, serena-dash)
├── lib/
│   ├── common.sh                     ← 공통 함수 진입점 (모든 lib 로드)
│   ├── logging.sh                    ← log_info/warn/error 출력 헬퍼
│   ├── windows.sh                    ← Windows/WSL2 경로 감지 및 hook 래핑
│   ├── installers.sh                 ← 스킬·에이전트·룰·hook 설치 함수
│   ├── harness_installers.sh         ← 하네스 특화 설치 함수
│   ├── preset.sh                     ← 프리셋 로드·dedupe·권한 머지
│   ├── settings_gen.sh               ← settings.json / settings.local.json 생성 진입점
│   ├── claude_md_gen.sh              ← CLAUDE.md 마커 블록 생성·병합
│   ├── hermes_memory.sh              ← 헤르메스 DB 초기화·조회 셸 래퍼
│   ├── uninstall_helpers.sh          ← uninstall.sh 전용 안전 제거 헬퍼
│   ├── codex_installers.sh           ← Codex 전용 설치 함수
│   ├── codex_settings_gen.sh         ← Codex hooks.json 생성
│   ├── codex_md_gen.sh               ← AGENTS.md 생성
│   ├── generate_settings.py          ← settings.local.json (env 전용) 생성
│   ├── generate_settings_json.py     ← settings.json (hooks+permissions) 머지 생성
│   └── generate_codex_hooks.py       ← Codex hooks.json 생성 (Python)
├── presets/
│   ├── _common.conf                  ← public-claude.sh 가 사용
│   ├── lang/{python,node,java,flutter}.conf
│   ├── framework/{fastapi,svelte,vue,react,springboot}.conf
│   ├── database/{postgres,mysql,oracle,mongodb,redis}.conf
│   ├── build/{jpa,mybatis,maven,gradle}.conf
│   ├── permissions/{git-write,pm2}.conf  ← 추가 권한 화이트리스트
│   ├── tools/{terminal-paste-image}.conf
│   ├── workflow/{harness,hermes,mcp,skill-dev,serena}.conf
│   └── global/                           ← [global] 스텝: ~/.claude 전역 opt-in 스킬 (현재 비어있음)
├── scripts/
│   ├── hermes-init.py                ← 헤르메스 SQLite DB 초기화
│   ├── hermes-save-session.py        ← 세션 내용 DB 저장 + 패턴 집계 (session_id upsert, 사용자 지적 + 객관 실패 신호 감지)
│   ├── hermes-crystallize.py         ← 패턴 결정화 (claude -p 호출 + junk SKIP 게이트)
│   ├── hermes-increment.py           ← 패턴 카운트 증가 (결정화된 패턴 제외)
│   ├── hermes-search.py              ← FTS5 스킬 검색
│   ├── hermes-evolve-skill.py        ← 스킬 자가 진화
│   ├── hermes-index-skills.py        ← 하네스 스킬 인덱싱 (used_count 보존)
│   ├── hermes-cleanup.py             ← junk 패턴·중복 세션 정리 (기본 dry-run)
│   ├── hermes-summarize.py           ← 롤링 5슬롯 세션 요약 (델타만 Haiku 호출, 없으면 스킵)
│   ├── hermes-recall.py              ← 직전 세션 요약 회상 (--inject: 컨텍스트 주입 / --query: 검색)
│   ├── hermes-dream.py               ← 드리밍: 누적 요약 → 결정화 승격 + junk 스킬 삭제 제안
│   ├── hermes-correlate.py           ← 주입 스킬 ↔ 편집 경로 상관 (helpful/noop 집계)
│   ├── hermes-prune.py               ← 측정 신호 기반 스킬 강등·톰브스톤 (파일 삭제 안 함)
│   ├── hermes_redact.py              ← 저장·요약 경계 민감정보 비가역 마스킹 모듈
│   ├── hermes_skills.py              ← 스킬 DB 접근 공용 모듈
│   ├── hermes-manager.py             ← 자율 에이전트 매니저 프롬프트 조립
│   ├── hermes-message.py             ← 에이전트 간 메시지 버스 CLI
│   ├── hermes-cron-run.sh            ← cron 용 러너 (자율 매니저 start/check/end 액션)
│   ├── sync-plugins.sh               ← assets/agents ↔ plugins 동기화 (--check: CI 드리프트 검사)
│   ├── install-statusline.sh         ← 상태줄(이메일 | 모델 | 프로젝트) 머신 설치 (독립 실행)
│   └── install-fzf.sh                ← bin/fzf 로컬 설치
├── assets/                           ← 실제 스킬/에이전트/룰 본체
│   ├── skills/<skill>/SKILL.md
│   ├── agents/<agent>.md
│   ├── rules/<ruleset>/
│   └── hooks/                        ← 하네스/헤르메스 hook 스크립트 원본
├── plugins/ai-dev-setting/           ← 플러그인 번들 (agents 는 실파일 — symlink 금지)
├── tests/                            ← 테스트 (러너: tests/run-all.sh)
├── docs/
│   ├── exec-plans/{active,completed,backlog}/  ← 실행 계획 (+ template.md)
│   ├── audits/                       ← 감사 보고서
│   ├── design-docs/                  ← 설계 문서
│   ├── exec-plans-system.md
│   └── hermes-cron-guide.md          ← 자율 에이전트 cron 설정 가이드
└── templates/                        ← 신규 프로젝트용 파일 템플릿
    ├── CLAUDE.md.tpl
    ├── AGENTS.md.tpl
    └── global-claude.md.tpl
```

## 빠른 시작 (setup.sh)

```bash
# 1) 리포지토리 클론
git clone <repo-url> ~/PROJECT/ai-dev-setting

# 2) 대화형 UI로 프로젝트 설정
~/PROJECT/ai-dev-setting/setup.sh
```

`setup.sh` 를 실행하면:
1. 프로젝트 경로 입력 (Enter = 현재 폴더)
2. **[global] 스텝** — 모든 프로젝트 공통으로 `~/.claude` 에 한 번 깔리는 전역 opt-in 스킬 선택. 선택분은 `~/.claude/presets.global.lock` 에 기록되어 `update-all` 에도 유지됨. ESC = 변경 없음. (`presets/global/` 에 프리셋이 하나도 없으면 이 스텝은 자동으로 건너뜀)
3. 카테고리별 스텝 선택 (lang → framework → database → build → workflow → permissions → tools)
   - **Space**: 선택/해제, **Enter**: 다음 단계
3. 확인 후 target에 맞는 installer 자동 실행

> `fzf` 가 없으면 자동으로 최신 버전을 설치합니다.

### 머신 전역 도구 자동 설치

`setup.sh` (Claude 타겟) 실행 시 아래 도구들이 **미설치 시 자동으로 설치**됩니다:

| 도구 | 설명 |
|------|------|
| `uv` | Python 패키지 관리자 (Serena 의존성) |
| Session Report | `/session-report` 커맨드로 세션 요약 |
| Claude MD Management | `/claude-md` 커맨드로 CLAUDE.md 관리 |
| Hookify | PreToolUse/PostToolUse 훅 자동 연결 |
| Serena MCP | 코드 심볼 인덱싱으로 토큰 절감 (자동 백그라운드 동작) |

`setup.sh` (Codex 타겟) 실행 시:
- `serena-agent` 자동 설치
- `~/.codex/config.toml` 에 Serena MCP 서버 자동 등록

`update-all.sh` 실행 시에도 동일하게 미설치 항목을 감지해 자동 설치합니다.

## 전체 프로젝트 일괄 업데이트

ai-dev-setting 이 업데이트된 후 등록된 모든 프로젝트에 일괄 재적용:

```bash
# 직접 실행
~/PROJECT/ai-dev-setting/update-all.sh

# 또는 setup.sh 옵션으로
~/PROJECT/ai-dev-setting/setup.sh --update-all
```

`project-claude.sh` 를 실행할 때마다 해당 프로젝트가 머신 로컬 레지스트리(`.installed-projects`)에 자동 등록됩니다. `update-all` 은 이 목록을 읽어 각 프로젝트에 `project-claude.sh` 를 재실행합니다.

> `.installed-projects` 는 머신별 로컬 파일로 git에 포함되지 않습니다.

## 언인스톨

```bash
# fzf 멀티선택 (레지스트리에 등록된 프로젝트 목록에서 선택)
./uninstall.sh

# 직접 경로 지정 (상대경로 / ~ 허용)
./uninstall.sh ~/PROJECT/my-app

# 삭제 예정 항목만 미리 보기 (실제 삭제 없음)
./uninstall.sh --dry-run ~/PROJECT/my-app
```

**제거하는 것** (하네스가 설치한 것만):
- `CLAUDE.md` / `.gitignore` / `AGENTS.md` 의 관리 마커 블록
- `.claude/settings.json` 의 하네스 hooks 항목 (사용자 hook 은 보존)
- `.claude/settings.local.json`, `presets.lock` 등 관리 파일
- `.claude/{skills,agents,rules}` 의 하네스 symlink (사용자 실파일 보존)
- `scripts/hooks/`, `.git/hooks/pre-commit` (하네스 마커 확인 후), lint-configs, GC 워크플로
- `scripts/hermes-*.py` + `hermes-cron-run.sh`, Codex 설치물 (`.codex/` 등)
- `.installed-projects` 레지스트리 항목

**보존하는 것**: 사용자가 직접 추가한 hook·권한·스킬·룰·마커 밖 문서 내용 전부.
`.hermes/` (DB 포함) 는 별도 확인(y) 후에만 삭제합니다.

## 직접 실행

```bash
# 형식
project-claude.sh <PROJECT_PATH> <preset1> [preset2] ...

# 코인 그리드 (Python + FastAPI + PostgreSQL + Redis)
./project-claude.sh ~/PROJECT/coin python fastapi postgres redis

# Svelte 대시보드 (Node + Svelte + Postgres + 하네스)
./project-claude.sh ~/PROJECT/dashboard node svelte postgres harness

# 레거시 ERP (Java Spring Boot + MyBatis + Oracle + Maven)
./project-claude.sh ~/PROJECT/legacy-erp java springboot mybatis oracle maven

# 사용 가능한 프리셋 보기
./project-claude.sh --list

# 변경 없이 어떤 것이 설치될지 미리 보기
./project-claude.sh --dry-run ~/PROJECT/foo python fastapi postgres
```

## Codex target

Claude가 기본 target입니다. Codex 산출물을 설치하려면 `--target codex` 를 사용합니다.

```bash
# 대화형 설치
./setup.sh --target codex

# 같은 동작의 편의 wrapper
./setup-codex.sh

# Claude + Codex 동시 설치
./setup.sh --target both

# 직접 실행
./project-codex.sh ~/PROJECT/dashboard node svelte postgres harness

# Codex target 전체 업데이트
./update-all.sh --target codex

# 같은 동작의 편의 wrapper
./update-codex-all.sh
```

Codex target은 프로젝트에 다음을 생성합니다:

- `.codex/skills`, `.codex/agents`, `.codex/rules`
- `.codex/hooks.json` — Codex hook metadata
- `.agents/plugins/marketplace.json` — Codex repo-local marketplace entry
- `plugins/ai-dev-setting/` — Codex plugin 형태의 project-local bundle
- `scripts/codex-hooks/` — Codex 전용 hook scripts
- `scripts/codex-review.sh` — `codex review --uncommitted` 편의 wrapper
- `AGENTS.md` — Codex용 프로젝트 지침 파일

Claude 전용 `CLAUDE.md`, `.claude/settings.json` / `.claude/settings.local.json`, Claude hook scripts 는 Codex target에 설치하지 않습니다.

## 프리셋 목록

| 카테고리 | 프리셋 | 현재 제공 범위 |
|----------|--------|----------------|
| lang | python, node, java, flutter | 언어별 린터·포매터 훅 + CLAUDE.md 섹션 |
| framework | fastapi, svelte, vue, react, springboot | 프레임워크별 규칙·스킬 |
| database | postgres, mysql, oracle, mongodb, redis | **CLAUDE.md 가이드 섹션 + 권한** 위주. postgres 만 전용 스킬(`postgres-patterns`) 보유, 일부는 공용 자산(`database-migrations` 스킬, `database-reviewer` 에이전트)만 포함 — 나머지 전용 스킬/룰은 TODO |
| build | jpa, mybatis, maven, gradle | **CLAUDE.md 규칙 섹션** 위주. jpa 만 전용 스킬(`jpa-patterns`) 보유 — 나머지 전용 스킬/룰은 TODO |
| permissions | git-write, pm2 | 추가 권한 화이트리스트 |
| tools | terminal-paste-image | VSCode 익스텐션 등 부가 도구 |
| workflow | **harness**, **hermes**, mcp, skill-dev, serena | 작업 방식·도구 프리셋 |
| global | _(현재 없음)_ | **전역 opt-in 스킬 자리.** `[global]` 스텝에서 선택 시 프로젝트가 아닌 `~/.claude/skills/` 에 한 번 설치되어 모든 프로젝트에서 사용. `~/.claude/presets.global.lock` 에 기록되고 `update-all` 이 유지. `resolve_preset` 대상이 아니라 프로젝트 프리셋으로는 설치 불가. `presets/global/<name>.conf` 추가 시 자동 노출 |

### global 카테고리 (전역 opt-in)

`presets/global/*.conf` 는 프로젝트별이 아니라 **`~/.claude` 전역**에 설치되는 선택형 스킬입니다.
`_common.conf`(무조건 전역 베이스라인)과 달리 `setup.sh` 의 `[global]` 스텝에서 **선택**해야 깔립니다.

- 선택분은 `~/.claude/presets.global.lock` 에 기록 → `public-claude.sh` 가 설치 시 `_common.conf` 와 합쳐 적용
- `update-all.sh` 는 `public-claude.sh` 를 호출하므로 전역 선택이 자동 유지됨
- 빠른 적용: `bash public-claude.sh --skills-only --set-global "<이름들>"` (빈 문자열 = 전부 해제)

### 플러그인 프리셋 (PLUGINS)

프리셋 `.conf` 에 `PLUGINS+=(...)` / `PLUGIN_MARKETPLACES+=(...)` 를 넣으면 Claude Code
플러그인을 **user scope(전역)** 로 설치합니다 (예: `presets/tools/understand-anything.conf`).
스킬·룰·에이전트(프로젝트별 심볼릭)와 달리 플러그인은 한 번 깔면 모든 프로젝트에서 동작합니다.

- **설치**: 프리셋 선택 시 `claude plugin install <id> --scope user` (idempotent)
- **제거(참조추적)**: 선택을 해제하면, **다른 프로젝트도 더 이상 그 플러그인을 선택하지 않을 때만**
  `claude plugin uninstall` 로 전역에서 제거합니다. 어느 프로젝트가 어떤 플러그인을 요구하는지
  `<claude_dir>/.ai-dev-setting/preset-plugins.tsv` 에 `플러그인ID\t프로젝트경로` 로 기록(refcount)합니다.
- `setup.sh` 가 강제 설치하는 baseline official 플러그인(session-report, hookify, serena 등)은
  이 manifest 에 등록되지 않으므로 절대 제거 대상이 아닙니다.
- `--dry-run` 으로 설치/제거 계획(`would-install` / `would-remove`)을 미리 확인할 수 있습니다.

### serena 프리셋

`workflow/serena` 를 선택하면 CLAUDE.md 에 "Serena MCP 코드 검색·심볼 탐색 강제" 섹션이 자동 삽입됩니다.
Claude 가 매 턴 이 룰을 읽어 Grep 대신 Serena 도구(`find_symbol`, `search_for_pattern` 등)를 1순위로 사용하게 합니다.

- **선택 권장**: Python / TypeScript / Java / Dart 등 LSP 지원 언어 + 심볼이 많은 코드 헤비 프로젝트
- **선택 비추**: bash·markdown·문서 위주 리포 (LSP 가치 낮고 토큰만 소모)

Serena MCP 서버 자체는 `setup.sh` 가 머신 전역으로 자동 설치하므로 이 프리셋과 무관하게 항상 등록되어 있습니다.
이 프리셋은 단지 "Claude 가 Serena 를 실제로 쓰도록" 룰을 박는 역할입니다.

### harness 프리셋

`workflow/harness` 를 선택하면 프로젝트에 다음이 설치됩니다:

- **스킬**: `harness-boundary-check`, `harness-reasoning-sandwich`, `harness-promote-rule`, `structured-file-layout`
- **룰**: `harness` (코딩 규칙 전문)
- **훅 8종**: 매 턴 리마인더, bash 가드, 에이전트 가드, prettier 경고, size 경고, 리뷰 리마인더, dead-file 경고, stop 피로도 방지
- **CLAUDE.md 섹션**: 불변 규칙 체크리스트 + 작업 기록 시스템 안내 자동 삽입

### hermes 프리셋

`workflow/hermes` 를 선택하면 **자가 진화 러닝 루프**가 활성화됩니다. `harness` 프리셋과 함께 선택해야 합니다.

```bash
./project-claude.sh ~/PROJECT/my-app python fastapi postgres harness hermes
```

**설치되는 것:**

| 항목 | 내용 |
|------|------|
| SQLite DB | `[project]/.hermes/state.db` — 세션 기억 + 롤링 요약 + 스킬 인덱스 (WAL + busy_timeout) |
| 전역 DB | `~/.hermes/global.db` — 전역 공통 패턴 |
| 스크립트 18개 (python 17 + cron 러너 1) | `[project]/scripts/hermes-*.py`, `hermes_redact.py`, `hermes_skills.py` + cron 러너 `hermes-cron-run.sh` |
| Stop Hook | `claude-stop-retrospective.sh` — 세션 종료 시 러닝 루프 실행 (save → summarize → crystallize → correlate → prune) |
| SessionStart Hook | `claude-sessionstart-dream.sh` — startup/resume 세션 시작 시 하루 1회(throttle 20h) 드리밍 백그라운드 구동 (cron 대체). 끄기 `HERMES_DREAM_ON_SESSION_START=0` |
| UserPromptSubmit Hook | 관련 스킬 FTS5 검색 주입 + 직전 세션 요약 회상 주입(`hermes-recall --inject`) |
| 민감정보 마스킹 | `hermes_redact.py` — 저장·요약 경계에서 비밀을 `[REDACTED:TYPE]`로 비가역 치환 (원본 미보관) |
| 스킬 4종 | `hermes-status`, `hermes-crystallize`, `hermes-recall`, `hermes-dream` |
| CLAUDE.md 섹션 | 헤르메스 동작 안내 자동 삽입 |

**동작 흐름:**

```
사용자 입력
    ↓
UserPromptSubmit Hook
    ├─ FTS5 로 관련 스킬 검색 → 프롬프트에 자동 주입 (주입 원장에 기록)
    └─ hermes-recall.py --inject — 직전(다른) 세션 요약의 open/decisions 를 주입 (세션당 1회)
    ↓
Claude 작업
    ↓
세션 종료 (Stop Hook — save → summarize → crystallize → correlate → prune)
    ↓
① hermes-save-session.py — 대화 내용을 SQLite FTS5 에 저장 + 패턴 집계
    │  (저장 직전 hermes_redact 로 민감정보 마스킹)
    │  ├─ A 신호: 사용자 지적 키워드 ("자꾸", "또" 등 — UserPromptSubmit Hook)
    │  └─ B 신호: 테스트/빌드 실패·git 되돌림을 transcript 도구 블록에서 감지
    ↓
② hermes-summarize.py — 롤링 5슬롯 요약 갱신 (새 델타만 Haiku 호출, 델타 없으면 스킵)
    ↓
③ 동일 패턴 3회 이상? (A·B 공통 임계)
  → NO : 대기 (pattern_count 증가만)
  → YES: hermes-crystallize.py — claude -p 로 스킬 초안 생성
            ↓
          LLM 판단: 스킬 가치 없음(SKIP)? → crystallized=-1 마킹, 재시도 않음
            ↓
          [project]/.hermes/skills/<패턴>.md 스킬 파일 생성
            ↓
          이후 피드백 감지 시 hermes-evolve-skill.py — 스킬 자동 수정 + 버전 bump
    ↓
④ hermes-correlate.py — 이번 세션 주입 스킬 ↔ transcript 편집 경로 대조 → helpful/noop 집계
    ↓
⑤ hermes-prune.py — 측정 신호로 스킬 강등(active→demoted→tombstoned). 파일은 삭제 안 함(되돌림 가능)

[별도] hermes-dream.py (세션 시작 자동 — 하루 1회 + `/hermes-dream` 수동) — 누적 5슬롯 요약을 읽어
        반복된 결정/사실을 결정화로 승격하고, junk 스킬 삭제를 '제안'(실행은 --apply 게이트)
```

> **SKIP 게이트**: LLM이 "이 패턴은 스킬로 만들 가치가 없다"고 판단하면 `crystallized=-1` 로 마킹됩니다.
> 이 행은 재결정화 대상에서 영구 제외되므로, 동일 패턴이 반복 집계되어도 불필요한 `claude -p` 호출이 발생하지 않습니다.

> **B 신호 (객관적 실수 감지)**: 사용자가 입으로 지적하지 않아도, 세션 transcript 의 도구 실행 결과에서
> 테스트/빌드 실패(`test-fail:<파일>`)와 git 되돌림(`revert:<파일>`)을 감지해 같은 결정화 파이프라인에 넣습니다.
> 실패 위치(locus)별로 키를 만들어 같은 곳의 반복 실수만 누적되고, 탐지는 순수 정규식·채점은 별도 모델이 맡아
> 작업자가 자기 결과를 채점하는 함정을 피합니다. 합성 맥락 행(`role='tool'`)은 대화 패턴 분석을 오염시키지 않습니다.

**슬래시 커맨드:**
- `/hermes-status` — 스킬 수·세션 수·결정화 대기 패턴 현황 출력
- `/hermes-crystallize` — 수동으로 결정화 실행 (대기 패턴 즉시 처리)
- `/hermes-recall` — 직전 세션 요약을 키워드로 검색해 회상 (`hermes-recall.py --query`)
- `/hermes-dream` — 드리밍 결정화 수동 실행 (누적 요약 → 결정화 승격 + junk 스킬 정리 제안)

**동작 확인:**
```bash
# Stop Hook 실행 여부 + 결정화 로그 실시간 확인
tail -f [project]/.hermes/hooks.log
```

**자가 진화:**
- 사용자 피드백("이건 X 말고 Y로")을 감지하면 해당 스킬을 자동 수정 + 버전 bump
- 로컬 스킬은 자동 진화, ai-dev-setting 공통 스킬 변경은 사용자 승인 후 PR

**자율 에이전트 (선택):**
- cron + `claude --bg` 조합으로 매니저 에이전트를 주기적으로 실행 가능
- 설정 방법: `docs/hermes-cron-guide.md` 참고

**DB 유지보수:**

장기 사용 시 junk 패턴(불용어, 2글자 이하 한글 등)과 중복 세션이 쌓입니다. 주기적으로 정리하세요.

```bash
# 1) 삭제 예정 항목 미리 보기 (변경 없음)
python3 scripts/hermes-cleanup.py --db .hermes/state.db

# 2) 실제 적용 (junk 패턴·스킬 파일·중복 세션 삭제 + FTS5 optimize + VACUUM)
python3 scripts/hermes-cleanup.py --db .hermes/state.db --apply
```

> FTS5 인덱스는 행 삭제만으로는 용량이 회수되지 않습니다. `--apply` 실행 시 VACUUM 전에 FTS5 `optimize`를 자동으로 수행합니다.

**원칙:**
- AI가 공통 스킬을 자동으로 수정하는 것은 금지
- 파괴적 작업(삭제·force push)은 자율 에이전트도 절대 자동 실행하지 않음

## 동작 원리

### 자산은 심볼릭 링크 (Linux) / 복사 (Windows)
Linux/WSL2 에서는 `assets/` 자산을 **심볼릭 링크로** 프로젝트의 `.claude/` 에 연결합니다.
`ai-dev-setting` 리포지토리에서 자산을 수정하고 `git pull` 하면, **이 자산을 사용하는 모든 프로젝트가 자동으로 최신 내용을 받습니다.**

Windows NTFS 경로(`/mnt/c/...`)의 경우 NTFS 심볼릭 링크 제한으로 **복사** 방식을 사용합니다.
이 경우 자산 수정 후 `update-all.sh` 를 다시 실행해야 반영됩니다.

프리셋(어떤 자산을 쓸지) 자체를 바꿀 때만 `project-claude.sh` 를 다시 실행하세요.

### CLAUDE.md 는 마커 블록으로 안전 병합
프로젝트 루트의 `CLAUDE.md` 에 다음 마커가 자동 삽입됩니다:
```markdown
<!--===DS:BEGIN===-->
## ⚠️ 최우선 — 기억 말고 문서 먼저      ← (A) 가드
## 설치된 규칙·스킬 목차 (필요할 때 펼쳐 본다)  ← (B) 압축 목차
... 프리셋이 자동 생성한 섹션들 ...
<!--===DS:END===-->
```
이 블록 **바깥**에 직접 적은 내용은 절대 덮어쓰지 않습니다.

관리 블록 최상단에는 [`agent.md` 원리](docs/agent-md-vs-skill.md)를 반영한 두 서문이 항상 먼저 들어갑니다 (Codex `AGENTS.md` 도 동일, 경로만 `.codex/`):

- **(A) 가드** — "사전학습으로 외운 지식으로 단정하지 말고, 이 문서와 규칙·프로젝트 문서를 먼저 확인한 뒤 판단하라." 모델이 옛 기억으로 일하는 것을 막습니다.
- **(B) 압축 목차** — 이 프로젝트에 실제 설치된 룰셋·스킬·에이전트와 항상 적용되는 규칙 위치(`.claude/rules/`, `~/.claude/rules/common/`)를 나열합니다. 스킬을 "모델이 알아서 호출"(누락 위험)이 아니라 **항상 보이는 메모가 직접 가리키는** 방식으로 전환합니다.

두 서문은 `SKILLS`/`AGENTS`/`RULES` 배열에서 자동 생성되므로 프리셋을 바꿔 재설치하면 목차도 함께 갱신됩니다.

### .gitignore 에 머신 로컬 항목 자동 추가

설치 시 프로젝트의 `.gitignore` 에 커밋하면 안 되는 머신 로컬 파일을 자동으로 추가합니다.

| target | 추가 항목 |
|--------|-----------|
| claude | `.claude/settings.local.json` |
| codex  | `.codex/settings.local.json` |

마커 블록 `# >>> harness-agent-preset >>>` ~ `# <<< harness-agent-preset <<<` 사이에만 기록하므로
재실행해도 중복이 쌓이지 않고, 마커 밖의 사용자 항목은 보존됩니다.
`.gitignore` 가 없으면 새로 생성합니다.

### settings 는 두 파일로 분리 관리

| 파일 | git | 프리셋이 관리하는 키 |
|------|-----|---------------------|
| `.claude/settings.json` | **커밋 대상** | `hooks`, `permissions.allow`, `permissions.deny` |
| `.claude/settings.local.json` | gitignored | `env` 만 |

- **머지 정책 (settings.json)**: 프리셋 항목은 추가·갱신만 하고, **사용자가 직접 추가한 hook·권한 항목은 절대 삭제하지 않습니다.** 프리셋이 더 이상 제공하지 않게 된 항목도 자동 삭제되지 않으므로, 정리가 필요하면 수동으로 제거하거나 `uninstall.sh` 를 사용하세요.
- **settings.local.json**: `env` 외의 키는 전부 보존됩니다.
- 글로벌 `~/.claude/settings.json` 은 절대 건드리지 않습니다.

### 멱등성
같은 명령을 다시 실행해도 안전합니다. 새 프리셋을 추가하면 변경 사항만 반영되고, 제거된 프리셋의 자산은 다음 실행 때 정리됩니다.

## 새 기기에서 사용

```bash
# 1) 리포 클론
git clone <repo-url> ~/PROJECT/ai-dev-setting

# 2) 각 프로젝트 셋업 (대화형) — uv·플러그인·Serena 자동 설치 포함
cd ~/PROJECT/my-project
~/PROJECT/ai-dev-setting/setup.sh
```

두 명령으로 이전 기기와 **완전히 동일한 환경** 이 복원됩니다.

### Windows (Claude Code Desktop) 에서 사용

WSL2 에서 `setup.sh` 를 실행할 때 프로젝트 경로로 Windows 경로(`/mnt/c/...`)를 입력하면 자동으로 Windows 모드로 동작합니다:

- 심볼릭 링크 대신 **복사** 사용 (NTFS 호환)
- hook 명령을 `wsl bash "..."` 로 자동 래핑 (Windows Claude Code Desktop 에서 실행 가능)

## 새 프리셋 추가하기

`presets/<category>/<name>.conf` 파일을 만들고 다음 변수만 채우면 됩니다 (전부 `+=` 권장):

```bash
SKILLS+=(my-skill)
AGENTS+=(my-agent)
RULES+=(my-ruleset)
DENY_AGENTS+=(unwanted-agent)
ENV_VARS+=(MY_VAR=value)
POST_EDIT_HOOKS+=('command-to-run-after-each-edit')
STOP_HOOKS+=('command-to-run-at-stop')

read -r -d '' _section <<'EOF' || true
## 내 프레임워크
- 규칙 1
- 규칙 2
EOF
CLAUDE_MD_SECTIONS+=("$_section")
unset _section
```

새 **프로젝트별** 카테고리를 추가할 경우 `lib/preset.sh` 의 `resolve_preset` 카테고리 루프와 `setup.sh` 의 루프 모두에 카테고리 이름을 추가하세요.

> **전역(global) 스킬을 추가할 때는 다르다.** `presets/global/<name>.conf` 에 `SKILLS+=(...)` 만 넣으면 됩니다. `global` 은 `resolve_preset` 대상이 **아니며**(프로젝트 설치 차단), `setup.sh` 의 `[global]` 스텝과 `public-claude.sh` 의 `presets.global.lock` 처리가 자동으로 잡습니다. 즉 프로젝트 카테고리 루프에는 절대 추가하지 마세요.

## 테스트

```bash
# 전체 실행 (정적 검사 + 무결성 + 통합 테스트)
bash tests/run-all.sh

# 개별 실행
bash tests/preset-integrity-test.sh    # 프리셋 → assets 참조 무결성
bash tests/harness-hooks-smoke.sh      # 하네스 hook 차단/통과 경로
bash tests/hermes-pipeline-test.sh     # 헤르메스 러닝 루프 전체 (HOME 격리, claude 모킹)
bash tests/uninstall-roundtrip-test.sh # 설치→언인스톨 라운드트립 (사용자 자산 보존)
bash tests/windows-helpers-test.sh     # Windows 경로 헬퍼 단위 테스트
bash tests/windows-smoke.sh            # Windows 타깃 설치 (WSL2 + /mnt/c 필요, 아니면 SKIP)
```

`tests/run-all.sh` 는 추가로 전체 셸 스크립트 `bash -n` 문법 검사,
`scripts/*.py`·`lib/*.py` 의 `python3 -m py_compile`, `scripts/sync-plugins.sh --check`
(assets ↔ plugins 드리프트)를 수행합니다. 각 테스트는 서브셸로 실행되어 하나가
실패해도 나머지는 계속 실행되고 마지막에 통과/실패가 집계됩니다.

CI(`.github/workflows/ci.yml`)는 push/PR 마다 `SKIP_INTERACTIVE=1 bash tests/run-all.sh`
를 실행합니다. 테스트는 임시 디렉터리 + HOME 격리로 동작하며 실 DB(`~/.hermes`)와
`.installed-projects` 레지스트리를 오염시키지 않습니다 (cleanup trap 으로 원복).

## 의존성

- `bash` 4 이상
- `python3` (`generate_settings.py`, 헤르메스 스크립트 사용)
- `fzf` — `setup.sh` 실행 시 없으면 자동 설치
- `uv` — `setup.sh` 실행 시 없으면 자동 설치 (Serena MCP 의존성)
- `jq` — 헤르메스 Stop Hook 에서 transcript JSON 파싱 시 사용
- 프리셋이 사용하는 외부 도구들(ruff, prettier, mvn, gradlew 등)은 **있으면 사용하고 없으면 조용히 건너뜁니다**

## 주의

- `~/.claude/settings.json` 과 사용자가 직접 만든 `CLAUDE.md` 는 **절대 덮어쓰지 않습니다**.
- 프리셋이 참조하는 자산 이름이 `assets/` 에 없으면 WARN 만 출력하고 계속 진행합니다 (나중에 채우면 됩니다).
- 민감한 환경에서는 반드시 `--dry-run` 으로 미리 확인하세요.
