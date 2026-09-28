# memory-select-empty-table-warning — 기억이 0건인 정상 상태를 경고로 찍는다

## 관찰 (2026-09-28, agent-mention-bridge Step 3·4)

에이전트 출근 본문을 만들 때(`scripts/hermes_soul_render.py` → `hermes_memory_select.select_memories`)
`memory_events` 표가 없으면 `[agent-soul WARN] 기억 선별 실패, MEMORY.md 파일로 대신: no such table: memory_events` 가 난다.

- 공장 저장소에서도, **갓 설치한 프로젝트**에서도 난다 — 기억이 한 건도 적히지 않아 표가 아직 없는 **정상 상태**다.
- 동작은 맞다(MEMORY.md 파일로 폴백). 세션 stdout 은 오염되지 않고 `.hermes/hooks.log` 와 세션 시작 stderr 에만 남는다.
- 문제는 소음이다 — 진짜 선별 실패(스키마 손상 등)와 "아직 기억 없음" 이 같은 경고라 로그로 가를 수 없다.

## 목표 후보

- [ ] 표가 없거나 기억 0건이면 경고 없이 파일 폴백. 검증: 새 설치 프로젝트에서 훅 실행 → stderr 0 B · hooks.log 에 WARN 없음.
- [ ] 표는 있는데 읽기가 실패하면 지금처럼 WARN. 검증: 표 이름을 바꾼 픽스처에서 WARN 1줄.

## 관련

- `docs/exec-plans/completed/2026-09-28-agent-mention-bridge.md` §7
- `scripts/hermes_memory_select.py` · `scripts/hermes_soul_render.py::_selected_memory`
