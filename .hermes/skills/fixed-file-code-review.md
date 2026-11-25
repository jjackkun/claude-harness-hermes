# fixed-file-code-review
<!-- hermes:auto-generated version:1 created:2026-11-25 -->

## 문제 상황
code-reviewer가 임시방편으로 파일을 선택하고 검사 기준을 불규칙하게 적용해, 리뷰 범위와 커버리지가 추적되지 않음. 지적한 줄 번호가 실제 파일과 맞지 않을 수 있음.

## 규칙
- [ ] 리뷰 시작 전 파일 목록을 고정한다 (브랜치 범위 또는 커밋 하나)
- [ ] 파일 종류마다 검사 기준을 붙인다 (17개 규칙 중 해당하는 것)
- [ ] 파일 종류별로 override 규칙을 정의한다
- [ ] 각 파일을 순서대로 검사한다
- [ ] 검사 완료 후 장부를 작성한다 (coverage_rate · 파일명 · 줄 번호)
- [ ] 장부에 "몇 개 중 몇 개를 봤는지" 명시한다
- [ ] 지적한 줄 번호가 실제 파일과 맞는지 스크립트로 검증한다

## 근거
- 감지 횟수: 1회 (code-reviewer 절차 개선)
- 패턴 키: code-reviewer-procedure-fixed-files-rules-ledger
