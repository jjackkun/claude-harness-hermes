# revalidate-benchmarks-for-local-model-substitute
<!-- hermes:auto-generated version:1 created:2026-10-01 -->

## 문제 상황
로컬 모델(Jeff)을 기존 원격 API(Jev/jevgrep) 대신 사용할 때 공식 벤치마크 점수만으로 적합성을 판단하고, 프로젝트 저장소의 **실제 사용 사례**에서 재측정하지 않는 실수. 특히 코드 의미 추론이 필요한 작업에서 Jeff의 성능 저하(20~30%)를 간과할 위험.

## 규칙
- [ ] 공식 벤치마크(Jeff: BBH 64~68, JudgeBench 60~64 vs Jev: BBH 94.3, JudgeBench 78.6)만으로 충분하다고 판단하지 말 것
- [ ] 우리 저장소의 **실제 사용 사례**(jevgrep의 코드 의미 이해 작업)에서 동일 데이터 세트로 Jeff와 Jev를 직접 비교 실측 필수
- [ ] 응답 시간: Jeff CPU 처리(463ms) vs Jev API 지연(114~212ms) 합산 실측으로 네트워크 이득 재확인
- [ ] 벤치마크 저하폭(20~30%)이 프로젝트 요구사항 범위 내인지 명시적으로 검증 후 기록

## 근거
- 감지 횟수: 1회
- 패턴 키: jeff-inference-performance-benchmark
