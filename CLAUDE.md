# CLAUDE.md — claude-harness-hermes

에이전트(Claude)용 **부트 섹터/맵**. 100 줄 이내 유지. 상세는 링크로 위임.
PDF 4~5쪽: "AGENTS.md 를 백과사전이 아닌 *목차* 로 취급한다."

## 프로젝트 한 줄

(여기에 프로젝트의 한 줄 설명. 도메인·생애주기·돈이 걸려 있는지 여부.)

## 먼저 읽어야 할 것

1. `ARCHITECTURE.md` — 도메인·패키지 레이어링 최상위 맵
2. `docs/design-docs/core-beliefs.md` — 검증 상태와 핵심 신념 (R1~Rn)
3. `docs/audits/` 의 최신 phase handoff 문서 — 현재 단계의 발견·결정

## 핵심 한 줄 룰

- 프로젝트 고유 불변 원칙(R1~Rn) 위반 발견 시 즉시 중단·보고. 우회 금지.
- 비자명한 작업은 계획 → 구현 → 검증 흐름. 깊은 리뷰는 위험 신호가 있을 때 승격.
- 강제 장치: `.git/hooks/pre-commit` (게이트 16종 — 차단 10 / 경고 6) + `.claude/settings.json` 훅.

## 작업 흐름

- 작업 전: 관련 `docs/design-docs/` 와 `docs/exec-plans/active/` 확인.
- 새 설계 결정: `docs/design-docs/` 에 새 파일 (이름은 결정 주제).
- 새 실행 계획: `docs/exec-plans/active/YYYY-MM-DD-slug.md`. 완료 시 `completed/` 로 이동.
- 감사·인시던트·핸드오프: `docs/audits/YYYY-MM-DD-slug.md`.

## 환경

(여기에 dev/prod 포트, 기동 명령, 핵심 환경변수.)

<!--===DS:BEGIN===-->
<!-- Managed by dev-setting/project-claude.sh. Edits inside this block are overwritten on re-run. -->

## ⚠️ 최우선 — 기억 말고 문서 먼저

사전학습으로 외운 지식으로 단정하지 말고, **이 문서와 아래 규칙·프로젝트 문서를 먼저 확인한 뒤** 판단·작업한다.
도구·라이브러리·프로젝트 규칙이 기억과 다를 수 있다. 충돌 시 항상 프로젝트의 실제 파일·규칙이 우선이다.

## 설치된 규칙·스킬 목차 (필요할 때 펼쳐 본다)

- **항상 적용되는 규칙**: `.claude/rules/` (및 `~/.claude/rules/common/`) — 코딩 스타일·보안·테스트·git·리뷰 등. 관련 작업 전 해당 규칙을 먼저 확인한다.
  - 이 프로젝트 룰셋: harness
- **스킬** (아래 발동 조건에 걸리면 호출한다. 작업 크기와 무관하다): `.claude/skills/`
  - harness-boundary-check — 실행 모드(once/scheduled/realtime) 간 경계 위반과 LLM SDK 직접 호출을 감지한다. Use when writing or reviewing code that touches execution…
  - harness-reasoning-sandwich — 비자명한 작업에 계획 → 구현 → 검증 흐름을 적용하고, 큰 변경일 때만 깊은 리뷰로 승격한다. Use when starting a new feature, multi-file change, or any…
  - harness-promote-rule — 반복되는 결함·리뷰 지적·경계 위반을 docs/design-docs/core-beliefs.md 의 R 룰로 승격하고, 대응하는 강제 장치(테스트·린터 규칙)를 스캐폴드한다. Use when the same…
  - structured-file-layout — Use when creating new files, planning features, or writing exec-plans — before any code is written, to ensure each file…
  - run-to-the-end — 오래 걸리는 명령을 돌리기 **직전에** 본다. 내가 "시험을 돌립니다" · "전체 검사를 돌리고" · "검증하겠습니다" · "실측하겠습니다" · "빌드하겠습니다" 라고 말하려는 자리, 또는 사용자가 "검사부터…
  - hermes-status — Show the overall Hermes engineering status. Use when the user types /hermes-status. Reads the project's .hermes/state.db…
  - hermes-crystallize — Crystallize repeated conversation patterns into reusable skill files. Triggered automatically by the Hermes learning…
  - hermes-recall — Recall past conversation context from Hermes rolling summaries. Use when the user types /hermes-recall [keyword]. Reads…
  - hermes-dream — Run Hermes dreaming — consolidate accumulated rolling summaries into crystallized/evolved skills and propose junk-skill…
  - hermes-loop — Goal-based autonomous loop for the CURRENT project. Trigger when the user types /hermes-loop (with or without a goal)…
  - mcp-builder — Guide for creating high-quality MCP (Model Context Protocol) servers that enable LLMs to interact with external services…
  - skill-creator — Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a…
- **에이전트** (검토·위임): `.claude/agents/` — architect-lite planner-lite architect planner code-reviewer silent-failure-hunter tdd-guide doc-updater docs-lookup performance-optimizer refactor-cleaner

## 하네스 엔지니어링 (PDF 방법론)

이 프로젝트는 claude-harness-hermes 의 `harness` 프리셋으로 강제 장치가 깔려 있다.
훅 실체는 `scripts/hooks/`, 커밋 게이트는 `.git/hooks/pre-commit`.

<!--===DS:COUNTS:BEGIN===-->
- 세션 중 실행 훅 **14종** + 훅이 공유하는 판정 모듈 **10개**
- git pre-commit 게이트 **16종** — 차단 10 / 경고 6
- 스킬 **5종** · 에이전트 **11종** · 테스트 **49개**
<!--===DS:COUNTS:END===-->

**세션 중**: 매 턴 규율 리마인더 · 커밋 전 리뷰 리마인드 + `--no-verify` 탐지 · 에이전트
dispatch 차단 · **R-iface** 새 파일 공개 심볼 8 이상 **차단**(쓰이기 전) · **R-declare** 새 코드
파일이 계획서 §4 에 선언됐는지 경고 · size 조기 경고(400/500) + 인터페이스 폭 증가 경고 ·
편집을 리뷰 빚으로 적립 · dead-file 경고 · **R-pipe** 리뷰어 dispatch 를 빚 청산으로 기록 ·
**R-mut** 주 1회 변이 점검(백그라운드) · **R-out** Bash 출력 바이트 실측 기록 ·
주간 문서 편차 점검 · 권한 프롬프트 피로도 감지

**커밋 시 차단**: R-size · R-fmt · R-lint · R-test · R-cx(임계 12, `.cxbaseline` 라쳇) · R-dep(`.deprc`) · R-struct · R-secret · R-plan
**커밋 시 경고**: R-cov(테스트가 한 줄도 실행 안 하는 파일) · R-pipe(리뷰 빚) · R-retro(회고 없이 완료) · R-acc(§2 목표 미검증) · R-plan-missing · R-plan-stale

**관측**: 모든 판정이 `.harness/gate-events.jsonl` 에 남는다 — 발화율 `python3 scripts/hooks/gate_report.py`.

**추론 샌드위치**: 비자명한 작업은 계획 → 구현 → 검증. 위반 발견 시 즉시 중단·보고, `--no-verify` 우회 금지.

**프로젝트 고유 불변 원칙(R1~Rn)은 `docs/design-docs/core-beliefs.md` 에 직접 정의한다.**
PDF 11쪽: "이 리포지터리의 특정 구조와 툴링에 따라 크게 달라지며, 유사한 투자 없이
일반화할 수 있다고 가정해서는 안 된다." 규율이 틀렸다면 근거를 `docs/audits/` 에 남기고 고친다.

## 작업 기록 시스템 (PDF 5~6쪽)

리포지터리의 지식 베이스는 `docs/` 디렉터리에 구조화되어 관리된다.
**핸드오프 메모가 아닌 리포지터리 안의 계획 문서가 세션 간 연속성의 원천이다.**

- `docs/exec-plans/backlog/` — 언젠가 할 작업 후보 (우선순위 미정)
- `docs/exec-plans/active/` — 진행 중인 작업 계획 (세션 시작 시 반드시 읽을 것)
- `docs/exec-plans/completed/` — 완료된 작업 (의사결정 로그 보존)
- `docs/design-docs/` — 설계 결정 + 불변 원칙(R 룰)
- `docs/audits/` — 조사·감사 기록

**강제 규칙:**
1. 비자명한 작업 시작 전 `docs/exec-plans/active/YYYY-MM-DD-<slug>.md` 작성 (템플릿: `docs/exec-plans/template.md`)
2. 작업 완료 시 회고(§8) 작성 후 `completed/`로 이동
3. 세션 시작 시 `active/` 에 문서가 있으면 먼저 읽고 이어감
4. 미래 작업 후보는 `backlog/`에 날짜 없이 `<slug>.md`로 보관
5. `.claude/memory/`의 핸드오프 파일 대신 `docs/exec-plans/`를 사용

## 헤르메스 엔지니어링 (Hermes Engineering)

이 프로젝트는 `hermes` 프리셋으로 자가 진화 러닝 루프가 활성화되어 있다.

**기억 구조:**
- `[project]/.hermes/state.db` — 프로젝트 전용 SQLite (세션 기억 + 스킬 인덱스)
- `~/.hermes/global.db` — 전역 SQLite (공통 패턴 + 사용자 성향)

**자동 동작 (Claude Code 세션 훅 기반 — Codex 세션에서는 미동작, 추후 버전업에서 지원 예정):**
- 세션 종료 시 러닝 루프: 저장 → 롤링 요약 → 결정화(반복 3회+) → 스킬 효용 상관·강등
- 결정화된 스킬은 `[project]/.hermes/skills/` 에 저장
- 세션 시작 시(startup/resume): 관련 스킬 자동 검색 주입 + 직전 세션 요약 회상 주입 + 하루 1회 드리밍 자동 실행(throttle 20h, 백그라운드)
- 작업 도중 Bash 가 터미널 실패(401·permission denied·Traceback·FAILED 등)를 내면 관련 스킬을 그 자리에서 주입 (세션당 최대 3회)

**슬래시 커맨드:**
- `/hermes-status` — 전체 스킬/규칙/세션 현황 확인
- `/hermes-crystallize` — 대기 패턴 즉시 결정화 (수동 실행)
- `/hermes-recall` — 직전 세션 요약 키워드 검색·회상
- `/hermes-dream` — 드리밍 결정화 수동 실행 (누적 요약 → 승격 + junk 스킬 정리 제안)

**자율 에이전트 (선택):**
- cron + `scripts/hermes-cron-run.sh` 로 매니저 에이전트 자동 실행 가능
- 설정 방법: `docs/hermes-cron-guide.md` 참고
- 테스트: `python3 scripts/hermes-manager.py --db .hermes/state.db --action start --projects <프로젝트명>`

**목표 기반 자율 루프:**
- 헤드리스: `scripts/hermes-loop-run.sh <프로젝트> "<목표>"` — 완료/안전캡까지 자율 반복
- 대화형: `/hermes-loop <목표>` — 현재 세션에서 반복 (파괴적 작업은 승인 게이트)
- 상태/중단: `python3 scripts/hermes-loop.py status` / `... stop <loop-id>`
- 재개: `scripts/hermes-loop-run.sh <프로젝트> --resume <loop-id>`
- 가이드: `docs/hermes-loop-guide.md`

**원칙:**
- 로컬 스킬 진화는 자동, 공통(claude-harness-hermes) 반영은 사용자 승인 후 PR
- AI가 공통 스킬을 자동으로 수정하는 것은 금지
- 파괴적 작업(삭제·force push)은 자율 에이전트도 절대 자동 실행하지 않는다

## MCP Server Development

- 새 MCP 서버 또는 기존 서버 확장 시 **mcp-builder 스킬 호출 필수**
- 도구 이름은 동사+명사로 구체적이게 (`create_issue`, `search_docs`)
- 도구 설명은 LLM 이 **언제 호출해야 할지** 를 결정하므로 트리거 조건을 명확히
- 입력 스키마는 JSON Schema 로 엄격하게. Optional 필드에도 description 필수
- 에러는 구조화된 오브젝트로 반환 (LLM 이 복구 가능하도록)
- 민감한 작업은 리소스/프롬프트 승인 패턴 활용

## Skill Development

- 새 스킬/기존 스킬 개선 작업 시 **skill-creator 스킬을 반드시 invoke**
- frontmatter 의 `description` 이 트리거 정확도를 결정한다 — 구체적 키워드 + 조건 명시
- 스킬 본문은 실제 호출됐을 때만 로드되므로 용량보다 **description 정확도** 에 투자
- 변경 후 skill-creator 의 평가/벤치마크 도구로 트리거 정확도 검증

<!--===DS:END===-->
