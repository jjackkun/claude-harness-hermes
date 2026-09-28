# hermes-preset-installation-verify
<!-- hermes:auto-generated version:1 created:2026-09-14 -->

## 문제 상황
Hermes 프리셋 설치 후 "정말 적용됐나?"를 확인할 때, 파일시스템·설정·세션 적용을 구분하지 않고 같은 질문을 반복하며, history 폴더나 hooks.log 누적이 정상인지 불안해함. 전파 구조(원본 소스)를 모르면 설치 실패를 진단할 수 없음.

## 규칙
- [ ] **3단계 검증 분리**: ① 프리셋 파일 시스템 존재 (`~/.claude/presets/`, `/scripts/hooks/`) ② `settings.json` 레지스트리 기록 (enabledPlugins, RULES+=) ③ 세션 재시작 필요 여부 **명시** — 설정만 변경하면 현 세션에 즉시 반영 안 됨
- [ ] **원본 소스 단일 확인**: history/hooks.log 누적은 정상 (state.db는 이들의 파생물, 재생성 불가역). 전파 구조는 `lib/harness_installers.sh:34` 의 `install_harness_hooks()` 한 곳만 확인
- [ ] **프리셋별 검증 경로 구분**: 전역(~/.claude/) vs 프로젝트(.claude/) 설치 위치 다름 — 질문 직후 그 구분을 명시
- [ ] 기존 문서 diff 우려는 Hermes 특성상 "세션 컨텍스트 타이밍(로드 시점 고정)" 설명으로 **한 번에 종료** (반복 재설명 금지)

## 근거
- 감지 횟수: 4회
- 패턴 키: hermes
