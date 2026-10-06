# hermes-sync-verdict-only

<!-- hermes:auto-generated version:1 created:2026-10-02 -->

## 문제 상황

hermes-sync가 판정(verdict) 정보만 운반해야 하는데, 원본 대화 텍스트나 민감 정보까지 포함시키는 경향. 프라이버시 경계와 재구성 가능성이 혼란스러워짐.

## 규칙

- [ ] hermes-sync는 **verdict(판정)** · **pattern count(패턴 수)** · **common summary(공통 요약)**만 포함
- [ ] 원본 대화 텍스트(raw transcripts, 원문)는 절대 저장하지 않기
- [ ] 개인적·업무 무관 문장은 `python3 scripts/hermes-privacy-review.py` 로 필터링한 뒤만 파일에 기록
- [ ] 커밋 전 R-privacy 게이트 통과 확인
- [ ] `.hermes/sync.json` 이 "원본 없이 재구성 가능한 형태"(verdict+metadata)만 포함하는지 감사

## 근거

- 감지 횟수: 3회 (hermes-sync 프로토콜 정의 중)
- 패턴 키: hermes-sync-carries-verdict-only-not-original
- 관련 문서: CLAUDE.md «운반» 섹션 · scripts/hermes-privacy-review.py · R-privacy 커밋 게이트
- 설계 원칙: "협업 화면은 공유 기록 파일을 읽는 얇은 층" → 원본 아닌 판정만 유통
