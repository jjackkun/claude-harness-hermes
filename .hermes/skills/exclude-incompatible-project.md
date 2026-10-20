# exclude-incompatible-project
<!-- hermes:auto-generated version:1 created:2026-10-16 -->

## 문제 상황
특정 프로젝트가 전파 대상에 맞지 않을 때(git 저장소 아님, 별도 런타임 등), `.installed-projects` 파일 수정과 메모리 기록 절차가 산발적으로 진행됨. 제외 사유가 메모리에만 남아 파일 상태와 불일치 가능성.

## 규칙
- [ ] 프로젝트 부적합 판단 후 `.installed-projects`에서 해당 줄 제거
- [ ] 제외 이유를 메모리 파일로 기록 (형식: `[project-<이름>-excluded.md]` — 날짜, 사유 포함)
- [ ] 메모리 MEMORY.md 인덱스에 제외 항목 추가 (한 줄, 150자 이내)
- [ ] .installed-projects 수정을 커밋에 포함하되, 동일 커밋에서 메모리도 함께 스테이징

## 근거
- 감지 횟수: 4회 (teulankkae 2026-10-06, wonil 2026-10-14, ai-create 2026-09-22, rim-office 2026-09-22)
- 패턴 키: installed-projects
