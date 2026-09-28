# decision-id-namespace-clarity
<!-- hermes:auto-generated version:1 created:2026-09-18 -->

## 문제 상황
설계 문서의 결정 ID(A·C·G·K·V 등)가 여러 절(§)에 나타나면서 추적 불가. 
"A는 §5인가 §8인가", "V는 §7의 어느 줄인가" 같은 혼동이 반복되어 ID → 절 매핑을 세마다 다시 확인하는 낭비 발생.
결정 ID가 원장에 등재되지 않은 채로 설계에만 있거나, 같은 ID가 중복 인용되기도 함.

## 규칙
- [ ] 새 결정 ID 추가 전 `docs/hermes-universe/decision-log.md` 원장에서 접두어 매핑 확인
- [ ] 한 ID는 정확히 하나의 절(§N)과만 1:1 대응 — 다른 절에서 같은 ID 재사용 금지
- [ ] 설계 문서에 ID 인용 후 바로 원장에 새 행 추가 (형식: `| ID | 절 | 결정 | `)
- [ ] 설계 문서 ID → 계획서 목표 → 코드 커밋 메시지로 추적 체인 유지
- [ ] 같은 ID가 다른 절에서 보이면 = 오기(fix) 또는 새 ID 필요(별도 결정)

## 근거
- 감지 횟수: 3회 이상
- 패턴 키: id-system-prefix-canonical
- 관련 계획: `docs/exec-plans/active/2026-09-18-decision-id-ledger.md` 목표 1·2
