# scripts-harness-eval-gate
<!-- hermes:auto-generated version:1 created:2026-10-07 -->

## 문제 상황
`scripts/` 내 파일 수정 후 검증을 건너뛰거나 지연하는 경향. 모델 명시(`--model haiku`) 누락으로 인한 크레딧 낭비 및 속도 저하.

## 규칙
- [ ] scripts/ 파일 생성/수정 후 즉시 `python3 scripts/harness-eval.py --trigger <변경사항> --k 2` 실행
- [ ] harness-eval 검증이 없으면 커밋 진행 금지 (R-harness-eval)
- [ ] 모델 명시 필수: `--model haiku` 또는 명시적 모델 선택 (진행 가능 여부 먼저 결정)
- [ ] scripts/hooks/ 공용 로깅 지점 월 1회 조사 (정기 유지보수)
- [ ] 제로데이 파일은 `.claude/ignored` 추가, 커밋 후 설치 산출물로 추적 분리

## 근거
- 감지 횟수: 5회 이상 (harness-eval 검증 지연, 모델 누락, 제로데이 추적)
- 패턴 키: scripts
- 영향: 불완전한 검증 → 배포 후 버그, 크레딧 24회 소모 반복
