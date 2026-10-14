# propagation-hook-source-sync
<!-- hermes:auto-generated version:1 created:2026-10-08 -->

## 문제 상황
update-all로 여러 프로젝트에 파일을 전파할 때, `scripts/hooks/` 의 낡은 사본 2개가 원본과 달라서 전파 전에 수동으로 갱신해야 했습니다. 전파 대상이 9곳(공장 포함)인데 원본이 구형이면 모든 곳에 구형이 박혀서, R-doc 게이트 오탐까지 초래합니다.

## 규칙
- [ ] update-all 전파 **전에** `scripts/hooks/` 원본과 기존 사본 2개 동기화 확인
- [ ] 제외 목록(rim-office, ai-create, teulankkae) 명시적 유지 — 커밋 메시지에 제외 사유 기록
- [ ] 낡은 사본은 `git diff scripts/hooks/` 로 원본과 대조 후 갱신
- [ ] 전파 후 최소 1곳 이상 직접 확인 (`git show <hash>:<file>`)

## 근거
- 사실: 낡은 훅 사본 2개 원본 갱신 기록 + R-doc 게이트 오탐 발생
- 전파 대상: 9곳 모두 성공, 실패 0건
- 패턴 키: update-all-propagation-success
