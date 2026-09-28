# 프롬프트 감사 — 세션에 로드되는 Claude Code 설정

> 작성일: 2026-09-28
> 목적: 이 프로젝트 세션에 로드되는 지시 파일에서 낡은 사실·모순·옛 모델용 문구를 찾아 제안 diff 로 남긴다.

## 개요

**전제 (Step 0)**

- **범위**
  - 이 프로젝트: `CLAUDE.md`, `.claude/rules/**/*.md`, `.claude/skills/*/SKILL.md`, `.claude/agents/*.md`
    - 심링크는 추적되는 원본 `assets/...` 기준으로 적는다.
  - 사용자 레벨: `~/.claude/CLAUDE.md`, `~/.claude/rules/**`, `~/.claude/skills/*`, `~/.claude/commands/*`, `~/.claude/agents/*`
- **없음**
  - 상위 디렉터리·관리 정책 CLAUDE.md, `CLAUDE.local.md`, `AGENTS.md`, `.claude/CLAUDE.md`, 명령(프로젝트), 출력 스타일
  - import 도 없다.
- **보고만**
  - 플러그인 11개가 제공하는 스킬·명령·에이전트
  - `~/.claude/skills/synced/*` (Anthropic 동기화 스킬)
- **읽지 않음**: settings 파일, `.mcp.json`, `~/.claude.json`
- **대상 모델**: Claude Opus 5.5 — 이 감사를 돌린 세션의 모델이다. 에이전트 frontmatter 는 `sonnet`/`opus`/`haiku` 별칭이라 버전이 고정되지 않았다.
- **패턴 표시**: 비Anthropic 제공자 흔적은 해당 없다. 이 저장소는 LLM 을 API 로 부르는 코드가 아니라 설정 저장소다.

**가장 영향이 큰 셋**

1. **사용자 규칙이 두 번 로드된다.**
   - `~/.claude/rules/common.backup-20260921-092049/` 는 `common/` 과 바이트 단위로 같다. 525줄이 매 세션 두 번 들어간다.
   - 아래 사용자 레벨 diff 를 `common/` 에 적용하는 순간 백업본이 **반대 규칙**이 된다. 그래서 diff 보다 먼저 옮겨야 한다.
2. **존재하지 않는 도구·에이전트·스크립트를 가리키는 지시가 여럿이다.**
   - 도구: `TodoWrite`, `Task(`
   - 에이전트: `security-reviewer`, `build-error-resolver`, `e2e-runner`, `rust/python/go-reviewer`
   - 스크립트: `suggest-compact.js`, `/verify`, `/instinct-*`, `scripts/codemaps`, `.00_docs/`
   - MCP 도구: `get_all_rules`·`search_nodes` 등
   - 모델은 적힌 대로 없는 것을 부르려 한다.
3. **프로젝트 `CLAUDE.md` 가 스스로와 어긋난다.**
   - 20행은 "게이트 16종 — 차단 10/경고 6", 70행(생성기 `doc_counts.py`)은 "20종 — 11/9" 다.
   - 3행은 "100 줄 이내" 라고 하지만 파일은 174줄이다. 설치기가 템플릿 35줄 뒤에 절을 붙이므로 모든 소우주에서 같은 상태다.

**그룹별 건수 (High·Medium 제안 / flag·Low)**

- **그룹 1 (옛 모델용 문구)**: 7 / 3
- **그룹 2 (낡은 사실·모순)**: 29 / 11
- **그룹 3 (도구 설명)**: 해당 없음. 이 저장소가 정의하는 API 도구가 없다.
- **그룹 4 (요청 설정·구조)**
  - 요청 코드: 해당 없음
  - 서브에이전트 명부 중복: 0. architect/-lite 와 planner/-lite 는 비용 단계를 의도적으로 나눈 것이다.

**제안 diff** (적용하지 않았다)

- 프로젝트: `docs/audits/2026-09-28-prompt-audit.patch` — 9파일 17 hunk, `git apply --check` 통과
- 사용자 레벨: `~/.claude/prompt-audit-2026-09-28.user.patch` — 14파일 23 hunk, `patch --dry-run` 통과
  - ⚠ 모든 프로젝트에 영향을 준다.

## 프로젝트 발견 (High → Low)

| ID | 위치 | 근거 | 패턴 | 왜 | 확신 | 조치 |
|---|---|---|---|---|---|---|
| P1 | `CLAUDE.md:20` | "게이트 16종 — 차단 10 / 경고 6" | 2 낡은 사실 | 같은 파일 70행(생성기 출력, 2026-09-21)이 20종 11/9 이다. 20행은 2026-09-09 손 작성 | High | rewrite — 숫자를 빼고 아래 절을 가리킴 |
| P2 | `CLAUDE.md:3`, `assets/docs-templates/CLAUDE.md.tmpl:3` | "100 줄 이내 유지" | 2 낡은 사실 | 설치기가 붙이는 절 때문에 174줄 | High | rewrite 두 곳 |
| P4 | `assets/skills/hermes-status/SKILL.md:30` | `count>=2` | 2 모순 | 결정화 기준은 3 (`scripts/hermes_dashboard_data.py:126`, CLAUDE.md "반복 3회+"). 대기 수가 부풀려진다 | High | rewrite `count>=3` |
| P5 | `assets/agents/docs-lookup.md:4` | `mcp__context7__*` | 2 도구 이름 | 이 세션의 실제 이름은 `mcp__plugin_context7_context7__*`. 허용 목록이 비어 Context7 을 못 부른다 | High | rewrite — 두 이름 모두 허용 |
| P6 | `assets/agents/doc-updater.md:3,18,23-29` | "Runs /update-codemaps and /update-docs", `npx tsx scripts/codemaps/generate.ts` | 2 낡은 사실 | 명령·스크립트가 없다. "Use PROACTIVELY" 는 과발동 부스터 | High | rewrite description, 명령 블록 remove |
| P7 | `assets/skills/harness-promote-rule/SKILL.md:126` | `.00_docs/harness-integration-plan.md` | 2 낡은 경로 | 파일 없음 | High | remove |
| P8 | `assets/skills/harness-reasoning-sandwich/SKILL.md:27` 와 `assets/agents/planner.md:5` | `model: "sonnet"` 와 `model: opus` | 2 파일 간 모순 | 호출 예시가 에이전트 정의를 덮어쓴다 | High | remove `model:` 줄 |
| P9 | 같은 스킬 `:39` 와 `:43` | "직접 구현하지 않는다" 와 "메인 세션에서 계획대로 구현한다" | 2 파일 안 모순 | 바로 이어진 두 문장이 반대다 | High | rewrite 39행 |
| P3 | `CLAUDE.md:8,31` | "(여기에 프로젝트의 한 줄 설명…)", "(여기에 dev/prod 포트…)" | 1d 정체성 자리표시 | 부트 맵의 두 칸이 빈 틀이다. 모델은 이 저장소가 공장이라는 맥락을 다른 곳에서 추론해야 한다 | Medium | rewrite — README 기준으로 채운 문안(검토 필요) |
| P10 | 같은 스킬 `:8`, `:65` | "TerminalBench 52.8% → 66.5%", "Haiku 금지 — 단일 Haiku 실패 사례" | 2 이력 서술 | 사건이 규칙의 권위 노릇을 한다. `doc-updater` 는 `model: haiku` 라 적용 범위가 모호하다 | Medium | 8행 수치 remove, 65행 rewrite |
| P11 | `assets/agents/tdd-guide.md:84-93` | "## v1.8 Eval-Driven TDD Addendum" | 1d 화석 | 출처 저장소의 버전 표식이다. 이 저장소 eval 도구와 무관 | Medium | remove |
| P12 | `assets/agents/tdd-guide.md:27,40,82` | `npm test`, `npm run test:coverage`, `skill: tdd-workflow` | 2 | 스택을 가정한다. `tdd-workflow` 는 lang 프리셋에만 있다 | Medium | rewrite |
| P13 | `.claude/skills/claude-harness-hermes-install/SKILL.md:65` | "Windows 환경의 모든 파일 수정 후" | 1d | 13행대로 2026-09-16 에 모든 OS 가 복사 설치로 바뀌었다. 67행이 이미 덮는다 | Medium | remove |
| P14 | `assets/rules/harness/examples/README.md` (규칙으로 로드됨) | "이것은 복사할 정답이 아니라 …출발점" | 2 | 복사용 예시집인데 `.claude/rules/harness` 심링크 아래라 매 세션 규칙으로 로드된다 | Medium | move — `assets/rules/` 밖으로 옮기고 설치 목록 수정. 파일 이동·설치기 변경이라 diff 에서 뺐다 |
| P15 | `assets/agents/performance-optimizer.md:62-367` | O(n²)→Map, React `useCallback`, DevTools 힙 스냅샷, "Every 100ms matters" | 1c 일반 지식 교재 | 448줄 대부분이 모델이 아는 내용이다. React 에 치우쳤다 | Medium | rewrite — 역할·측정 원칙·보고 형식만 남긴다. 무엇을 남길지 저자 확인이 필요해 diff 없음 |
| P16 | `assets/skills/run-to-the-end/SKILL.md:10-24` 외 | 대화 원문 인용, 🔴⚠️★ 강조 약 20곳 | 1a·2 | 과발동을 부르는 압박 문구 | Medium | rewrite — 10-24행을 "배경으로 돌리고 턴을 끝내면 기다림이 사용자에게 넘어간다." 한 줄로 줄이고 강조 기호를 걷어 낸다. diff 없음 |

### flag (제안 편집 없음)

| 위치 | 내용 | 결정할 것 |
|---|---|---|
| `assets/rules/harness/rules.md:5-21` (R1~R3), `assets/skills/harness-boundary-check/SKILL.md` | 이 저장소에 없는 `once/scheduled/realtime/`, `test_r1_boundary.py`, `docs_legacy/`, `backend/app/execution` 을 강제 장치로 적는다. `core-beliefs.md` 에는 R1~R4·R6·R7 이 없다. `examples/README.md` 의 "R 번호는 core-beliefs 와 맞춰라" 와 충돌한다 | 두 파일은 모든 harness 소우주로 배포되는 자산이다. R3(SDK 금지)은 금지 규칙이다. R1~R3 을 `examples/` 로 내리고 각 프로젝트 core-beliefs 로 옮길지 정해야 한다 |
| `assets/rules/harness/rules.md:69` 대 `docs/design-docs/core-beliefs.md` R-size | "파일 400줄 초과 금지" 대 "soft 400 경고, hard 500 차단" | 둘 다 최초 커밋 `6c2bff4` 라 선후를 가를 수 없다. 강제 장치(pre-commit)는 500 이다 |
| `rules.md` R7 대 `decision-ledger.md` §1 | "리뷰 여부를 질의" 대 "멈추고 묻는 경우는 넷뿐" | R7(2026-07-01)이 더 오래됐다. 다만 묻는 것이 멈추는 것인지는 해석 문제다 |
| `decision-ledger.md:14` | "사용자 전역 규칙 (… 자동 커밋 금지 등)" | `~/.claude/CLAUDE.md` 에는 그 규칙이 없다. 훅 알림 "자동 커밋 금지" 와 사용자 메모리 "끝난 작업은 묻지 말고 커밋" 이 서로 반대다 |
| `CLAUDE.md:71` | "스킬 6종 · 에이전트 12종" (실제 `.claude/skills` 17, `.claude/agents` 14) | 생성기 `doc_counts.py` 출력이다. 세는 대상(프리셋 자산)이 다를 수 있다 — Low |
| `assets/agents/code-reviewer.md:26` | `database-reviewer` | 실제 이름은 `claude-harness-hermes:database-reviewer` — Low |
| `assets/agents/refactor-cleaner.md:24-27` | `knip/depcheck/ts-prune` 만 있다 | Python/bash 저장소에서는 탐지가 빈다 — Low |
| `assets/agents/docs-lookup.md:24-46` | Step 1/2/3, "3 times total" | 도구 두 번 부르는 일에 쓴 절차 — Low |

## 사용자 레벨 발견 (`~/.claude` — ⚠ 모든 프로젝트에 영향)

| ID | 위치 | 근거 | 패턴 | 왜 | 확신 | 조치 |
|---|---|---|---|---|---|---|
| U1 | `rules/common.backup-20260921-092049/` | `diff -rq` 결과 `common/` 과 동일 | 2 중복·표류 | 두 번 로드된다. `common/` 을 고치면 모순이 된다 | High | move — `mv ~/.claude/rules/common.backup-20260921-092049 ~/.claude/rules-backup-20260921` (규칙 폴더 밖). **diff 적용 전에** |
| U2 | `rules/common/hooks.md:17-19` | "Use TodoWrite tool" | 2 도구 이름 | 현재 도구는 TaskCreate/TaskUpdate | High | rewrite |
| U4 | `rules/common/agents.md:13-15,18` | security-reviewer, build-error-resolver, e2e-runner, rust-reviewer | 2 | `~/.claude/agents`·프로젝트·플러그인 어디에도 없다 | High | remove 행 |
| U5 | `rules/common/code-review.md:31,48,50-52` | security/python/go/rust-reviewer | 2 | 위와 같다 (typescript-reviewer 는 플러그인에 있어 유지) | High | rewrite/remove |
| U6 | `rules/common/security.md:26` | "Use security-reviewer agent" | 2 | 없는 에이전트 | High | rewrite → code-reviewer 보안 관점 |
| U7 | `rules/common/performance.md:60` | "Use build-error-resolver agent" | 2 | 없는 에이전트 | High | remove 단계 |
| U14 | `skills/strategic-compact/SKILL.md:34,50,54,73,86,87,93,132` | `node …/suggest-compact.js`, TodoWrite, `~/.claude/memory/`, `continuous-learning` | 2 | 디스크에는 `suggest-compact.sh` 만 있다. 나머지 경로·도구·스킬도 없다 | High | rewrite |
| U15 | `skills/continuous-learning-v2/SKILL.md:201-221` | `/instinct-status`, `/evolve`, `/promote` … | 2 | 그런 명령이 없다. 실체는 `scripts/instinct-cli.py` 하위 명령(`status/evolve/export/import/promote/projects/prune`) | High | rewrite |
| U17 | `skills/coding-standards/SKILL.md:14-15` | `frontend-patterns`, `backend-patterns`, `api-design` | 2 | 세 스킬 모두 없다 | High | remove |
| U18 | `skills/verification-loop/SKILL.md:110-122` | "every 15 minutes", "Run: /verify" | 1b 주기 + 2 | `/verify` 가 없다. 고정 주기는 옛 모델용 안무 | High | remove 절 |
| U19 | `skills/search-first/SKILL.md:76,122-126` | `Task(subagent_type=…)`, "iterative-retrieval skill" | 2 | 도구 이름은 `Agent`, 스킬은 없다 | High | rewrite/remove |
| U20a | `commands/ss.md:14` | "WSL 경로로 변환: /mnt/{{{INPUT}}}" | 2 | 적힌 대로면 `/mnt/c:/…` 가 된다 | High | rewrite |
| U3 | `rules/common/hooks.md:15` | "`allowedTools` in `~/.claude.json`" | 2 | 권한 허용은 settings.json `permissions.allow` 에 둔다 | Medium | rewrite |
| U8 | `rules/common/performance.md:41-55` | "reserving up to 31,999 tokens", `MAX_THINKING_TOKENS`, "Ensure extended thinking is enabled" | 1b·1d | Opus 5.5 는 thinking 이 항상 켜져 있고 토큰 예산이 없다. 깊이 조절은 effort 로 한다 | Medium | rewrite |
| U9 | `rules/common/performance.md:5-26` | "Current generation (2026-09) … Opus 5 (`claude-opus-5`)" | 2 모델명 고정 | 이 세션은 이미 Opus 5.5 다. 버전을 박은 표는 다음 출시에 조용히 낡는다 | Medium | rewrite — 버전 대신 등급(haiku/sonnet/opus/fable)으로. 모델 선택 방침이 걸려 있어 diff 없음 |
| U10 | `rules/common/performance.md:28-39` | "Avoid last 20% of context window" | 1d 옛 컨텍스트 한도 | 자동 압축이 있다. 하네스도 "일찍 마무리할 필요 없다" 고 지시한다 | Medium | remove |
| U11 | `rules/common/development-workflow.md:12` | "Use Exa" | 2 | Exa 도구가 이 환경에 없다 | Medium | remove 줄 |
| U12 | `CLAUDE.md:241-289` (4부) | `get_all_rules`, `create_rule`, `search_nodes`, `add_observations`, "기억을 불러오는 중..." | 2 | 이 세션의 MCP(figma·context7·github·playwright·Claude Docs)에 해당 도구가 없다. 기억은 파일 기반 자동 메모리와 헤르메스가 맡는다 | Medium | remove. 특정 프로젝트에서 그 MCP 를 쓰면 그 프로젝트 CLAUDE.md 로 옮긴다. 범위가 커서 diff 없음 |
| U13 | `CLAUDE.md:10,12` | "(3초 멈춤)", "반드시 3초 멈추고 확인" | 1b 생각 유도문 | thinking 이 항상 켜져 있다. 체크리스트 내용은 유지한다 | Medium | rewrite |
| U14b | `skills/strategic-compact/SKILL.md:100-126` | "Trigger-Table Lazy Loading … 50%+", "`token-optimizer` MCP — 95%+" | 1d·2 | 스킬 본문은 원래 호출 때만 로드된다. 예시 스킬·MCP 는 없고 수치 근거도 없다 | Medium | remove 두 소절 |
| U20 | `commands/ss.md:11-13`, `commands/mss.md:16,18,28` | `{{{INPUT}}}` | 2 | Claude Code 명령은 `$ARGUMENTS` 를 치환한다 | Medium | rewrite |
| U21 | `skills/coding-standards/SKILL.md:35-38` 대 `:175-333` | "primary source 아님: React … API design" 인데 React·API 절이 있다 | 2 자기모순 | — | Medium | remove 두 절. 150줄 삭제라 diff 에서 뺐다 |
| U22 | `skills/coding-standards/SKILL.md:40-175,461-548` | KISS/DRY/YAGNI, 이름 짓기, AAA, 매직넘버 예제 | 1c | `rules/common/coding-style.md`·`testing.md` 와 겹치는 일반 교재다 | Medium | rewrite — 규칙 파일과 다른 내용만 남긴다. diff 없음 |
| U23 | `skills/coding-standards/SKILL.md:96-109` | "Immutability Pattern (CRITICAL)", "ALWAYS use spread", "NEVER mutate" | 1a | 이유 없는 대문자 강조가 몰려 있어 지역 배열 push 까지 막는다 | Medium | rewrite "공유 상태나 인자로 받은 객체는 복사해서 바꾼다(숨은 부작용 방지)" |
| U24 | `skills/continuous-learning-v2/SKILL.md:26-47,136,249-273,333-348` | "What's New in v2.1", `~/.claude/homunculus/`, "Backward Compatibility" | 2 이력·경로 | 버전 비교 서술이 권위 노릇을 한다. `homunculus` 경로가 없고 `config.json` 은 `"enabled": false` 다 | Medium | remove 버전 절 + "기본 비활성" 한 줄 add |
| U25 | `skills/continuous-learning-v2/agents/observer.md:139-143` 대 `:160` | "1-2 observations: 0.3" 대 "Only … 3+ observations" | 2 파일 안 모순 | 첫 행은 쓰일 수 없는 값이다 | Medium | rewrite "1-2회: 기록만" |

### flag (사용자 레벨)

| 위치 | 내용 | 결정할 것 |
|---|---|---|
| `CLAUDE.md:50,64-66,135,157,189` 대 `rules/common/coding-style.md:71-72,118` | "50줄 경고 / 100줄 즉시 분리 / 모듈 50줄 이하" 대 "soft 400 / hard 500". 프로젝트 하네스도 400/500 | `~/.claude` 는 git 이 아니라 선후를 모른다. 어느 한도를 전역으로 쓸지 정해야 한다 |
| `CLAUDE.md:44-47` 대 `rules/common/development-workflow.md:17-19` | "코드 한 줄 전 설계 문서 (5-10분)" 대 "Plan When Useful — 계획 문서는 세션을 넘길 때만" | 위와 같다 |
| `rules/common/git-workflow.md:19` | "백그라운드 세션: EnterWorktree 사용" | 이 백그라운드 세션의 하네스는 "제자리 작업, EnterWorktree 생략" 이라고 지시했다. 하네스 설정은 이 저장소 밖이다 |
| `rules/common/testing.md:5-12` | "Test Types (ALL required)", "MANDATORY workflow" | 문서만 바꾸는 작업에도 E2E 를 요구하는 것으로 읽힌다. 다만 방침 문제라 Low |
| `skills/verification-loop` `head -30`/`tail -20` | 출력 상한 때문에 오류 뒷부분이 잘린다 | Low |

## 플러그인·동기화 스킬 (보고만)

- `hookify` `commands/hookify.md:4,231`
  - `allowed-tools` 에 `Task`·`TodoWrite` 가 있고, "Use TodoWrite to track your progress" 라고 적혀 있다.
  - 둘 다 현재 이름이 아니다. 플러그인 쪽에서 고쳐야 한다.
- 나머지 플러그인 파일 30개와 `skills/synced/*`
  - 낡은 모델 ID, `TodoWrite`/`Task(`, 생각 유도문 grep 에 걸린 것이 없다.
  - 본문 정밀 감사는 하지 않았다.

## 적용 순서와 검증

1. U1 이동을 가장 먼저 한다. 백업본이 규칙 폴더에 남아 있으면 이후 diff 가 모순을 만든다.
2. 적용 명령
   - 프로젝트: `git apply docs/audits/2026-09-28-prompt-audit.patch`
     - 소우주로 퍼지는 자산(`assets/…`)이 섞여 있어 `update-all` 전파 대상이다.
   - 사용자 레벨: `cd ~/.claude && patch -p1 < prompt-audit-2026-09-28.user.patch`
3. 검증 (Step 7)
   - 사실 발견은 적용 뒤 경로·이름을 다시 확인하면 된다.
   - 행동 발견(U8, U13, P10, P16)은 한 번에 하나씩 적용하고 `harness-eval` 로 전후를 잰다.
