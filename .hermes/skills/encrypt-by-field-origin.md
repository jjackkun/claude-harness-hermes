# encrypt-by-field-origin
<!-- hermes:auto-generated version:1 created:2026-09-16 -->

## 문제 상황
데이터 스키마 설계에서 필드별 암호화 정책을 결정할 때, 시스템이 생성하는 필드(event_id, ts, kind, actor)와 사용자 입력 필드(intent, lesson, decision)를 구분하지 않으면 인덱싱 성능과 데이터 보호 사이 충돌 발생.

## 규칙
- [ ] 필드 출처를 먼저 구분하라 — 시스템 생성(ID, 타임스탐프, 카테고리, 액터) vs 사용자 입력(텍스트, 의견, 의사결정)
- [ ] 시스템 생성 필드는 평문 유지 — 인덱싱·쿼리·감사 필요
- [ ] 사용자 입력 필드는 기본값으로 암호화 — 민감 정보 보호
- [ ] 모든 엔티티에 일관된 정책 적용 — 예외 없음

## 근거
- 감지 횟수: 1회
- 패턴 키: plaintext-fields-event-id-ts-kind-actor
