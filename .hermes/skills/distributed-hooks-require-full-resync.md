# distributed-hooks-require-full-resync
<!-- hermes:auto-generated version:1 created:2026-10-06 -->

## 문제 상황
훅 파일을 `assets/hooks/`에서 수정해도 분산된 프로젝트들의 `.git/hooks/` 복사본이 자동 갱신되지 않음.
훅은 symlink가 아니라 `cp`로 복사되므로, 원본 수정 후 모든 프로젝트에 수동 재배포 필수.
공장(`claude-harness-hermes` 자신)의 `.git/hooks/`도 따로 갱신해야 함 (09-17 이후 낡은 파일 추적).
hooks.log는 로테이션 정책 없이 계속 쌓임 (현재 67,934줄 / 6.5MB / 45일 누적).

## 규칙
- [ ] 훅 원본(`assets/hooks/*.sh`) 수정 직후 `update-all.sh`로 전체 프로젝트에 재배포
- [ ] `.git/hooks/` 내 낡은 파일(09-17 이전)을 `git log --follow` 로 추적해 제거
- [ ] 공장 자신의 `.git/hooks/`도 원본과 동일 버전으로 유지
- [ ] hooks.log는 크기 기반(10MB) 또는 줄 수 기반(50,000줄) 로테이션 도입
- [ ] 훅이 symlink가 아님을 개발자에게 명시 (update-all.sh 주석으로 기록)

## 근거
- 감지 횟수: 8회 이상 (원본 수정 전후 동기화 재확인)
- 패턴 키: hooks
- 영향: 낡은 pytest_gate.sh(09-17)와 doc_counts.py가 함께 발견, 공장 gates도 중복 수정
