# maintain-hag-state-project-scope
<!-- hermes:auto-generated version:1 created:2026-10-08 -->

## 문제 상황
hag 상태 저장소(`.hermes/hag/on.json`)를 세션 레벨에서 프로젝트 레벨로 변경할 때, 단일 파일 수정으로는 불충분하다. 관련 스크립트 5개(hermes_hag_state.py, hermes_hag_line.py, hermes_hag_commands.py, hermes-agent.py, tests)를 함께 수정해야 하고, 광범위한 시험(hermes-hag-rooms-test, hermes-hag-test, hermes-chat-test)으로 검증한 뒤 훅(@hag) 통합을 확인해야 한다.

## 규칙
- [ ] hag 상태 저장소는 세션별이 아닌 프로젝트별(`.hermes/hag/on.json`)로 관리한다
- [ ] 상태 경로 변경 시 scripts/hermes_hag_*.py 파일 5개를 일괄 검토해 수정한다
- [ ] update-all로 배포 전 로컬 프로젝트에서 hermes-hag-rooms-test · hermes-hag-test · hermes-chat-test를 모두 통과 확인한다
- [ ] 훅(@hag)이 새 경로를 인식하는지 게이트QA 호출로 검증한다
- [ ] 별칭 추가(@hh → @hagent 등) 시 훅 통합 영향을 확인 후 진행한다
- [ ] 계획서(hagent-call 등) 목표와 파일 치환이 일치하는지 확인한다

## 근거
- 감지 횟수: 1회 (세션별→프로젝트별 구조 전환)
- 패턴 키: hag-state-project-level
