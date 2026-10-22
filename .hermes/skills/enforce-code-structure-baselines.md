# enforce-code-structure-baselines
<!-- hermes:auto-generated version:1 created:2026-10-20 -->

## 문제 상황
R-struct 게이트가 언어별로 다른 규칙을 강제하면서, 새 언어 추가 시 설정을 빠뜨리거나 중복 관리하는 실수 반복. 파일 목록(setup/remove)과 기준선이 여러 곳에 산재되어 동기화 오류 발생.

## 규칙
- [ ] 새 언어 지원 시 `lib/struct_files.sh` 에만 파일 목록 추가 (install/remove 경로 한 곳 관리)
- [ ] 모든 언어는 `.structbaseline` 파일로 기준선 고정 (수동 조정 금지)
- [ ] pre-commit 게이트는 언어 무관 엔진 사용 (언어별 분기 금지)
- [ ] 새 소우주 설치 뒤 `git commit` 으로 `.structbaseline` 을 함께 기록 (기준선 누락 방지)
- [ ] R-struct 기준선 수정은 `git diff [baseline]` 으로 검증 후 계획서에 근거 기록

## 근거
- 감지 횟수: 13개 언어 · pre-commit 엔진 교체 · lib 중앙화
- 패턴 키: r-struct
