# design-decisions-unplanned — 원장에 확정됐으나 어느 계획서도 인용하지 않은 결정 4건

## 배경

2026-09-18 결정 ID 체계 정리(계획 `2026-09-18-decision-id-ledger`) 뒤 `R-design-cover` 기준선에 남은 (A) 틈. 근거: `docs/audits/2026-09-18-decision-id-mapping.md` 2차 표.

| ID | 결정 | 상태 | 할 일 |
|---|---|---|---|
| C-20 | 기억 이벤트 `body` 원격 암호화, 기계 칸 평문 | 코드 있음(`scripts/hermes_sync_fragments.py` `_outgoing_memory`·`import_memory`), 계획 문장 없음 | 계획 3 §7 에 소급 인용 + 테스트 존재 확인(`hermes-sync-test`)이면 인용만으로 닫힘 |
| D-04 | 저장소 하나 = 소우주 하나, 회사 층 없음 | 정의성 결정 — 코드 대상 아님 | 계획 2 §6 에 전제로 인용(`hermes_universe.py` 가 저장소마다 `universe.id`) |
| H-04 | 다른 소우주의 일은 사람 경유, 자동 이슈 없음 | `handoff.external` kind 만 예약, 기록 코드 0 | 구현 계획 필요: 봉투가 다른 `universe_id` 를 가리키면 `handoff.external` 로 기록하고 사람에게 안내 |
| H-09 | 에이전트는 소우주 하나에만, 복제는 우주 템플릿 경유 | `kind: template` 값만 예약 | 구현 계획 필요: 제안 봉투 `kind: template` + 공장 템플릿 승격 경로 |

## 검증

- `python3 assets/hooks/design_cover.py check` 가 rc 1 이고 기준선 항목이 이 4건뿐이다. 항목이 닫힐 때마다 기준선에서 지운다.
