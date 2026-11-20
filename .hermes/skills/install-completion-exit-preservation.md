# install-completion-exit-preservation
<!-- hermes:auto-generated version:1 created:2026-11-18 -->

## 문제 상황
설치 스크립트(setup.sh, update-all.sh)의 마지막에 완료 메시지나 안내를 추가할 때, 직접 `exit 0`을 붙이면 원래의 종료 코드가 0으로 덮어씌워진다. 설치 실패(exit 1)가 성공으로 변환되는 버그 발생.

## 규칙
- [ ] 설치 스크립트 내부에서 최종 `exit` 명령을 직접 사용하지 않는다
- [ ] 완료 메시지(안내문, alert 등)는 stdout/stderr로 출력하되, exit는 호출자가 처리하게 한다
- [ ] 여러 경로에서 cleanup이 필요하면 `cmd; rc=$?; <cleanup>; exit $rc` 패턴으로 코드를 보존한다
- [ ] setup 스크립트를 호출하는 감싸개(_hermes_setup 등)에서 최종 exit 처리 및 완료 메시지 출력을 담당하도록 설계한다

## 근거
- 감지 횟수: 2회
- 패턴 키: setup-script-completion-guidance
