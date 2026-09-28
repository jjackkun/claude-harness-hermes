# verify-git-add-completeness
<!-- hermes:auto-generated version:1 created:2026-09-18 -->

## 문제 상황
여러 파일을 한 번에 `git add` 할 때, 일부 경로가 잘못되거나 존재하지 않으면 전체 add 명령이 실패합니다. 이미 스테이징된 파일들이 혼재되어 있으면 어느 파일이 실패했는지 추적이 어렵습니다.

## 규칙
- [ ] 여러 파일을 add하기 전에 `git status` 로 각 파일 경로 확인
- [ ] `git add <file1> <file2> ...` 시 각 경로를 명시적으로 나열(와일드카드 최소화)
- [ ] add 실패 시 오류 메시지에서 실패한 경로 파악 후 해당 파일만 제외
- [ ] 제외한 파일이 의도된 변경인지 재확인(backlog 이미 삭제됨 등)
- [ ] add 완료 후 `git status` 로 스테이징 목록 재확인

## 근거
- 감지 횟수: 1회
- 패턴 키: add-install-closure-test
