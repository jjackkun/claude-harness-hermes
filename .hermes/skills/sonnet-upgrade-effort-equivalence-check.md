# sonnet-upgrade-effort-equivalence-check
<!-- hermes:auto-generated version:1 created:2026-10-01 -->

## 문제 상황
Sonnet 5에서 Sonnet 5.5로 모델을 업그레이드할 때, 기존 `effort: high` 설정이 새 모델에서 동등한 사고량/동작을 보장하지 않음. 버전 간 thinking 블록 호환성 차이(5.5는 5의 블록을 읽을 수 있지만 역은 불가)로 인해 재보정 필요.

## 규칙
- [ ] 모델 버전 전환 후 공식 마이그레이션 가이드(claude.dev 'Building with Claude Sonnet 5.5') 먼저 확인
- [ ] 기존 effort 설정값이 새 모델에서 동등한지 실측으로 검증 (단순 추측 금지)
- [ ] Sonnet 5.5는 Sonnet 5 thinking 블록을 읽을 수 있으나 역은 불가능함을 인식
- [ ] effort 레벨 변경 시(high→medium 또는 유지) 관련 작업 다시 실행 후 비교
- [ ] metallab.ai 등 비공식 출처 대신 claude.dev 공식 문서를 우선 참조

## 근거
- 감지 횟수: 1회
- 패턴 키: sonnet-5-effort-high-not-equivalent-55
