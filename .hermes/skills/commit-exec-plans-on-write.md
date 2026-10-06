# commit-exec-plans-on-write
<!-- hermes:auto-generated version:1 created:2026-10-06 -->

## 문제 상황
- 계획서 작성 후 커밋하지 않고 다른 작업으로 넘어가는 패턴
- R-plan 게이트에서 exec-plan 부재 경고를 받은 뒤 사후 대응하는 상황 반복
- `docs/exec-plans/active/`, `backlog/`, `completed/` 경로 혼선으로 문서 관리 체계 흐트러짐
- git revert 등으로 인한 계획 문서 손실 이력

## 규칙
- [ ] exec-plans 파일 작성 완료 직후 즉시 `git add` + `git commit` 실행
- [ ] 파일을 추가하기 전에 active / backlog / completed 경로를 명확히 결정
- [ ] R-plan 게이트 경고 발생 → 즉시 해당 계획 파일을 커밋하기 (사후 대응 금지)
- [ ] 작은 계획도 `.md` 파일로 공식화 (메모리/핸드오프 아님)
- [ ] 계획 문서 작성 후 "다음 행동"에 "커밋하겠습니다"를 명시하고 같은 턴에서 실행

## 근거
- 감지 횟수: 5회 (실측/backlog/active 혼재, 커밋 누락, 게이트 경고, revert 손실)
- 패턴 키: exec-plans
