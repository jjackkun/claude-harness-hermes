# production-assets-need-pixel-tools
<!-- hermes:auto-generated version:1 created:2026-11-19 -->

## 문제 상황
Claude Code 에디터에서 생성한 스프라이트·그림을 출시 품질 에셋으로 취급하려는 경향. sprite-gen 같은 도구도 Claude 구독만으로는 동작 프레임 자동 생성 같은 고급 기능 미제공.

## 규칙
- [ ] Claude Code에서 생성한 에셋(스프라이트, 그림, 애니메이션 프레임)은 프로토타입·학습용만 사용
- [ ] 프로덕션/출시 품질 에셋이 필요하면 전문 픽셀 도구(pixel-draw, Aseprite, Piskel) 또는 에셋 팩 사용
- [ ] 에셋 도구(sprite-gen 등)도 Claude 구독만으로는 부족 — ChatGPT/xAI나 오픈소스 대체(glt 저장소) 검토 필요
- [ ] 에셋 용도 불명확 시 "프로토타입/최종 중 어느 것"을 먼저 확인
- [ ] 최종 품질 필요 시 도구·팩 선정을 협의하고 그 뒤 작업 진행

## 근거
- 감지 횟수: 3회 (D9: 프로토타입용만, D10: pixel-draw 구현 필요, D13: Claude 미제공 기능)
- 패턴 키: claude-code-asset-prototyping-only
- 출처: game-dev 2026-11월 세션 (jj-agent-room 기록)
