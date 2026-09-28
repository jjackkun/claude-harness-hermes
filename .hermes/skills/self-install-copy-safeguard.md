# self-install-copy-safeguard
<!-- hermes:auto-generated version:1 created:2026-09-15 -->

## 문제 상황
`project-claude.sh` 가 자기 자신(예: `claude-harness-hermes` 설치 시)을 재설치할 때, 원본과 대상 디렉터리가 동일하면 `cp` 명령이 실패해서 `set -e` 로 인해 전체 설치 프로세스가 중단된다. 결과적으로 프리셋·규칙·훅 업데이트가 완료되지 않음.

## 규칙
- [ ] 스크립트 실행 시 원본 위치(`$ASSETS_DIR`, `$PRESETS_DIR`)와 대상 경로(`$target_dir`)를 realpath로 정규화해 비교한다
- [ ] 원본 == 대상이면 `cp` 단계를 건너뛴다 (자기 자신에 대해서는 이미 제 위치에 있으므로 복사 불필요)
- [ ] 건너뛴 항목은 로그에 기록해서 설치 과정의 투명성을 유지한다

## 근거
- 감지 횟수: 1회 (자기 저장소 `setup.sh` 재실행 중)
- 패턴 키: project-installation-tracking
