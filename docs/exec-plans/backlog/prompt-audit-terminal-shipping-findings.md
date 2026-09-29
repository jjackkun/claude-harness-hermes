# prompt-audit-terminal-shipping-findings — 소우주 감사가 찾은 공장 쪽 낡은·충돌 지시 8건

> 출처: terminal-shipping `docs/audits/2026-09-29-prompt-audit.md` (`/claude-api prompt-audit`, 대상 모델 Opus 5.5, 보고서 전용 실행).
> 소우주에서 고치면 다음 설치에 덮이고 `harness-doctor` 가 "불일치" 로 잡으므로 여기서 고쳐 전파한다.
> 소우주 소유분 5건(CLAUDE.md 블록 밖 수치·링크, `.hermes` 메타 발화 한 줄, 백업 스킬 3개)은 소우주에서 이미 고쳤다.

## 문제

설치된 규칙·훅·DS 블록이 서로, 또는 소우주 실물과 어긋난다. 모델은 어느 쪽이 지금 규칙인지 가릴 수 없고, 매 요청 주입되는 글이 커서 작은 모델이 핵심 규칙을 놓치는 정황이 있었다(같은 날 Sonnet 세션에서 확인 안 한 것을 확인한 것처럼 말한 일 3건 — 인과는 미확인).

## 발견 — 확신도 높은 순

| # | 공장 위치 | 무엇이 어긋나나 | 제안 |
|---|---|---|---|
| 1 | `assets/rules/harness/rules.md` `## R6. UI 작업 전 스킬 호출 필수` | 소우주의 `docs/design-docs/core-beliefs.md` R6 은 *접속 주소를 고르는 자기 규칙 금지* 이고 CLAUDE.md 도 그 뜻으로 인용한다 — 같은 번호가 두 규칙 | 공장 규칙 파일의 번호를 소우주 R 번호와 겹치지 않는 이름(예: `H-ui-skill`)으로. R 번호는 소우주 `core-beliefs.md` 만 쓴다 |
| 2 | `assets/rules/python/coding-style.md` (black · isort), `assets/rules/python/hooks.md` (black/ruff) | DS 블록(Python 절)은 `ruff check --fix` + `ruff format` (black/isort 대체), 게이트도 ruff | black·isort 줄을 ruff 로 바꾼다 |
| 3 | `assets/rules/web/coding-style.md` "Vue 컴포넌트는 아래 구조를 반드시 따른다" (Vue 9곳) | terminal-shipping 은 SvelteKit — `frontend/src` 에 `.vue` 0개. 강제 장치 설명(R-struct)도 Vue 전제 | 프레임워크 중립으로 쓰거나 프리셋별(svelte/vue)로 나눈다 |
| 4 | DS 블록 생성기 — 헤르메스 절의 `docs/hermes-cron-guide.md` · `hermes-loop-guide.md` · `hermes-sync-guide.md` | 셋 다 **공장** `docs/` 에만 있고 소우주에는 없다 → 소우주 CLAUDE.md 의 링크 셋이 깨진다 | 공장 주소(절대 경로나 저장소 URL)로 가리키거나, 설치 때 함께 복사한다 |
| 5 | `assets/hooks/doc_counts.py` → DS `COUNTS` 칸 | terminal-shipping 에 *스킬 6종 · 에이전트 12종* 이 찍혀 있는데 실물은 스킬 폴더 41개(백업 3 포함, 지금 38)·에이전트 16개 | 세는 대상(공장 설치분만인지, 전체인지)을 글에 적고 실물과 맞춘다 |
| 6 | `scripts/hermes-search.py` `_compose_injection` | 프로젝트 스킬의 frontmatter 가 `description: \|`(YAML 블록)이면 주입 결과가 `[헤르메스 규칙 — SKILL.md] \|` 한 글자. 이름표도 스킬 폴더 이름이 아니라 `SKILL.md` | YAML 로 읽어 블록 스칼라를 펼친다. 이름표는 폴더 이름 |
| 7 | `assets/hooks/claude-userpromptsubmit-reminders.sh` (+ `hermes-search.py` 주입) | 매 요청 `[Active Plans]` 16개(기한 지난 2026-08-29 항목 포함) · `[Backlog]` 38개 · `[Hermes 관련 규칙]` 3개(요청과 무관한 것 포함 — 모델 질문에 유니패스·입사 규칙) · `[Harness Reminders]` 가 반복된다. prompt-audit Group 1d "매 턴 재주입": 현재 모델은 한 번 말한 지시를 유지하고, 무관한 규칙은 행동 신호로 읽힌다 | 계획·백로그 목록은 세션 시작 1회로. 헤르메스 규칙은 관련도 문턱을 두고 문턱 밑이면 0개. 리마인더는 세션 시작 1회 |
| 8 | `assets/rules/web/design-quality.md` "Use `/impeccable` as the default skill for all frontend design work" · "Do not skip `/impeccable teach`" | 소우주는 화면을 `layout-ui-doc-first`(무엇을 정하나) → `shadcn-first`(무엇으로 만드나) 순으로 정했다 — 프론트 작업의 첫 스킬이 두 답 | 어느 쪽이 먼저인지 **사람이 정한다.** 정한 뒤 공장 규칙에 "프로젝트 스킬이 있으면 그것이 먼저" 한 줄 |

## 착수 조건

- 7(매 턴 주입 줄이기)은 **행동 가설**이다. terminal-shipping 의 `model-discipline-test` 로 주입 전후를 재고 판단한다 — 줄여서 규율이 무너지면 되돌린다.
- 1·2·3·4·5·6 은 사실 대조로 끝난다(파일·경로·수치). 바로 할 수 있다.
- 8 은 사람 결정이 먼저다.
