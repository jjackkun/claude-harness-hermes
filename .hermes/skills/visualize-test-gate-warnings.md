# visualize-test-gate-warnings
<!-- hermes:auto-generated version:1 created:2026-10-20 -->

## 문제 상황
R-test 게이트가 스킵되거나 판정불가 상황을 조용히 지나쳐서, 개발자가 테스트 실패 원인을 알기 어려웠음. 경고로 변경되어 가시화되었으나, 경고를 받은 뒤 대응하는 규칙이 명확하지 않음.

## 규칙
- [ ] R-test 경고가 뜨면 즉시 멈추고 원인을 확인 (무시하고 진행하지 않음)
- [ ] `venv-test.sh` 경고 → 가상환경 선택 또는 활성화 확인
- [ ] 스킵(skip) 상황 → 테스트 환경(Python, npm 등) 사전 설치 확인
- [ ] 판정불가(indeterminate) 상황 → 테스트 입력 데이터 또는 실행 모드 확인
- [ ] 테스트 결과는 "X/Y 통과" 형태의 구체 수치로 보고 (silent skip 방지)

## 근거
- 감지 횟수: 3회
- 패턴 키: r-test
