# legacy-venv-version-mismatch-rebuild
<!-- hermes:auto-generated version:1 created:2026-10-26 -->

## 문제 상황
시스템 Python 업그레이드(3.10→3.12) 후 기존 `.venv`가 구 버전을 가리켜서 패키지 인식 실패. upbit-ai-trading, kis-trading에서 pytest 설치 불가능 → R-test 게이트 차단. 전파 시 이 문제를 사전 발견하지 못하면 커밋이 실패함.

## 규칙
- [ ] 전파 전: `python -m pip list` 또는 `pytest --version` 으로 각 프로젝트 venv 상태 확인
- [ ] 패키지 미인식 오류 발생 시: `python --version` (실행 python) vs `.venv/pyvenv.cfg` (venv python) 비교
- [ ] 미스매치 발견 시: `rm -rf .venv && python -m venv .venv && source .venv/bin/activate && pip install -e .` 로 재생성
- [ ] 호환성 미복구 프로젝트는 전파 제외 목록에 추가, 별도 회의 후 처리

## 근거
- 감지 횟수: 4회
- 패턴 키: upbit-ai-trading
- 영향: kis-trading도 동일 증상
