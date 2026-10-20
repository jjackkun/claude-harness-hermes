# factory-json-rebase-conflict-use-upstream
<!-- hermes:auto-generated version:1 created:2026-10-16 -->

## 문제 상황
terminal-shipping 등 다중 저장소 도구를 사용해 여러 프로젝트에서 rebase할 때, 설치 목록 파일(`factory.json`)이 충돌하는 상황이 반복 발생. 각 프로젝트의 factory.json이 공장의 최신 버전과 달라서 발생하는 merge conflict.

## 규칙
- [ ] rebase 도중 factory.json 충돌이 발생하면, 먼저 diff를 확인 (`git diff HEAD factory.json`)
- [ ] 공장 저장소(상류)의 버전이 있으면, 상류 버전을 우선 (`git checkout --theirs factory.json`)
- [ ] 파일을 staged 상태로 변경 (`git add factory.json`)
- [ ] rebase 진행 (`git rebase --continue`)
- [ ] 로컬 커스터마이제이션이 필요하면, rebase 완료 뒤 수동으로 병합

## 근거
- 감지 횟수: 4회
- 패턴 키: factory.json
