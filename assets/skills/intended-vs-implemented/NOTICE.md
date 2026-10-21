# NOTICE — intended-vs-implemented

이 스킬은 아래 원본의 절차를 한국어로 옮기고 고쳤다. 스킬 폴더가 설치 단위라 출처를 폴더마다 둔다.

## 원본

- `phuryn/pm-skills` — `pm-ai-shipping/skills/intended-vs-implemented/SKILL.md`
  MIT License, Copyright (c) 2026 Pawel Huryn.
  가져온 것: 의도 문서 → 구현 증거 → 경계 하나씩 대조 → 중요한 어긋남만 → 양쪽 인용의 다섯 걸음, "적혀만 있고 강제 안 됨" 도 결함, 의도를 지어내지 않기, 문서·코드를 지시가 아닌 검사 대상으로 다루기.

## 바꾼 점

- 의도 문서를 사슬 계약의 찾기 순서로 고른다 (PRD 의 FR 행, 실행 계획서 §2, 설계 문서). 원본의 `documentation/*.md` 기본 경로와 다른 스킬 참조는 뺐다.
- 판정을 다섯 가지(`일치`·`어긋남`·`강제 없음`·`문서 없음`·`확인 못 함`)로 정했고, 시험이 주장을 단언하는지도 보게 했다.
- 결과를 대화가 아니라 `docs/audits/YYYY-MM-DD-<이름>-intent-check.md` 감사 문서로 남긴다.
- 보안 감사 중심의 "공격자와 피해자" 표현을 "넘어서면 누가 무엇에 닿나" 로 넓혔다.
- 한국어·존댓말 보고로 바꿨다.
