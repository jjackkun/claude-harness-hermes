# official-source-for-sonnet-55-settings
<!-- hermes:auto-generated version:1 created:2026-10-02 -->

## 문제 상황
Sonnet 5에서 5.5로 모델을 업그레이드한 후, effort 설정값(high)의 의미가 변경됨. metallab.ai 같은 비공식 소스에서 설정을 찾으면 정보 오류 발생. claude.dev 공식 문서에서 재보정 필요.

## 규칙
- [ ] 모델 버전 업그레이드 시(5.0 → 5.5 등) ~/.claude/settings.json의 effort 값을 claude.dev 공식 문서에서 재확인
- [ ] "Building with Claude Sonnet 5.5" 등 공식 가이드에서 사고량(thinking tokens) 정책 확인 후 설정 조정
- [ ] metallab.ai 등 비공식 기술 블로그는 참고만 하고, claude.dev를 단일 출처로 삼기
- [ ] Sonnet 5 사고 블록과 5.5 extended thinking의 차이(역호환 불가) 인식 후 프롬프트 조정

## 근거
- 감지 횟수: 1회 (이번 세션)
- 패턴 키: sonnet-55-official-source-claude-dev
