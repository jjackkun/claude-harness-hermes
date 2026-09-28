# settings-file-sync-check
<!-- hermes:auto-generated version:1 created:2026-09-28 -->

## 문제 상황
설치 또는 전파 과정에서 `settings.json`에 훅/스크립트를 등록했으나 대응 파일이 실제로 존재하지 않음. 예: `claude-posttooluse-prettier-warn.sh`가 settings.json에 등록되었지만 파일이 누락되어 doctor 검증 실패. 동일 패턴으로 `hermes_mesh_gate.py`가 import 대상인데 복사 목록에 누락됨.

## 규칙
- [ ] 새로운 훅/스크립트를 `settings.json`에 등록하기 **전에** 해당 파일이 실제로 존재하는지 확인
- [ ] 설치 또는 전파 완료 후 `settings.json`의 모든 훅 항목을 대응 파일과 매칭하여 검증 (doctor 또는 직접 grep)
- [ ] 누락된 파일을 발견했을 때는 즉시 파일 생성 또는 settings.json에서 등록 제거로 불일치 해결
- [ ] 전파 시 복사 목록·settings.json 등록·실제 파일 세 곳을 모두 일치시키는 체크리스트 사용

## 근거
- 감지 횟수: 3회+
- 패턴 키: settings.json
