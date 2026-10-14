# isolated-config-testing
<!-- hermes:auto-generated version:1 created:2026-10-09 -->

## 문제 상황
테스트 실행 시 프로젝트 전역 설정이나 환경 변수가 테스트 결과에 영향을 미치거나, 테스트가 실행 환경의 상태에 의존하게 되는 경우. 임시 설정 파일을 사용해 테스트를 격리해야 하지만 이를 일관되게 적용하지 않으면 테스트 신뢰성이 떨어진다.

## 규칙
- [ ] 테스트마다 임시 디렉토리(`tempfile.TemporaryDirectory`, `/tmp`, 메모리 FS 등) 생성
- [ ] 전역 설정 파일(`.env`, `config.json`, `settings.yaml` 등)을 임시 디렉토리에 복사하거나 동적 생성
- [ ] 테스트 실행 전 임시 설정으로 작업 디렉토리 지정 (cwd, HOME, 환경변수 오버라이드)
- [ ] 테스트 종료 후 임시 파일·디렉토리 자동 정리 (context manager, finally, cleanup fixture)
- [ ] 테스트 간 설정 공유 금지 — 각 테스트는 독립적 임시 환경에서만 실행
- [ ] CI/로컬 환경의 전역 `.env`나 시스템 경로가 테스트를 오염시키지 않도록 cwd로 격리

## 근거
- 감지 횟수: 0회
- 패턴 키: isolated-testing-with-temp-config
