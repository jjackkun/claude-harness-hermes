# dream 워터마크가 시계 역행 시 요약을 영구 누락한다

> 출처: `docs/exec-plans/completed/2026-09-18-dream-test-clock.md` §7

## 문제

`scripts/hermes-dream.py` 는 `session_summary.updated_at > watermark` 로 새 요약을 수집하고, 워터마크를 마지막 요약의
`updated_at` 으로 올린다. 벽시계가 뒤로 가면(WSL2 시계 보정 — 2026-09-09 시험 덤프에서 1.1초 뒤 삽입이 1초 이른 시각으로
기록된 실측) 그 뒤 종료된 세션의 요약이 워터마크보다 이르게 찍혀 **다음 드리밍에서도, 그 다음에서도 수집되지 않는다.**

시험(`hermes-pipeline-test.sh` 20·21)은 2026-09-18 부터 합성 시각을 써서 이 결함을 더는 재현하지 않는다. 운영 결함은 남아 있다.

## 고칠 때 후보

- 수집 조건을 `updated_at >= watermark AND session_id NOT IN (처리된 세션)` 으로 — 처리 이력 테이블 필요.
- 또는 `session_summary` 에 단조 증가 `seq`(AUTOINCREMENT) 를 두고 워터마크를 `seq` 로 — 스키마 변경 + 마이그레이션.

## 먼저 잴 것

- 소우주 8곳의 `session_summary` 에서 `updated_at` 이 이전 행보다 이른 사례가 실제로 있는지(`LAG` 로 셈).
  0 이면 우선순위를 낮게 둔다.
