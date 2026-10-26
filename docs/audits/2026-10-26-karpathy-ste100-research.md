# 카파시 "LLM 출력 이해" 팁과 ASD-STE100 조사

> 작성일: 2026-10-26
> 목적: 사용자가 전해 준 스레드(jokerburg.builder, 2026-10-03)의 원문과 근거를 확인하고, STE 규칙을 공장에 들일 근거를 남긴다.

## 개요

- 원문: 안드레이 카파시의 X 게시물, 2026-10-02 전후. **전문을 실은 2차 자료는 찾지 못했다** — 아래는 짧은 인용과 요약뿐이다.
- 주장: "We'll be spending a lot more time trying to understand the outputs of language models." 이해를 돕는 출력 형식 4단계를 낸다.
- 공장에 들일 것: 1단계(STE 문장 규칙)만. 2~4단계는 이미 다른 장치가 있다(아래 표).

## 원문에서 확인된 것 (인용은 2차 자료 기준)

| 단계 | 원문 표현 | 출처 |
|---|---|---|
| 1. ASD-STE100 | 모델이 규격을 잘 알고, "heavy constraints on clean writing style" 덕에 "a lot more readable". 규격이 "quite stringent" 하므로 "80% of the way to ASD-STE100" 로 요청하기도 한다 | SEJ |
| 2. 다이어그램 | "a lot easier to process, parse, and understand" | SEJ |
| 3. HTML | "in HTML" 로 요청하면 상호작용 웹페이지 | SEJ |
| 4. 설명 영상 | "most bullish on". 예: "3b1b style" + ElevenLabs 내레이션. "This is actually starting to work!" | SEJ |
| 맺음 | "large, custom, discardable software artifacts" 를 요청하라 | SEJ |

## 스레드 치트시트(2번째 이미지)의 오류

max.nardit.com 이 Issue 9 원문과 대조한 결과. 수치 제한(20/25단어, 6문장, 명사 묶음 3) 과 승인 동사형 6가지는 맞다.

| 치트시트 | 실제 규격 |
|---|---|
| `approximately` 비승인 → ABOUT | APPROXIMATELY 는 승인 부사. ABOUT 은 "~에 관하여" 전치사로만 승인 |
| `TEST` 승인 동사 | 명사로만 승인 ("DO A FUNCTIONAL TEST") |
| 서술문 수동태는 "필요할 때" | 행위자를 **모를 때만** |
| "noun cluster", "technical name" | Issue 9 용어는 "multi-word noun", "technical noun" |

## STE 규칙 중 한국어로 옮길 수 있는 것

규격 사전(약 900 낱말)은 영어 전용이라 옮길 수 없다. 카파시의 "80%" 와 같은 뜻으로, **문장 규칙만** 옮긴다.

| STE 규칙 | 한국어 판 |
|---|---|
| 5.2 한 문장 한 지시 | 한 문장 한 사실·한 지시 |
| 2.1 명사 묶음 3개 이하 | 같음 |
| 3.2 단순 시제 · 3.6 능동태 | 피동("~되었습니다")·진행("~하고 있습니다") 대신 행위자 + 단순 시제 |
| 4.2 낱말 생략 금지 | 주어(행위자) 생략 금지, 개조식 명사 종결 금지 |
| 1.2 한 낱말 한 뜻 | 같은 대상에는 같은 낱말 |
| 조건을 지시 앞에 | 같음 |
| should/may/might 금지 | 근거 없이 흐리지 않고 확인한 방법(실행·읽음·추정·모름)을 쓴다 |
| 7절 안전 지시 (WARNING/CAUTION) | "경고:"·"주의:" 로 시작, 지시 다음에 위험 |
| 8.1 세미콜론 금지 | 옮기지 않음 — 한국어에 대응 문장부호가 없고, 줄표 금지로 넓히면 decision-ledger 칸 형식과 충돌 |

## 사용자 실측 샘플

사용자가 "너무 좋다" 고 한 실제 출력(스레드 첫 캡처, bizops 보고) 16문장을 세었다.

| 잰 것 | 값 |
|---|---|
| 서술어 2개 초과 문장 | 0 / 16 |
| 가장 긴 명사 묶음 | 3 ("색인 반영 전 기준선", "핸드오프 §2 대기 줄") |
| 행위자 없는 문장 | 0 — 모든 문장이 블록 제목(bizops / 제가 / 사용자)으로 행위자를 갖는다 |
| "사용자가 하실 일" 이 비었을 때 | "없습니다" 를 적고 이유 한 문장 |

## 참고 구현

- `AminBlg/SimpleEnglish` (MIT, 영어 전용): 96 생성물에서 STE 린터 위반 72.9% 감소라고 보고. 단, 같은 계열 모델이 채점했고 칸당 1회 실행이며, 린터 수치는 "규칙 준수" 이지 "읽는 사람이 보는 것" 이 아니라고 저장소가 스스로 밝힌다. 사전은 포함하지 않는다.

## 2~4단계는 이미 있다

| 단계 | 지금 쓸 수 있는 장치 |
|---|---|
| 다이어그램 | `artifact-diagramming` 스킬 (기본 제공, 공장 것 아님) |
| HTML | Artifact 도구, `ui-prototype` 스킬 |
| 영상 | `video-to-interaction` 스킬 (2026-10-22, 입력 쪽) — 설명 영상 생성은 없음 |

## 출처

- https://www.searchenginejournal.com/karpathy-llm-aircraft-manual-writing/591813/
- https://max.nardit.com/articles/karpathy-understanding-llm-outputs
- https://ralmodiel.github.io/ai-study-library/notes/04-prompting/2026-10-02-karpathy-s-tip-ask-llms-to-explain-in-asd-ste100.html
- https://explainx.ai/blog/asd-ste100-simplified-technical-english-ai-skill-2026
- https://github.com/AminBlg/SimpleEnglish
- https://en.wikipedia.org/wiki/Simplified_Technical_English
