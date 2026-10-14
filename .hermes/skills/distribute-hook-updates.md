# distribute-hook-updates
<!-- hermes:auto-generated version:1 created:2026-10-08 -->

## 문제 상황
`assets/hooks/` 의 훅 파일을 수정할 때, 공장과 모든 소우주 프로젝트의 `.git/hooks/` 에 수동으로 반영되지 않으면 버전이 갈라짐. 훅은 symlink가 아니라 cp 복사이므로, `update-all.sh` 재배포 없이 수정하면 일부 프로젝트만 낡은 코드를 계속 실행함.

## 규칙
- [ ] `assets/hooks/` 의 훅 파일을 수정한 후 **반드시** `./scripts/update-all.sh` 를 실행해 전파
- [ ] hooks.log 로테이션·포맷 변경 시 `assets/hooks/` 원본부터 수정 (파생 파일 직접 수정 금지)
- [ ] 공장(`claude-harness-hermes`)의 `.git/hooks/` 와 소우주 모든 `.git/hooks/` 가 같은 커밋 날짜의 코드를 운영하는지 월 1회 확인
- [ ] hooks.log 는 파생 디버깅 로그 — 로테이션 후 update-all 재실행 전까지 각 프로젝트 사본이 달라도 무방

## 근거
- 감지 횟수: 1회 (2026-10-08 hooks.log 동기화 감사)
- 패턴 키: hook-sync-pattern
