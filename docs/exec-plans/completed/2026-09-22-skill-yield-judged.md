# 2026-09-22-skill-yield-judged — 스킬 도움률을 "판정된 것" 기준으로, 대시보드 스킬 이름을 폴더 이름으로

> 사용자(2026-09-22): 대시보드 "주입 상위" 에 `SKILL.md` 만 보여 "누구 어디 무슨 스킬이야" — 확인 중 도움률 자체가 틀린 것을 찾았다. "진행하자".

## 1. 동기 (Why)

- `skill_injection.correlated` 는 **"판정을 마쳤다"** 표시다 — 도움이든 헛주입이든 판정하면 1 이 된다(`hermes-correlate.py:124`).
  그런데 대시보드와 `hermes_skill_yield.low_yield_skills`(= `hermes-cleanup` 의 강등 기준)는 이것을 **도움**으로 셌다.
  그래서 "도움률" 은 실제로 **판정 비율**이었다.
- 실측: `asset-preset-distribution-pattern` 주입 424 · 판정 17 · 판정 17 전부 도움 → 옛 도움률 4.1% 로 **강등 후보**.
  11곳 전체에서 옛 기준 강등 후보 6개 중 **5개가 도움 기록이 있는 스킬**(zeroday 3 · terminal-shipping 1 · 공장 1).
  `/hermes-dream apply` 한 번이면 지워졌다. 지금까지 이 결함으로 지워진 스킬은 없다(자동 드리밍은 제안만).
- 대시보드는 파일 이름만 보여 설치 스킬이 전부 `SKILL.md` 로 보였다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 명령: `bash tests/hermes-skill-yield-test.sh`. 강등 = 판정(helpful+noop) ≥ 50 · 판정 중 도움률 ≤ 5%. "주입 424 · 판정 17(전부 도움)" 은 강등하지 않는다.
- [x] 목표 2 — 명령: `bash tests/hermes-dashboard-test.sh`. 스킬 이름은 `SKILL.md` 면 폴더 이름, 출처(설치·결정화·개인·그물망) 표시, 판정 50 미만은 "판정 부족".

## 2-bis. 착수 전 확인한 사실 (2026-09-22)

| 확인한 것 | 결과 |
| --------- | ---- |
| 판정 범위(공장) | 주입 2,879 · 판정 1,102(38%) · **세션 605 중 판정 있는 세션 15** |
| 판정 결과(공장) | helpful 1,054 · noop 47 — 판정된 것의 96% 가 도움 |
| zeroday · terminal-shipping | 판정 42% · 41%, 판정 있는 세션 17/1,227 · 2/308 |
| 옛 기준 강등 후보(11곳) | 6개 — 그중 도움 기록 있는 것 5개. 새 기준 0개 |

## 3. 비목표 (Out of Scope)

- **판정이 왜 이렇게 적은가**(세션 605 중 15)와 **판정 규칙이 왜 96% 도움인가** — 원인 조사가 필요한 별개 문제. backlog `skill-correlation-coverage.md`.
- `MIN_JUDGED = 50` · `MAX_HELPFUL_RATE = 0.05` 값 자체 — 2026-09-18 계획의 근거((0.95)^50 ≈ 7.7%)를 판정에 그대로 옮긴다.

## 4. 영향 영역

- 코드: `scripts/hermes_skill_yield.py`(기준) · `scripts/hermes_dashboard_data.py` · `scripts/hermes_dashboard_html.py` · `scripts/hermes-cleanup.py`(출력 문구).
- 신규 파일 목록: 없음(기존 파일 수정만).
- 시험: `tests/hermes-skill-yield-test.sh`(fixture 가 correlated 를 도움으로 넣던 것을 helpful/noop 으로) · `tests/hermes-dashboard-test.sh`.

## 5. 단계 (Steps)

### Step 1. 강등 기준 [Impl] — ✅ RED(옛 코드는 도움만 된 스킬을 지우고 쓸모없는 스킬을 남겼다) → GREEN 12/12
### Step 2. 대시보드 이름·출처·판정 [Impl] — ✅ 58/58
### Step 3. 실데이터 [단순] — ✅ 공장 주입 상위 10 이 이름·출처로 보이고 강등 후보 0

## 6. 의사결정 로그

- 2026-09-22: 판정 = `skill_index.helpful_count + noop_count` — 근거: 판정 결과가 남는 유일한 곳. `correlated` 는 판정 여부만.
- 2026-09-22: 대시보드 "판정 부족" 문턱은 강등 기준과 같은 50 — 근거: 같은 숫자를 두 뜻으로 쓰지 않는다.

## 7. 발견·예외

- 2026-09-18 계획(`skill-yield-junk`)의 근거 "세 파일 775회 주입 · 도움 2회" 도 실제로는 **판정 2회** 였을 수 있다 — 그 계획의 결론(단일 영단어 키는 헛주입)은
  판정 규칙 개선 뒤 다시 잴 것.

## 8. 회고 (완료 시 작성)

- 잘된 것: 이름 문제를 보다가 숫자 뜻을 의심했고, 11곳 전체에서 옛·새 기준을 대조해 결함 크기(도움 있는 스킬 5개 삭제 위험)를 먼저 쟀다.
  RED 가 결함을 그대로 보였다 — 옛 코드는 판단이 뒤집혀 있었다.
- 잘못된 것: 같은 날 앞에서 `correlated` 가 판정 표시라는 것을 이미 알았는데(결정화 백로그 재실측), 그것을 쓰는 다른 곳(대시보드·강등)을 그때 찾지 않았다.
  fixture 에 파이썬 식을 SQL 문자열 안에 넣어 시험이 중간에 멈췄다.
- 다음 룰 후보: "한 칸의 뜻이 틀렸다는 것을 알면, 그 칸을 읽는 모든 곳을 그 자리에서 찾는다" — 사례 1건, 보류.
