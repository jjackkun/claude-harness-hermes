# memory-select-empty-table-warning — 기억이 0건인 정상 상태를 경고로 찍는다

## 관찰 (2026-09-28, agent-mention-bridge Step 3·4)

에이전트 출근 본문을 만들 때(`scripts/hermes_soul_render.py` → `hermes_memory_select.select_memories`)
`memory_events` 표가 없으면 `[agent-soul WARN] 기억 선별 실패, MEMORY.md 파일로 대신: no such table: memory_events` 가 난다.

- 공장 저장소에서도, **갓 설치한 프로젝트**에서도 난다 — 기억이 한 건도 적히지 않아 표가 아직 없는 **정상 상태**다.
- 동작은 맞다(MEMORY.md 파일로 폴백). 세션 stdout 은 오염되지 않고 `.hermes/hooks.log` 와 세션 시작 stderr 에만 남는다.
- 문제는 소음이다 — 진짜 선별 실패(스키마 손상 등)와 "아직 기억 없음" 이 같은 경고라 로그로 가를 수 없다.

## 목표 후보

- [x] 표가 없거나 기억 0건이면 경고 없이 파일 폴백. 검증: 새 설치 프로젝트에서 훅 실행 → stderr 0 B · hooks.log 에 WARN 없음.
- [x] 표는 있는데 읽기가 실패하면 지금처럼 WARN. 검증: 표 이름을 바꾼 픽스처에서 WARN 1줄.

## 관련

- `docs/exec-plans/completed/2026-09-28-agent-mention-bridge.md` §7
- `scripts/hermes_memory_select.py` · `scripts/hermes_soul_render.py::_selected_memory`

## 6. 의사결정 로그

- 표 확인은 `sqlite_master` 조회 한 줄 — `scripts/hermes-agent.py` refresh-memory 와 같은 방식.
- "표 이름을 바꾼 픽스처" 대신 **칸이 맞지 않는 `memory_events`** 로 깨짐을 만든다 — 이름을 바꾸면 "표 없음" 이 되어 조용한 쪽으로 가기 때문이다.
- 기억 끔 상태(`memory_events_disabled_*` 사본만 있음)도 표 없음과 같이 조용히 파일 폴백 — 사람이 일부러 끈 상태라 실패가 아니다.

## 7. 실측 (2026-10-03, 임시 픽스처 · 수정 전 → 후)

| 경우 | stderr | WARN | 파일 폴백 |
| --- | --- | --- | --- |
| 표 없음 | 97 B → 0 B | 1 → 0 | 1 → 1 |
| 기억 끔(disabled 사본만) | 97 B → 0 B | 1 → 0 | 1 → 1 |
| 표 깨짐(칸 불일치) | 94 B → 94 B | 1 → 1 | 1 → 1 |

시험: `tests/hermes-soul-render-test.sh` 7건(수정 전 1건 빨강) · 기존 `hermes-agent-mention-test.sh` 86 · `hermes-agent-summary-test.sh` 30 통과.
공장 DB 는 이미 `memory_events` 가 있어 실 저장소에서는 수정 전 경고가 재현되지 않는다 — 픽스처로만 잰다.

## 8. 회고

- 잘된 것: 같은 표 확인이 `hermes-agent.py` 에 이미 있어 새 방식을 만들지 않았다. 고친 곳 2줄.
- 아쉬운 것: 백로그 검증 문구("표 이름을 바꾼 픽스처")가 의도와 반대 경우를 만든다 — 검증 문구도 실행해 보고 적어야 한다.
- 다음 룰 후보: 없음.
