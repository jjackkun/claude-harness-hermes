# docs-redaction-and-convention-gate
<!-- hermes:auto-generated version:1 created:2026-10-16 -->

## 문제 상황
docs 판정(R-doc) 모듈이 새로 추가된 민감 정보(hermes_redact 가림 처리)를 감지하지 못해 오탐을 내고,
문서 위치·날짜 형식이 일관되지 않으면서 README 판정과 doc_counts 동기화가 깨짐.

## 규칙
- [ ] 새 문서 작성 시 기존 관례 먼저 확인 (docs/videos/ 같은 폴더 구조, 게시일 기준 날짜)
- [ ] 민감 정보는 hermes_redact 로 일괄 처리하고 한 곳에서만 노출
- [ ] docs 판정 모듈에 가림 처리 항목을 README 표·오탐 목록에 추가
- [ ] 계획서 완료 후 회고 작성 → docs/exec-plans/completed/ 로 이동하는 체크 규칙화

## 근거
- 감지 횟수: 3회 (R-doc 오탐 1회, 문서 관례 미적용 1회, 계획서 회고 후 이동 2회)
- 영향: 판정 모듈 유지보수 비용, 문서 일관성 저하
- 패턴 키: r-doc
