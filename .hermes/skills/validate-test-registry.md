# validate-test-registry
<!-- hermes:auto-generated version:1 created:2026-09-22 -->

## 문제 상황
`tests/run-all.sh`에 등록되지 않은 테스트 파일이 축적되고, hermes 모듈 복사 목록에서 필요한 파일이 누락되어 실제 런타임 오류가 발생. 예: `hermes_mesh_gate.py`가 복사 목록에 없어서 `hermes-propose.py` 호출 시 `ModuleNotFoundError`.

## 규칙
- [ ] `tests/run-all.sh`의 `REGISTERED_TESTS` 배열에 모든 테스트 스크립트 명시적 등록
- [ ] 매 커밋 전 `--check-orphans` 옵션으로 고아 테스트 자동 감지
- [ ] hermes 모듈의 `import` 문을 정적 분석(grep)으로 추출하고 복사 목록과 실시간 검증
- [ ] 복사 대상 누락 발견 시 CI 게이트에서 차단

## 근거
- 감지 횟수: 4회
- 패턴 키: run-all.sh
