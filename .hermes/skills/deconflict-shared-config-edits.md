# deconflict-shared-config-edits
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
공유 설정 파일(`presets/workflow/harness.conf` 등)을 여러 세션에서 동시에 수정할 때, 다른 세션의 변경이 섞여 들어가 의도하지 않은 설정이 커밋되는 문제.

## 규칙
- [ ] 공유 설정 파일 수정 후 커밋 전에 `git diff` 로 전체 변경 확인
- [ ] 다른 세션의 변경 라인 식별 (메인에 없거나 다른 작업 세션 주석)
- [ ] `git add -p` 또는 파일 수동 편집으로 자신의 변경만 스테이징
- [ ] `git diff --cached` 로 최종 검증 후 커밋

## 근거
- 감지 횟수: 2회
- 패턴 키: harness.conf
