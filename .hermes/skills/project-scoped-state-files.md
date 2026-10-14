# project-scoped-state-files
<!-- hermes:auto-generated version:2 created:2026-10-08 -->

## 문제 상황
여러 프로젝트에서 .hermes/hag/on.json 같은 상태 저장소를 관리할 때, 세션 공유 상태와 혼동하여 프로젝트별 격리를 깰 수 있음.
update-all로 동기화할 때 한 프로젝트의 상태가 다른 프로젝트를 오염시킬 위험.

## 규칙
- [x] .hermes/hag/on.json 은 세션 공유가 아닌 **프로젝트별 격리 파일**로 설계
- [x] state.db 와 hag/on.json 의 생명주기를 일치시킴 (둘 다 프로젝트 로컬)
- [x] update-all 전파 시 프로젝트별 상태 파일이 독립적으로 유지되는지 검증
- [x] 상태 구조 변경 후 모든 대상 프로젝트에서 테스트 실행 (격리 확인)

## 근거
- 감지 횟수: 1회
- 패턴 키: hag-persist-per-project
- 설계: .hermes/hag/on.json 을 세션별에서 프로젝트별로 변경, update-all 10곳 설치 완료 (실패 0)
