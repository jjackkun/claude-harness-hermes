# design-gaps-tier2 — 설계에 확정됐으나 아직 코드가 없는 기능 보강 9건

## 배경

2026-09-17 설계 문서 9개(`docs/hermes-universe/design/agent/*.md`, `world/*.md`)의 기계 동작 문장
≈85건을 코드와 전수 대조했다. 보안·계약 위반에 해당하는 7건은 계획 `2026-09-17-design-coverage-gaps`
가 채웠고, 아래 9건은 **기능 보강**이라 순서를 정해 따로 한다. 각 항목은 설계 파일:줄이 근거다.

## 항목

| # | 설계 문장 | 없는 것 | 봐야 할 코드 |
|---|---|---|---|
| 1 | `world/skill-layers.md:53` 주입 순서는 개인 → 단위 → 소우주 공통 → 우주 공통 | `hermes-search.py` 정렬 키가 IDF·helpful·used 뿐, 층은 필터에만 | `scripts/hermes-search.py` 정렬 |
| 2 | `agent/memory-events.md:119` 철회된 기억이 다시 배워지면 "전에 철회됨" 표시 | 철회 대상 제외만 함, content_hash ↔ retracted 대조 없음 | `scripts/hermes_memory_conflicts.py` |
| 3 | `agent/identity.md:198,209` 짝(`task.assigned`) 없는 actor 를 보기에서 "출처 불명" 표시 | 기록 시점 `system:unverified-session` 대체만 있음, 보기 계산 없음 | `scripts/hermes_journal_views.py` |
| 4 | `agent/handoff-contract.md:79` 만료 원인(열쇠 없음·러너 죽음)을 기계가 판정해 `evidence.reason` 에 | `check_expired` 가 고정 사유만 기록 | `scripts/hermes_handoff.py`, `assets/hooks/claude-sessionstart-handoff-expiry.sh` |
| 5 | `agent/handoff-contract.md:83` 같은 봉투의 두 번째 `handoff.question` 은 사람에게 올린다 | 되묻기 횟수 계산·승격 없음 | `scripts/hermes_handoff.py resolve` |
| 6 | `agent/handoff-contract.md:66` 동시 요청은 지시→협업→요청 순, 같은 종류는 선착순 | 대기열·우선순위 없음 (kind 는 2026-09-17 부터 기록됨) | 신규 모듈 |
| 7 | `agent/creation-and-organization.md:59` 담당 매칭 결과(요청 축·선택 근거)를 `task.assigned` 에 남긴다 | `hermes-summon.py` evidence 에 template 만 | `scripts/hermes-summon.py` |
| 8 | `agent/creation-and-organization.md:95` "담당 두지 않음" 선택을 기억해 그 영역은 다시 묻지 않는다 | 기억·판정 없음 | `scripts/hermes-agent.py match` + 기억 이벤트 |
| 9 | `agent/creation-and-organization.md:103` 사람 없는 세션은 `main` 이 수행하고 "담당 없음" 제안을 기록, 다음 대화형 세션에서 문의 | `ask:` 로 중단만, 기록·이월 없음 | `scripts/hermes-summon.py`, 세션 시작 훅 |

## 확인 필요 (grep 만으로 단정 불가)

- `world/skill-layers.md:154` 강등 반환을 위한 승격 이력 `universe_id` — 봉투에는 있으나 공장 측 "승격 이력" 저장소가 코드에 없음(사람 PR 로 처리하는지 확인).
- `agent/memory-events.md:118` 단일 사례 기억은 개인 스킬로 승격하지 않는다 — 기억→개인 스킬 승격 경로 자체가 없어 차단이 공허.
- `agent/creation-and-organization.md:183` YAML 앵커·별칭 거부 — 앵커가 문자열로 수용된 뒤 `validate_org` 가 간접 거부. 스칼라 자리에 오는 앵커는 통과할 수 있음.

## 재발 방지 (계획 §8 룰 후보 `R-design-cover`)

설계 문서의 "(확정)" 문장이 계획서 §2 목표에 옮겨졌는지 대조하는 게이트. 이 9건과 SOUL 주입·마스킹 누락이 전부 같은 경로(설계→계획 전사 누락)로 생겼다.
