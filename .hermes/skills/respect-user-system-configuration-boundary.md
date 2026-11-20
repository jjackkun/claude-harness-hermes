# respect-user-system-configuration-boundary
<!-- hermes:auto-generated version:1 created:2026-11-19 -->

## 문제 상황
Code Mode 설정, 설치 범위, 푸시 대상 같은 사용자 시스템 범위의 선택을 프로젝트 공장에 포함시키거나 프로젝트별로 전파하려는 실수 반복. 세션마다 사용자에게 "이건 사용자 컴퓨터 설정이지 프로젝트 범위가 아니다"를 다시 설명하게 됨.

## 규칙
- [ ] Code Mode 설정(CLAUDE_CODE_EXPERIMENTAL_CODE_MODE)은 ~/.claude/settings.json에서만 읽고, 프로젝트 .claude.json이나 공장 설치에 포함하지 않는다
- [ ] 설치(~/.local/bin, 사용자 플러그인)는 프로젝트별 전파 대상이 아니다. 전역 범위로 사용자에게 명시한다
- [ ] ~/.claude/settings.json은 읽기만 하고 수정하지 않는다. 사용자가 직접 편집하도록 안내한다
- [ ] 푸시는 사용자가 명시적으로 지시한 저장소에만 한다. "전체 푸시해"를 모든 프로젝트로 해석하지 않는다
- [ ] 컴퓨터별 설정 차이(Code Mode 초기값, 설치 여부)를 사용자에게 명확히 알린다

## 근거
- 감지 횟수: 3회
- 패턴 키: 사용자
