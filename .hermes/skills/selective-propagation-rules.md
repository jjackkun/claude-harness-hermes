# selective-propagation-rules
<!-- hermes:auto-generated version:1 created:2026-10-26 -->

## 문제 상황
여러 프로젝트에 기능·수정을 동시 전파할 때, 프로젝트별로 제외 조건(git 저장소 아님·자동 배포·개발 단계)이 다르지만 대상 목록을 매번 새로 세워서 누락·실수가 생김. 제외 규칙이 메모리에 산발적으로 저장되어 전파 전에 전체를 확인하기 어려움.

## 규칙
- [ ] 전파 작업 시작 전, 메모리의 `project-*-excluded` 항목을 전부 조회해 제외 대상 목록 정리 (완전 제외 vs 설치만 vs 커밋 금지)
- [ ] 각 프로젝트별 처리 규칙을 명시 (예: "zeroday-frontend는 설치만, 푸시 안 함")
- [ ] 전파 대상 프로젝트 수를 명시하고, 제외된 프로젝트 수도 함께 알림 (예: "12곳 대상, 5곳 제외")
- [ ] update-all 일괄 스크립트 대신 필터를 적용하거나 수동으로 대상 프로젝트만 처리
- [ ] 새로운 제외 조건 발견 시, `docs/exec-plans/active/` 의 전파 계획서 §3에 추가 후 메모리 기록

## 근거
- 감지 횟수: 7회 이상 (zeroday-frontend·rim-kanban·jj-agent-room·ai-create·rim-office·teulankkae·wonil)
- 패턴 키: multi-project-selective-propagation
