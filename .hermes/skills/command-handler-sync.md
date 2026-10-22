# command-handler-sync
<!-- hermes:auto-generated version:1 created:2026-10-22 -->

## 문제 상황
헤르메스 에이전트에 새 명령(command)을 추가할 때 명령 핸들러·도구 등록·문서 선언이 불일치하거나 누락되는 현상.
docs-lookup에서 도구 이름이 실제 구현과 다르고, doc-updater·run-to-the-end 등에서 등록되지 않은 명령을 참조하려다 실패.

## 규칙
- [ ] 새 에이전트 명령 추가 시 `hermes_hag_commands.py`에 핸들러 함수 정의
- [ ] 도구 이름(tool_name) = 명령 함수명 일치 확인 (예: `docs_lookup` → `def docs_lookup(...)`)
- [ ] 에이전트 manifest (또는 registry)에 명령 등록 (이름·설명·모델·권한)
- [ ] 명령을 참조하는 다른 모듈(doc-updater, run-to-the-end, boundary-check)에서 실제 존재 여부 확인
- [ ] 커밋 전 `hermes-agent.py --list` 로 등록된 명령 목록 검증

## 근거
- 감지 횟수: 3회+ (도구 이름 불일치·누락 명령·경로 오류)
- 패턴 키: command-message
