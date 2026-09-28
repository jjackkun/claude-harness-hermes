# register-hermes-scripts-in-config
<!-- hermes:auto-generated version:1 created:2026-09-22 -->

## 문제 상황
헤르메스 새 스크립트(예: `hermes_*.py`)를 추가할 때 `hermes.conf`의 복사 목록에 등록하지 않으면, 런타임에 `ModuleNotFoundError` 또는 import 실패가 발생합니다. 실제 설치에서 4건의 누락이 실측되어 `hermes-propose.py --help` 등이 모듈을 못 찾아 중단되었습니다.

## 규칙
- [ ] 새 `hermes_*.py` 스크립트를 `scripts/` 디렉토리에 추가할 때, `hermes.conf`의 복사 목록 섹션에 파일명을 등록한다
- [ ] 스크립트가 다른 헤르메스 모듈을 import하면, 그 모듈도 이미 복사 목록에 있는지 먼저 확인한다
- [ ] 커밋 전에 `scripts/` 디렉토리의 모든 `hermes_*.py` 파일이 `hermes.conf`에 나열되었는지 확인한다

## 근거
- 감지 횟수: 4회
- 패턴 키: hermes.conf
- 실제 피해: 헤르메스 크론/루프 배포 후 모듈 누락으로 초기화 실패
