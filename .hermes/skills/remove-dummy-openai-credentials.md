# remove-dummy-openai-credentials
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
LLM 구독 경로 통합(R3) 후 OPENAI_API_KEY 더미값과 구 설정 파일이 환경·훅에 남아 있음. 
새 pre-commit 훅 파일(`.git/hooks/pre-commit.factory-new` 등) 정리 누락으로 커밋이 중복 실행됨.

## 규칙
- [ ] 구독 CLI로 LLM 마이그레이션 후, `OPENAI_API_KEY` 를 grep으로 전체 스캔
- [ ] 환경 파일에서 가짜값(더미 토큰, 'sk-...', 'xxx' 등) 제거
- [ ] `.git/hooks/pre-commit.factory-*` 같은 임시 훅 파일 삭제
- [ ] 커밋 **전에** `git status` 로 `.git/hooks/` 잔존 파일 확인
- [ ] 환경변수 설정 검증: 구독 CLI만 사용되는지 로그로 확인

## 근거
- 감지 횟수: 2회
- 패턴 키: openai
