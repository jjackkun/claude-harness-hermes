# 스킬 진화 힌트가 사람이 쓰지 않은 글에서 나온다

> 출처: `docs/typesafe-jev/decision-points.md` "발견" 절 (2026-09-21 Jev 판단 지점 조사 중)
> 2026-09-22 백로그에서 착수 — 수정은 `docs/exec-plans/completed/2026-09-22-evolve-hint-false-positive.md`. 이 문서는 조사 기록으로 남긴다.

## 문제

세션이 끝날 때마다 `EVOLVE:<키워드>|<피드백>` 힌트가 나오는데, 이 힌트가 **사용자 피드백이 아닌 글**에서 만들어지고,
같은 힌트가 **턴마다 되풀이**된다. 진화는 고른 스킬을 **승인도 백업도 없이 덮어쓴다**(`scripts/hermes_dream_evolve.py:47`).

**이미 일어났다 (2026-09-21 확인).** 공장에서는 대상 스킬이 없어 빈손이었지만, 소우주 3곳에서
스킬 19개가 모두 96번 고쳐졌다. 재현 가능한 48번은 **전부** 사람이 쓰지 않은 글이 근거였다 — 아래 "소우주 실측".

## 소우주 실측 (2026-09-21, 읽기 전용)

방법: 설치 목록(`.installed-projects`) 12곳의 `.hermes/state.db` 를 `mode=ro` 로 열어 `skill_index.last_evolved_at` 을 세고,
`hooks.log` 의 `EVOLVED:` 줄 바로 뒤 `hook done: session=<id>` 로 세션을 찾은 뒤, 그 세션 대화 기록에
**현재 코드의** `load_transcript` + `extract_evolution_hints` 를 그대로 돌려 세션 끝 훅이 쓰는 앞 2개 힌트의 출처를 봤다.

| 소우주 | 고쳐진 스킬 | 진화 횟수 | 재현한 진화 | 그중 근거가 사람 글 | 대화 기록 없음 |
|---|---|---|---|---|---|
| zeroday-frontend | 12 | 76 | 31 | **0** | 45 |
| terminal-shipping | 5 | 17 | 17 | **0** | 0 |
| novel-bc | 2 | 3 | 0 | — | 3 |
| 나머지 6곳 (ai-create·jjackkun_bot·kis-trading·novel-ab·upbit-ai-trading·공장) | 0 | 0 | — | — | — |
| rim-kanban · rim-office · teulankkae | `.hermes/` 없음 — 헤르메스 미설치 | | | | |

- 경로: 96번 중 92번이 세션 끝 훅(`EVOLVED:` 다음 줄이 그 훅의 `hook done`), 4번이 드림 경로로 보인다.
- 예: terminal-shipping 세션 `64deea5f` 의 힌트 6개가 전부 비인간 글이었다. 앞 2개(훅이 쓰는 것)는 `svelte`·`postgres` 키워드로 잡힌 **다른 스킬의 본문**(`Base directory for this skill: …/layout-ui-doc-first`, `…/db-truth`)이었고, 그 세션 끝에 `write-ui-design-before-code.md` 가 v5 → v6 이 됐다.
- 가장 많이 고쳐진 것: zeroday-frontend `prettier-eslint-commit.md` v16 — 한 세션(`4adaae9f`, 메시지 3,398개) 안에서 v0 → v4 가 됐다. 24시간 쿨다운이 생긴 뒤에도 쿨다운마다 다시 고쳐진다.
- 되살릴 수 있다: 19개 모두 git 이력이 있고(버전 수 ≈ 커밋 수) 커밋 안 된 변경은 0건이다.
- **결과가 나빠졌다는 증거는 아직 없다.** terminal-shipping `write-ui-design-before-code.md` 의 커밋 7개를 읽었다(2026-09-21):
  최초 생성 1 · 본문 변경 2(`993a896e` 4+/3−, `1589855f` 5+/6−) · **버전 머리줄만 바뀐 것 4**.
  본문 변경은 "근거" 절을 구체화한 정도로, 오히려 조금 나아졌다. 근거로 쓰인 글(`layout-ui-doc-first` 스킬 본문)이 우연히 같은 주제였기 때문이다.
  즉 확인된 것은 **근거가 엉뚱하다**는 것까지이고, 드러난 손해는 의미 없는 버전 올림과 커밋의 누적이다.
- 한계: 재현은 현재 코드 기준이다. 추출 규칙이 그 사이 바뀌었다면 과거 힌트와 다를 수 있다. 대화 기록이 지워진 48번은 판단하지 않았다.

## 실측 (2026-09-21, 이 저장소)

| 무엇 | 값 | 출처 |
|---|---|---|
| 진화 빈손 기록 | `pip` 292회 · `docker` 290회 | `.hermes/hooks.log` `[hermes] 스킬 없음 — keyword:` |
| 실제로 진화된 스킬 | **0개** (`last_evolved_at` 이 있는 행 없음) | `.hermes/state.db` `skill_index` |
| `pip`·`docker` 키워드를 가진 스킬 | 0개 | 같은 표 |
| 대화 기록에서 `pip` 로 걸린 54건 중 가짜 | 35건 이상 — `pipeline` 19 · `pipefail` 5 · `R-pipe` 11 | `~/.claude/projects/-home-jjackkun-PROJECT-claude-harness-hermes/*.jsonl` 을 같은 정규식으로 재현 |
| `docker` 가 걸린 대화 기록 | 1개 — 그런데 빈손 기록은 290회 | 같은 파일 · hooks.log |
| 최근 힌트의 "피드백" 본문 | `Another Claude session sent a message: <agent-message …>` (서브에이전트 반환), `This session is being continued from a previous conversation…` (압축 요약), `Base directory for this skill: …` (스킬 본문) | `.hermes/hooks.log:3280-3287` |

## 원인 (코드로 확인)

힌트는 `scripts/hermes_save_session_patterns.py:171` `extract_evolution_hints` 가 만들고
`scripts/hermes-save-session.py:82` 가 내보내며 `scripts/hooks/claude-stop-retrospective.sh:89-104` 가 앞 2줄을 진화에 넘긴다.

1. **키워드에 단어 경계가 없다.** `(pnpm|npm|…|pip|docker|…)` 를 부분 문자열로 찾아 `pipeline`·`pipefail`·`R-pipe` 가 `pip` 가 된다.
2. **"사용자" 를 역할(`role == "user"`)로만 가른다.** 서브에이전트 반환·압축 요약·스킬 본문·훅 주입이 모두 user 역할로 들어온다. 피드백 단어(`수정`·`대신`·`아니라` …)는 이런 긴 글에 거의 늘 들어 있다.
3. **Stop 훅이 턴마다 대화 전체를 다시 읽는다(추정).** 같은 메시지 하나가 턴마다 힌트를 다시 낸다 — `docker` 1개 기록 대 290회가 이를 가리킨다. 한 세션에 한 번만 내는 장치가 있는지는 아직 확인하지 않았다.

## 후보

- 1 → 키워드에 단어 경계(`\b` 또는 앞뒤가 영숫자가 아닐 것)를 둔다.
- 2 → 사람이 친 메시지만 본다. 도구 결과·`isMeta`·`isCompactSummary`·`<`로 시작하는 주입·`Base directory for this skill:`·`Another Claude session sent a message:` 를 뺀다. 이 판별은 `hermes-search` 등 다른 경로에도 쓰이므로 한 곳(예: 세션 저장 쪽 공용 함수)에 둔다.
- 3 → 같은 (세션, 키워드) 힌트는 한 번만 낸다. 원인 3 을 먼저 실측으로 확인한 뒤 고른다.
- 진화 경로가 살아나기 전에 **덮어쓰기 전 백업 또는 사람 승인**을 둘지 함께 정한다(지금 한 번도 돈 적이 없으므로 지금이 가장 싸다).

## 착수 전 확인할 것

- 원인 3: Stop 훅 1회가 읽는 메시지 범위(대화 전체인가, 이번 턴인가). 메시지 3,398개 세션에서 v0 → v4 가 된 것은 "대화 전체" 를 가리킨다.
- ~~다른 소우주에서 진화가 돈 적이 있는가~~ → **있다** (위 "소우주 실측").
- **진화를 멈추거나 되돌리는 것이 목적이 아니다.** 진화는 사용자의 교정을 스킬에 반영하는 옳은 장치이고, 고칠 것은 그 입력이다.
  되돌리기는 결과가 나빠진 스킬이 실제로 나올 때만 그 스킬에 한해 사용자가 정한다(자동 되돌리기 금지 — 다른 프로젝트의 이력을 바꾸는 일).
- 착수 시 나머지 18개 스킬의 본문 변경만 골라(버전 머리줄만 바뀐 커밋 제외) 결과가 나빠진 것이 있는지 한 번 훑는다.
  나빠진 것이 없으면 이 항목의 우선순위는 "잡음 제거" 로 내려간다.

## 검증

- 이 저장소 대화 기록으로 고친 추출을 다시 돌려, `pipeline`·`pipefail`·`R-pipe` 발 `pip` 힌트가 0건이고 서브에이전트·압축 요약 발 힌트가 0건인지 본다.
- 사람이 실제로 친 피드백 메시지(예: "pip 말고 poetry 로") 한 건이 여전히 힌트로 잡히는지 본다 — 만든 예문이 아니라 기록에서 찾은 실제 메시지로.
