# sync-git-hooks-from-factory-source
<!-- hermes:auto-generated version:1 created:2026-10-07 -->

## 문제 상황
`.git/hooks/` 디렉토리의 헬퍼 스크립트(`pytest_gate.sh`, `doc_counts.py` 등)가 `assets/hooks/` 원본보다 낡은 버전으로 남아 있음. 공장 커밋이 원본을 수정해도 로컬 복사본이 자동 갱신되지 않아, 테스트 게이트 동작이 불일치. 공장 자신의 `.git/hooks/`와도 버전 불일치 발생.

## 규칙
- [ ] 세션/커밋 전: `assets/hooks/` 원본과 `.git/hooks/` 복사본의 파일 목록·타임스탬프 비교
- [ ] 원본이 더 최신이면 `cp assets/hooks/<script> .git/hooks/<script>`로 갱신 (백업은 선택)
- [ ] 공장 저장소의 `.git/hooks/`도 동일 버전으로 관리 — 공장 커밋이 변경하면 로컬도 따라가야 함
- [ ] 갱신 후 `bash .git/hooks/<script> --version` 또는 스크립트 헤드 주석으로 버전 확인
- [ ] backward compatibility 검증: 새 스크립트가 기존 호출처(`.git/hooks/pre-commit` 등)와 호환되는지 테스트

## 근거
- 감지 횟수: 2회
- 패턴 키: pytest-gate-helper-script-backward-compatible
