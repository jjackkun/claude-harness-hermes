# designate-encrypted-fields
<!-- hermes:auto-generated version:1 created:2026-09-16 -->

## 문제 상황
설계 문서를 작성할 때 데이터 모델의 각 필드가 평문인지 암호화인지를 미리 명시하지 않고, 구현 단계나 검토 후반에 뒤늦게 암호화 정책을 결정하는 상황. 특히 work-history처럼 자동 기입 필드(timestamp, ID)와 인간의 자유 텍스트 필드(intent, lesson, decision)가 섞여 있을 때 구분이 모호해진다.

## 규칙
- [ ] 저장소·구조·모델을 설계할 때 각 필드를 **두 카테고리로 먼저 분류**: "머신 자동 기입(평문)" vs "인간 자유 텍스트(암호화 대상)"
- [ ] 민감도에 따라 암호화 강도 결정: full-encryption · partial-masking · hash-only
- [ ] 설계 문서의 데이터 흐름에 암호화 경계를 함께 그린다 (예: intent/lesson/decision 옆에 🔒 표시)
- [ ] 이 결정을 설계 문서 표 또는 섹션에 명시적으로 기록 (뒤늦은 변경 방지)

## 근거
- 감지 횟수: 1회
- 패턴 키: encryption-applied-to-intent-lesson-decision
