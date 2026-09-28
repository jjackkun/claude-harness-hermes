# Confirmed Design in Plan

<!-- hermes:auto-generated version:1 created:2026-09-18 -->

## 문제 상황
설계 문서의 "(확정)" 또는 "✅ 리뷰 확정" 표지가 계획서 §2(목표/인수기준)에 제대로 반영되지 않은 채 계획이 닫혀 설계 결정이 누락되는 현상. 한 세션에 16건 발견, 코드 대조 결과 누락된 기능 15건.

## 규칙
- [ ] 설계 문서의 모든 "(확정)" 또는 "✅" 표지를 찾았다
- [ ] 각 확정 내용에 결정 ID(RV·G·V·K 등)가 있는지 확인했다
- [ ] 같은 계획서의 §2 또는 목표/인수기준에 그 ID가 명시적으로 인용되어 있는지 확인했다
- [ ] 누락된 확정이 있으면, 계획서에 추가했다
- [ ] `python3 scripts/hooks/design_cover.py` 로 R-design-cover 게이트를 실행했다

## 근거
- 감지 횟수: 16건
- 패턴 키: r-design-cover-promoted-to-rule
