# pytest-installation-venv-mismatch-check
<!-- hermes:auto-generated version:1 created:2026-10-06 -->

## 문제 상황
pytest 게이트가 venv 폴더 존재 여부만으로 pytest 설치를 가정하여, venv는 있으나 pytest가 설치되지 않은 상태에서 거짓 양성/음성을 낸다. 공장(claude-harness-hermes)도 이 문제를 갖고 있었고 이제 수정되었으나, 모든 소우주가 통일된 버전을 사용하는지 주기적 확인 필요.

## 규칙
- [ ] pytest 게이트(`pytest_gate.sh`)는 단순 폴더 존재가 아닌 실제 pytest 설치 여부를 `python -m pytest --version` 으로 검증할 것
- [ ] 공장과 소우주의 pytest_gate.sh 버전을 매 전파 후 체크섬으로 일치 확인
- [ ] 새 게이트 적용 후 테스트 커밋(의도적 pytest 누락)으로 동작 검증

## 근거
- 감지 횟수: 1회 (공장 자신에 대한 수정, 2026-10-06)
- 패턴 키: pytest-gate-warn-venv-folder-exists-no-pytest
