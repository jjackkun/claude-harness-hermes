# Claude Harness + Hermes Engineering (하네스 + 헤르메스 엔지니어링)

![License](https://img.shields.io/badge/license-MIT-green.svg)
![Python](https://img.shields.io/badge/python-3.x-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-89e051.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20WSL2-lightgrey.svg)
![Claude Code](https://img.shields.io/badge/Claude%20Code-compatible-8A2BE2.svg)

> **A preset-based installer & manager for Claude Code development environments — plus a self-evolving learning loop that improves your AI assistant from your own conversations.**

Two pillars:

- **Harness** — human-authored rules & guardrails (CLAUDE.md, hooks, skills). On install it injects a *"read the docs first, don't rely on memory"* guard plus a rules/skills index into CLAUDE.md, and safely merges into your existing file via managed marker blocks.
- **Hermes** — a self-evolving learning loop that learns from your conversations and turns recurring patterns into reusable skills.

**Hermes learning loop:**

- **Rolling summary** — distills every turn (ping-pong) into a 5-slot summary (decisions / facts / open / prefs / next)
- **Dreaming** — consolidates accumulated summaries "while you sleep" and crystallizes repeated knowledge into skills (auto, once per session start)
- **Skill crystallization & evolution** — hardens recurring patterns into skills and evolves them from your corrections
- **Recall injection** — restores the previous session's summary and relevant skills at the start of a new session
- **Objective-signal learning** — learns not only from your corrections but from test/build failures and git reverts
- **Redaction** — irreversibly masks secrets (tokens, passwords) at the storage/summary boundary

Assets are shared as Git-versioned presets; a single `git clone` restores your whole environment on a new machine.

```bash
git clone https://github.com/jjackkun/claude-harness-hermes ~/PROJECT/claude-harness-hermes
~/PROJECT/claude-harness-hermes/setup.sh
```

> **Note:** Hermes' hook-based automation depends on the `claude` CLI and is **Claude Code only** (Codex support is currently frozen — see below).

---

*English overview above · 한국어 상세 문서가 아래로 이어집니다.*

`setup.sh` (대화형 UI) + `project-claude.sh` + `project-codex.sh` + `public-claude.sh` 로
Claude Code / Codex 의 스킬·에이전트·룰·훅·프로젝트 지침 파일을 일관되게 관리합니다.

- **하네스(Harness)**: 사람이 직접 설계하는 규칙·가드레일 시스템 (CLAUDE.md·훅·스킬). 설치 시 CLAUDE.md 에 "기억 말고 문서 먼저" 가드와 규칙·스킬 목차를 주입하고, 사용자가 쓴 내용은 마커 블록으로 안전하게 병합합니다.
- **헤르메스(Hermes)**: 대화에서 배워 스킬을 스스로 만들고 진화시키는 **자가진화 러닝 루프**.

**헤르메스 러닝 루프의 핵심 기술:**
- **롤링 요약(rolling summary)** — 핑퐁(주고받기)마다 대화를 5슬롯(결정·사실·미해결·성향·다음)으로 증류
- **드리밍(dreaming)** — 누적된 롤링 요약을 "자면서" 통합해 반복된 지식을 스킬로 결정화 (세션 시작 시 하루 1회 자동)
- **스킬 결정화·진화** — 반복 패턴을 스킬로 굳히고, 사용자 정정을 반영해 기존 스킬을 진화
- **회상 주입(recall)** — 직전 세션 요약과 관련 스킬을 새 세션 시작에 자동으로 되살림
- **객관적 신호 학습** — 사용자 지적뿐 아니라 **테스트·빌드 실패·git 되돌림** 같은 객관 신호로 학습
- **민감정보 마스킹(redaction)** — 저장·요약 경계에서 비밀(토큰·비밀번호)을 비가역 치환

공통 프리셋과 자산은 공유하되, Claude 산출물과 Codex 산출물은 target별로 분리합니다.
자산은 git 리포지토리로 버전 관리되고, 새 기기에서는 `git clone` 한 번이면 환경을 복원할 수 있습니다.

> **Codex 지원 상태 (2026-07 기준):** 최초에는 Claude·Codex 를 번갈아 사용해 두 target 을 함께 지원했으나,
> 현재는 Claude Code 에 치우쳐 개발 중이며 Codex 경로는 **동결(frozen)** 상태입니다. 특히 헤르메스의
> 훅 기반 자동화(러닝 루프·세션 시작 드리밍)는 `claude` CLI 에 의존하므로 **Claude 세션 전용**입니다.
> Codex 인프라(`setup-codex.sh`·`lib/codex_*` 등)는 삭제하지 않고 보존하며, **추후 버전업에서 Codex 지원을 재개**할 예정입니다.

## 아키텍처

```
claude-harness-hermes/               ← 이 디렉터리 (private git repo 권장)
├── setup.sh                          ← 대화형 설치 UI (fzf, 카테고리별 스텝 선택)
├── setup-codex.sh                    ← Codex 전용 대화형 설치 wrapper
├── update-all.sh                     ← 등록된 프로젝트 전체 일괄 업데이트 + 전역 도구 체크
├── update-codex-all.sh               ← Codex 전용 전체 업데이트 wrapper
├── public-claude.sh                  ← 머신 전역 공통 설치 (Claude 전용, 선택)
├── project-claude.sh                 ← 프로젝트 설치 (매번)
├── project-codex.sh                  ← Codex 프로젝트 설치
├── uninstall.sh                      ← 설치물 안전 제거 (사용자 자산은 보존)
├── bin/                              ← 로컬 도구 바이너리 (fzf)
├── lib/
│   ├── common.sh                     ← 공통 함수 진입점 (모든 lib 로드)
│   ├── logging.sh                    ← log_info/warn/error 출력 헬퍼
│   ├── windows.sh                    ← Windows/WSL2 경로 감지 및 hook 래핑
│   ├── installers.sh                 ← 스킬·에이전트·룰·hook 설치 함수
│   ├── harness_installers.sh         ← 하네스 특화 설치 함수
│   ├── preset.sh                     ← 프리셋 로드·dedupe·권한 머지
│   ├── hook_inventory.sh             ← 훅 인벤토리 + 은퇴 훅 회수 (RETIRED_HOOK_SOURCES)
│   ├── permission_inventory.sh       ← 권한 인벤토리 + 은퇴 권한 회수 (RETIRED_PERMISSION_ALLOW)
│   ├── plugins.sh                    ← 플러그인 설치·refcount 기반 제거
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
│   ├── tools/{prettier,terminal-paste-image,understand-anything}.conf
│   ├── workflow/{harness,hermes,mcp,skill-dev}.conf
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
│   └── hooks/                        ← 하네스/헤르메스 hook 스크립트 원본 (실행 훅 + 공용 판정 모듈)
├── plugins/claude-harness-hermes/           ← 플러그인 번들 (agents 는 실파일 — symlink 금지)
├── lint-configs/                     ← 설치처에 배포하는 린트 설정 (harness-max-lines.config.js)
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
git clone <repo-url> ~/PROJECT/claude-harness-hermes

# 2) 대화형 UI로 프로젝트 설정
~/PROJECT/claude-harness-hermes/setup.sh
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
| Session Report | `/session-report` 커맨드로 세션 요약 |
| Claude MD Management | `/claude-md` 커맨드로 CLAUDE.md 관리 |
| Hookify | PreToolUse/PostToolUse 훅 자동 연결 |

`update-all.sh` 실행 시에도 동일하게 미설치 항목을 감지해 자동 설치합니다.

## 전체 프로젝트 일괄 업데이트

claude-harness-hermes 이 업데이트된 후 등록된 모든 프로젝트에 일괄 재적용:

```bash
# 직접 실행
~/PROJECT/claude-harness-hermes/update-all.sh

# 또는 setup.sh 옵션으로
~/PROJECT/claude-harness-hermes/setup.sh --update-all
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
- `plugins/claude-harness-hermes/` — Codex plugin 형태의 project-local bundle
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
| tools | prettier, terminal-paste-image, understand-anything | prettier 경고 훅(2026-08-04 harness 에서 분리), VSCode 익스텐션 등 부가 도구 |
| workflow | **harness**, **hermes**, mcp, skill-dev | 작업 방식·도구 프리셋 |
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
  `<claude_dir>/.claude-harness-hermes/preset-plugins.tsv` 에 `플러그인ID\t프로젝트경로` 로 기록(refcount)합니다.
- `setup.sh` 가 강제 설치하는 baseline official 플러그인(session-report, hookify 등)은
  이 manifest 에 등록되지 않으므로 절대 제거 대상이 아닙니다.
- `--dry-run` 으로 설치/제거 계획(`would-install` / `would-remove`)을 미리 확인할 수 있습니다.


### harness 프리셋

`workflow/harness` 를 선택하면 프로젝트에 다음이 설치됩니다:

- **스킬 5종**: `harness-boundary-check`, `harness-reasoning-sandwich`, `harness-promote-rule`, `structured-file-layout`, `run-to-the-end`
- **룰**: `harness` (코딩 규칙 전문)
- **에이전트 11종**: `architect-lite`, `planner-lite`, `architect`, `planner`, `code-reviewer`, `silent-failure-hunter`, `tdd-guide`, `doc-updater`, `docs-lookup`, `performance-optimizer`, `refactor-cleaner`

<!--===DS:COUNTS:BEGIN===-->
- 세션 중 실행 훅 **14종** + 훅이 공유하는 판정 모듈 **10개**
- git pre-commit 게이트 **16종** — 차단 10 / 경고 6
- 스킬 **5종** · 에이전트 **11종** · 테스트 **49개**
<!--===DS:COUNTS:END===-->

> 위 수치는 `assets/hooks/doc_counts.py` 가 소스에서 산출합니다. 손으로 고치지 마십시오 —
> `bash scripts/sync-doc-counts.sh` 로 갱신하고, 어긋난 채 커밋하면 **R-doc 이 막습니다**.

- **게이트 발화 기록**: `.harness/gate-events.jsonl`
- **CLAUDE.md 섹션**: 불변 규칙 체크리스트 + 작업 기록 시스템 안내 자동 삽입

> prettier 경고 훅은 2026-08-04 에 `presets/tools/prettier.conf` 로 분리되었습니다.
> harness 프리셋은 더 이상 이 훅을 설치하지 않습니다.

#### 세션 중 실행 훅

| 시점 | 훅 | 하는 일 |
|------|-----|---------|
| UserPromptSubmit | `claude-userpromptsubmit-reminders.sh` | 매 턴 규율 리마인더 + active 계획서·backlog 표시 |
| PreToolUse(Bash) | `claude-pretooluse-bash-guard.sh` | 커밋 전 리뷰 검토 리마인드 + `--no-verify` 탐지 |
| PreToolUse(Task\|Agent) | `claude-pretooluse-agent-guard.sh` | 잘못된 에이전트 dispatch 차단 |
| PreToolUse(Write) | `claude-pretooluse-iface-guard.sh` | **R-iface** — 새 파일의 공개 심볼이 8 이상이면 **차단** |
| PreToolUse(Write) | `claude-pretooluse-plan-declare.sh` | **R-declare** — 새 코드 파일이 계획서 §4 에 선언됐는지 경고 |
| PostToolUse(Edit) | `claude-posttooluse-size-warn.sh` | 400/500 줄 조기 경고 + 인터페이스 폭 증가 경고 |
| PostToolUse(Edit) | `claude-posttooluse-review-reminder.sh` | 코드 편집을 리뷰 빚으로 적립 (`.claude/.review-dirty`) |
| PostToolUse(Edit) | `claude-posttooluse-dead-file-warn.sh` | import 그래프에 없는 파일 편집 시 경고 |
| PostToolUse(Task\|Agent) | `claude-posttooluse-review-record.sh` | **R-pipe** — 리뷰어 dispatch 를 리뷰 빚 청산으로 기록 |
| SessionStart | `claude-sessionstart-mutation-probe.sh` | **R-mut** — 주 1회 변이 점검(백그라운드), 결과는 다음 세션에 보고 |
| SessionStart | `claude-sessionstart-doc-gardening.sh` | 주간 문서 편차 점검 (CI 미배선 환경에서도 동작, 7일 스로틀) |
| PostToolUse(Bash) | `claude-posttooluse-output-budget.sh` | **R-out** — 출력 바이트를 실측해 기록, 임계 초과 시에만 경고 |
| Stop | `claude-stop-perm-prompt-fatigue.sh` | 권한 프롬프트 피로도 감지 |

`iface-guard` 는 이 저장소 최초의 **하드 차단** PreToolUse 훅입니다. 임계 8 은 저장소 운영 코드
36개의 공개 심볼 분포에서 7이 최빈 고원이고 8부터 상위 사분위라는 실측에서 나왔습니다.
파일이 쓰이기 *전* 시점이라 오탐 비용이 거의 0 이므로 차단할 수 있습니다 — 같은 지표를 커밋
시점에 막으면 완성된 코드의 재구성을 요구해 우회가 상시화됩니다.

#### 판정 모듈 (훅이 아니라 훅·pre-commit 이 부르는 공용 코드)

| 모듈 | 축 | 내용 |
|------|-----|------|
| `iface_width.py` | R-iface | 인터페이스 폭의 **단일 정의**. `.py`/`.js`/`.ts`/`.svelte`/`.vue` 의 공개 심볼을 센다 |
| `complexity.py` | R-cx | 순환 복잡도 계산 (`--report` 로 함수별 출력) |
| `depcheck.py` | R-dep | `.deprc` 계약 기반 tier 역전·순환·금지 경계 검사 |
| `coverage_probe.py` | R-cov | 표준 라이브러리 `trace` 기반 줄 커버리지 (외부 패키지 의존 0) |
| `plan_state.py` | R-plan/R-acc/R-retro | 계획서 §2 목표·§8 회고 파싱 |
| `gate_event.py` | 관측 | 게이트 판정 1건을 JSONL 에 append (**종료코드 항상 0**) |
| `gate_emit.sh` | 관측 | 셸 훅에서 `gate_event.py` 를 부르는 얇은 래퍼 |
| `gate_report.py` | 관측 | 룰별 기회·통과·경고·차단·우회·발화율 집계 |
| `doc-gardening-drift.sh` | 문서 | 계획서가 코드를 따라오는지 편차 탐지 (주간 가드닝이 호출) |

`iface_width.py` 를 모듈로 뺀 이유: 폭을 재는 곳이 둘(생성 시점 차단 / 편집 시점 델타 경고)이라
각자 세다가 어긋났습니다. 후자는 `^export ` grep 이라 **Svelte 에서 한 번도 발화할 수 없었습니다**
(실측 — Svelte 200개 표본 중 `^export ` 0개, `$props()` 177개). 정의를 하나로 둡니다.

`coverage_probe.py` 와 `complexity.py` 가 외부 패키지(coverage.py, radon)를 쓰지 않는 이유:
하네스는 여러 프로젝트에 설치되는 도구이고, 각 프로젝트에 패키지 설치를 요구하면 **설치 실패가
곧 게이트 침묵**이 됩니다. 실제로 R-test 가 그 상태로 몇 달간 통과하고 있었습니다.

#### git pre-commit 게이트

`HARNESS_PRE_COMMIT=1` 이 `.git/hooks/pre-commit` 을 배치합니다.
(README 구버전의 "4단 검사" 는 R-size/R-fmt/R-lint/R-test 만 있던 시절의 표현입니다.)

**차단** — 하나라도 걸리면 커밋이 서지 않습니다:

| 게이트 | 검사 |
|--------|------|
| R-size | 파일 줄 수 한도 (`.py .js .ts .svelte .vue` 등, SFC 포함) |
| R-fmt | `prettier --check` (하네스 생성물은 대상에서 제외) |
| R-lint | `eslint --max-warnings 0` |
| R-test | `pytest` (테스트 0개면 통과가 아니라 실패로 본다) |
| R-cx | 순환 복잡도 **임계 12**, `.cxbaseline` **라쳇** — 나빠질 때만 차단 |
| R-dep | `.deprc` 의존 계약 — tier 역전·순환·금지 경계 |
| R-struct | 컴포넌트 폴더/배럴 규칙 |
| R-secret | 자격증명·개인정보 커밋 차단 |
| R-plan | 완료된 계획서가 `active/` 에 남아 있는지 |

**경고** — 알리되 막지 않습니다:

| 게이트 | 검사 | 막지 않는 이유 |
|--------|------|----------------|
| R-cov | 어떤 테스트도 실행하지 않는 파일을 고치는가 | 임계 없는 이분 판정, 기존 부채가 즉시 전부 걸린다 |
| R-pipe | 리뷰 빚을 안은 채 커밋하는가 | 훅은 "리뷰어를 불렀다"만 알 뿐 "리뷰가 유효했다"는 못 본다 |
| R-retro | `completed/` 로 옮긴 계획서에 §8 회고가 있는가 | 회고 유무는 형식이지 정확성이 아니다 |
| R-acc | §2 목표에 검증 명령이 있는가 / 미완 목표를 남긴 채 완료 처리하는가 | 위와 같음 |
| R-plan-missing | 코드를 고치는데 계획서가 있는가 | 스크래치·긴급 수정까지 막으면 우회가 상시화된다 |
| R-plan-stale | 코드는 바뀌었는데 계획서가 따라왔는가 | 위와 같음 |

임계 12 의 근거: 저장소 함수 295개의 복잡도 분포가 `11:11개 → 12:4개` 로 급락합니다.
그 절벽에 임계를 놓았습니다. 임계 8 이면 68개(23%), 6 이면 101개(34%) 가 걸려 과발화합니다.

#### 베이스라인 라쳇 — 남의 코드로 남을 막지 않는다

R-cx 를 임계 12 로 일괄 적용하면 이 저장소만 해도 파일 37개 중 16개(43%)가 즉시 막힙니다.
그 상태로 켜면 게이트를 끄거나 `--no-verify` 로 우회하는 것이 정상 작업 흐름이 됩니다.

- `.cxbaseline` — 설치 시점에 **그 프로젝트의 기존 부채를 동결**합니다. 값은 내려가기만 하고,
  나빠지면 차단합니다.
- 하네스는 **자기가 배포한 파일에 한해서만** 자기 베이스라인 기록을 프로젝트로 함께 보냅니다.
  배포한 코드의 복잡도를 설치 대상 프로젝트가 떠안지 않게 하기 위함입니다.
- `.covbaseline` — R-cov 도 같은 방식으로 기존 미커버 파일을 동결합니다.

#### 게이트 발화 기록 (게이트 텔레메트리)

R 룰 다수가 Provisional("발화율 관측 중") 상태였는데 **발화를 기록하는 코드가 없었습니다.**
승격·강등 판단의 입력을 만드는 것이 이 축입니다.

```bash
# 룰별 발화율 집계
python3 scripts/hooks/gate_report.py
```

```
룰        기회  통과  경고  차단  우회  건너뜀  발화율
-------  --  --  --  --  --  ---  ------
R-iface  1   0   0   1   0   0    100.0%
```

- 기록 위치: `.harness/gate-events.jsonl` (한 줄 1 판정: `ts rule verdict stage path detail`)
- `verdict` 는 `pass` / `warn` / `block` / `bypass` / `skipped`
- **`gate_event.py` 의 종료코드는 항상 0 입니다.** 관측 장치가 게이트를 죽이면 안 됩니다.
- `gate_event.py`·`gate_emit.sh` 가 빠지면 계장된 훅들이 emitter 를 못 찾아 **조용히 관측만
  꺼집니다** — 훅은 계속 동작하므로 아무도 눈치채지 못합니다. 반드시 함께 배포됩니다.

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
- 로컬 스킬은 자동 진화, claude-harness-hermes 공통 스킬 변경은 사용자 승인 후 PR

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
`claude-harness-hermes` 리포지토리에서 자산을 수정하고 `git pull` 하면, **이 자산을 사용하는 모든 프로젝트가 자동으로 최신 내용을 받습니다.**

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

- **머지 정책 (settings.json)**: **사용자가 직접 추가한 hook·권한 항목은 절대 삭제하지 않습니다.** 하네스가 배포한 항목(hook 등록, `permissions.allow`, `permissions.deny` 의 `Agent(...)`)은 **소유권 동기화** 대상이라, 프리셋이 더 이상 제공하지 않으면 다음 실행에서 자동으로 걷힙니다. 소유 판별 기준은 `lib/hook_inventory.sh` 와 `lib/permission_inventory.sh` 입니다.
- **settings.local.json**: `env` 외의 키는 전부 보존됩니다.
- 글로벌 `~/.claude/settings.json` 은 절대 건드리지 않습니다.

### 멱등성
같은 명령을 다시 실행해도 안전합니다. 새 프리셋을 추가하면 변경 사항만 반영되고, 제거된 프리셋의 자산은 다음 실행 때 정리됩니다.

## 새 기기에서 사용

```bash
# 1) 리포 클론
git clone <repo-url> ~/PROJECT/claude-harness-hermes

# 2) 각 프로젝트 셋업 (대화형) — 플러그인 자동 설치 포함
cd ~/PROJECT/my-project
~/PROJECT/claude-harness-hermes/setup.sh
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

## 프리셋 배포 중단하기

**`.conf` 를 먼저 지우면 안 됩니다.** 소유 판별이 `presets/**/*.conf` 와 `assets/hooks/` 스캔에 의존하므로, 파일을 지우는 순간 그 프리셋이 남긴 hook·권한이 **"하네스 것"이라는 증거가 사라져** 이미 설치된 프로젝트에서 영영 걷어낼 수 없게 됩니다. 게다가 설치본의 `.claude/presets.lock` 에는 이름이 남아 있어, 그 프로젝트는 이후 **모든 하네스 업데이트를 받지 못합니다.**

순서를 지키세요:

```bash
# 1) 은퇴 등재 — .conf 를 지우기 전에 반드시 먼저
#    lib/permission_inventory.sh : RETIRED_PERMISSION_ALLOW 에 allow 항목
#    lib/hook_inventory.sh       : RETIRED_HOOK_SOURCES 에 hook 파일명

# 2) 설치본에서 회수가 끝난 것을 확인
bash update-all.sh

# 3) 그 다음에 .conf 와 회수 코드를 삭제
git rm presets/<category>/<name>.conf
```

`presets.lock` 에 남은 유령 항목은 `update-all.sh` 가 경고와 함께 자동으로 걷어내므로 수동 정리가 필요 없습니다.

> 2026-08-21 `serena` 제거가 이 순서를 어겨 11개 프로젝트 중 6곳의 업데이트가 막히고 죽은 권한 184건이 고립됐습니다. 경위는 `docs/superpowers/specs/2026-08-21-preset-retirement-ownership-design.md` 에 있습니다.

## 테스트

```bash
# 전체 실행 (정적 검사 + 무결성 + 통합 테스트 43개)
bash tests/run-all.sh

# 특정 테스트만 건너뛰기
SKIP_TESTS=windows-smoke.sh,hermes-loop-test.sh bash tests/run-all.sh
```

`tests/` 에는 테스트 파일 **43개**가 있고 `run-all.sh` 가 전부 호출합니다. 축별로:

| 축 | 테스트 |
|----|--------|
| 설치·무결성 | `preset-integrity-test.sh` (프리셋 → assets 참조), `update-all-roundtrip-test.sh`, `uninstall-roundtrip-test.sh`, `hook-prune-test.sh`, `memory-symlink-roundtrip-test.sh`, `claude-md-skill-index-test.sh` |
| 게이트 (R 룰) | `iface-gate-test.sh`, `plan-declare-gate-test.sh`, `complexity-gate-test.sh`, `cx-baseline-distribution-test.sh`, `dep-contract-test.sh`, `pipe-gate-test.sh`, `struct-barrel-test.sh`, `coverage-probe-test.sh`, `plan-state-test.sh`, `r5-detection-test.sh` |
| 변이 점검 (R-mut) | `mutation-probe-test.sh`, `mutation-trigger-test.sh` |
| 게이트 텔레메트리 | `gate-event-test.sh`, `gate-report-test.sh`, `gate-instrumentation-test.sh`, `gate-precommit-instrumentation-test.sh` |
| 보안·마스킹 | `hermes-redact-test.sh`, `hermes-redact-boundary-test.sh`, `hermes-secret-masking-test.sh`, `check-secrets-answerkey-test.sh`, `check-secrets-code-expr-test.sh` |
| 헤르메스 러닝 루프 | `hermes-pipeline-test.sh`, `hermes-loop-test.sh`, `hermes-dream-test.sh`, `hermes-crystallize-naming-test.sh`, `hermes-cleanup-lock-test.sh`, `hermes-recall-measurement-test.sh`, `hermes-recall-history-search-test.sh`, `hermes-history-export-test.sh`, `hermes-lifecycle-test.sh`, `hermes-lifecycle-portability-test.sh`, `hermes-mesh-consume-test.sh`, `hermes-mesh-gate-test.sh` |
| 문서 가드닝 | `doc-gardening-drift-test.sh` |
| 훅 동작 | `harness-hooks-smoke.sh` |
| Windows | `windows-helpers-test.sh`, `windows-smoke.sh` (WSL2 + `/mnt/c` 필요, 아니면 SKIP) |

`tests/run-all.sh` 는 추가로 전체 셸 스크립트 `bash -n` 문법 검사,
`scripts/*.py`·`lib/*.py` 의 `python3 -m py_compile`, `scripts/sync-plugins.sh --check`
(assets ↔ plugins 드리프트)를 수행합니다. 각 테스트는 서브셸로 실행되어 하나가
실패해도 나머지는 계속 실행되고 마지막에 통과/실패가 집계됩니다.

**게이트 테스트는 "통과"만 보지 않습니다.** 가짜 위반을 일부러 만들어 게이트가 *실제로*
차단하는지 확인합니다 — 통과만 확인하는 검증은 게이트가 조용히 꺼진 것을 못 잡습니다
(`harness-hooks-smoke.sh` 가 실제로 그 상태였습니다).

CI(`.github/workflows/ci.yml`)는 push/PR 마다 `SKIP_INTERACTIVE=1 bash tests/run-all.sh`
를 실행합니다. 테스트는 임시 디렉터리 + HOME 격리로 동작하며 실 DB(`~/.hermes`)와
`.installed-projects` 레지스트리를 오염시키지 않습니다 (cleanup trap 으로 원복).

## 의존성

- `bash` 4 이상
- `python3` (`generate_settings.py`, 헤르메스 스크립트 사용)
- `fzf` — `setup.sh` 실행 시 없으면 자동 설치
- `jq` — 헤르메스 Stop Hook 에서 transcript JSON 파싱 시 사용
- 프리셋이 사용하는 외부 도구들(ruff, prettier, mvn, gradlew 등)은 **있으면 사용하고 없으면 조용히 건너뜁니다**

## 주의

- `~/.claude/settings.json` 과 사용자가 직접 만든 `CLAUDE.md` 는 **절대 덮어쓰지 않습니다**.
- 프리셋이 참조하는 자산 이름이 `assets/` 에 없으면 WARN 만 출력하고 계속 진행합니다 (나중에 채우면 됩니다).
- 민감한 환경에서는 반드시 `--dry-run` 으로 미리 확인하세요.
