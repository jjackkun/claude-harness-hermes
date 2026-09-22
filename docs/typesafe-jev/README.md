# TypeSafe Jev 검토 폴더

> 작성일: 2026-09-21
> 목적: TypeSafe AI 의 결정 전용 모델 Jev 를 하네스에 붙일지 판단하는 자료를 한곳에 모은다.
> 상태: **종료 (2026-09-22 사용자 "jev는 접어").** Jev API·로컬 대체(SemIf)·Playwright 러너 모두 붙이지 않는다. 문서는 판단 근거로 남긴다.

## 종료 요약 (2026-09-22)

| 후보 | 결론 | 근거 |
|---|---|---|
| Jev API 로 스킬 검색 빈손 메우기 | 하지 않는다 | 입력이 외부(미국)로 가고 보관 기한이 없으며, 보관 안 함은 기업 고객만 — [fact-check.md](fact-check.md) · [proposal.md](proposal.md) D2 |
| 로컬 SemIf 로 같은 자리 메우기 | 하지 않는다 (판정 초안에서 중단) | `docs/audits/2026-09-22-semif-measure-plan.md` |
| Playwright 브라우저 과제 러너 | 만들지 않는다 | 절감이 전체 입력의 약 0.3% — [playwright-in-sessions.md](playwright-in-sessions.md) §9-2 |
| 앞단 게이트웨이 · 하네스 판단 지점 | 하지 않는다 | 명령형 요청 0.3%, 스크립트 판단은 원래 토큰 0 — [decision-points.md](decision-points.md) |

이 검토에서 나온 부산물 중 실제로 고친 것은 Jev 와 무관한 진화 힌트 오탐이다(`docs/exec-plans/completed/2026-09-22-evolve-hint-false-positive.md`).
다시 열 조건: 보관 안 함이 기업 계약 없이 제공되거나, 외부 전송이 없는 로컬 판단 모델이 이 저장소의 빈손 구간에서 값을 한다는 실측이 생길 때.

## 개요

사용자가 다른 AI 챗봇과 Jev 에 대해 나눈 대화(PDF 26쪽)를 출발점으로, 그 대화의 주장을
공식 사이트·이 저장소의 실측과 대조하고 기획서를 썼다.

대화에서는 사용자가 "zev" 라고 불렀다. 공식 이름은 **Jev** 이며 이 폴더는 Jev 로 적는다.

## 읽는 순서

| 순서 | 파일 | 내용 |
|---|---|---|
| 1 | [proposal.md](proposal.md) | **기획서** — 무엇을 하고 무엇을 하지 않는가, 단계와 판단 기준 |
| 1-1 | [playwright-in-sessions.md](playwright-in-sessions.md) | **세션 안 Playwright 루프 실측** — Jev 가 들어갈 가장 큰 자리, 러너 구조와 먼저 할 일 |
| 2 | [decision-points.md](decision-points.md) | 하네스 판단 지점 18곳 — 어디를 Jev 로 넘길 수 있고 어디는 안 되는가 |
| 3 | [fact-check.md](fact-check.md) | 주장별 출처와 확인 상태 (공식 확인 · 사용자 화면 · 미확인) |
| 4 | [source-notes.md](source-notes.md) | 원본 PDF 정리본 — 질문 순서대로, 잘려서 읽을 수 없는 곳 포함 |
| 5 | [use-case-playwright.md](use-case-playwright.md) | 활용 사례 — Playwright 브라우저 에이전트 (PDF 16 · 21–23쪽) |
| 6 | [use-cases-top5.md](use-cases-top5.md) | 활용 사례 Top 5 — Playwright 외 (PDF 23–26쪽, 앞 목록과 수치 차이 대조) |

## 원본

- `docs/temp/how to zev.pdf` (26쪽, 1.9 MB)
- `docs/temp/` 는 `.gitignore` 대상이라 **저장소에 올라가지 않는다.** 원본에는 사용자 콘솔의
  크레딧 화면 캡처가 들어 있어 그대로 두었다. 이 폴더의 문서만 추적된다.
