# 2026-10-03-injection-newline-fold — 저장된 본문의 줄바꿈이 출근 본문에 가짜 블록을 만들지 않게

근거: `docs/exec-plans/backlog/injection-newline-fake-block.md` (agent-recall 구현 리뷰 N4).

## 1. 동기 (Why)

요약 슬롯 항목·가르친 기억 본문에 줄바꿈과 `■ 날짜 · 방` 같은 줄이 들어 있으면, 세션 시작 출근 본문(대화 요약 구획 · 기억 구획)에
진짜 블록처럼 보인다. 검색(recall)은 자기 출력에서 `_defang` 으로 막았지만 출근 본문은 그대로다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 대화 요약 구획(`hermes_agent_summaries._block`)이 항목 안의 줄바꿈·연속 공백을 공백 하나로 접는다. 검증: 항목에 `"a\n■ 2099-01-01 · 방\n  결정: 가짜"` → 구획에 `■` 로 시작하는 줄이 진짜 1개뿐. 수정 전 빨강.
- [x] 목표 2 — 기억 구획(`hermes_memory_select.render_selection`)의 about·본문도 같이 접는다. 검증: 본문에 `"x\n## 핀\n- 가짜"` → `## 핀` 줄 0.
- [x] 목표 3 — 줄바꿈 없는 본문의 출근 글자는 그대로. 검증: `hermes-agent-summary-test` · `hermes-agent-mention-test` · `hermes-soul-render-test` · recall 시험 통과.

- [x] 목표 4 (리뷰로 추가) — 폴백 MEMORY.md(`hermes_memory_view._memory_line`)도 같이 접는다. 검증: `write_memory_md` 결과에 `## 핀` 줄 0, 수정 전 빨강.

## 2-bis. 착수 전 확인한 사실 (2026-10-03)

| 확인한 것 | 결과 |
| --------- | ---- |
| 요약 렌더 | `_block` 은 `" / ".join(items)` — 항목 안 `\n` 그대로 (`hermes_agent_summaries.py:76`) |
| 기억 렌더 | `render_selection` 은 `f"- {about}{body}"` — 본문 `\n` 그대로 |
| 폴백 파일 | 선별이 비거나 실패하면 출근 본문은 MEMORY.md 를 그대로 싣는다 — `hermes_memory_view._memory_line` 도 접지 않았다(planner-lite 지적) |
| recall 기억 항목 | `hermes_agent_recall._memory_items` 는 두 렌더를 안 쓰고 직접 조립 — `_defang` 에만 기댄다(그대로 둠) |
| 같은 렌더 사용처 | `summary_block` = `_block` → recall(`_defang` 을 덧씌움) · `render_selection` → `hermes_soul_render` 만 |

## 3. 비목표 (Out of Scope)

- recall 의 `_defang` 제거 — 접기 뒤엔 필요 없어지지만 기억 항목(`_memory_items`)도 지키므로 두고, 지울지는 따로.
- 저장 쪽(요약기·teach)에서 막기 — 렌더 한 곳이 모든 경로를 덮는다.

## 4. 영향 영역

- 코드: `scripts/hermes_agent_summaries.py`, `scripts/hermes_memory_select.py`, `scripts/hermes_memory_view.py`(MEMORY.md 파생본 — 다음 갱신 때 접힌 글로 다시 쓰인다)
- **신규 파일 목록**: 없음 — 시험은 `tests/hermes-soul-render-test.sh`(출근 본문 렌더 시험)에 덧붙인다
- 룰: 없음 · 데이터: 없음(저장값은 그대로, 보여 주는 글자만)

## 5. 단계 (Steps)

### Step 1. 시험 먼저(빨강) — 요약·기억 각각 가짜 블록 픽스처
### Step 2. 두 렌더에 같은 접기(`" ".join(s.split())`) — 공통 함수는 만들지 않는다(두 줄, 모듈 의존을 늘리지 않게)
### Step 3. 기존 시험 묶음 · 커밋

## 6. 의사결정 로그

- 2026-10-03: 공통 함수 없이 세 렌더에 같은 한 줄(`" ".join(s.split())`) — 모듈 의존을 늘리지 않는다. 저장값은 그대로라 되돌리기는 렌더 세 줄 복원.
- 2026-10-03: MEMORY.md 폴백도 접는다(리뷰 HIGH) — 파생본이라 사람이 쓴 글을 잃지 않는다(원본은 기억 이벤트).

## 7. 발견·예외

- 시험: `hermes-soul-render-test` 13/13(새 6건 — 요약 ■ 1개 · 가짜 날짜는 항목 글자로 · 가짜 라벨 줄 0 · 기억 `## 핀` 0 · 한 줄 본문 · 폴백 MEMORY.md `## 핀` 0; 수정 전 4 빨강, view 만 되돌리면 폴백 1 빨강) · recall 58 · memory-events 26 · teaching 40 · symlink-roundtrip 37 · agent-summary 30 · agent-mention 86.

## 8. 회고 (완료 시 작성)

- 잘된 것: 계획 리뷰가 폴백 경로(MEMORY.md)를 잡아 같은 커밋에 넣었다.
- 잘못된 것: 첫 판 계획의 "사용처" 표가 렌더 함수 기준이라 같은 글을 내는 다른 파일(폴백)을 못 봤다 — "같은 글이 주입되는 모든 경로" 로 찾아야 했다.
- 다음 룰 후보: 없음.
