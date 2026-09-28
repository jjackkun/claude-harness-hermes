# store-expires-in-decision-field
<!-- hermes:auto-generated version:1 created:2026-09-17 -->

## 문제 상황

Handoff(인계) 객체에서 `expires_at` 메타데이터를 저장할 때, structured field인 `evidence`에 담으려다가 허용목록(whitelist) 검증에 실패. `evidence`는 정해진 필드만 허용하고 `expires_at`은 그 목록에 없음. 대신 자유 텍스트 필드인 `decision`에 한 줄로 담아야 함을 발견.

## 규칙

- [ ] TTL·만료 관련 메타데이터는 structured field(`evidence`)가 아니라 text field(`decision`)에 저장
- [ ] 구조화된 필드에 값을 저장하기 전에 스키마의 허용목록을 확인
- [ ] 필드 선택 오류 발견 시 근처 문서(`_expires_of` 판정 기록기 등)에 어느 필드를 썼는지 명시

## 근거

- 감지 횟수: 1회
- 패턴 키: expires-at-in-decision-field
