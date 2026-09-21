# TypeSafe Jev 검토 폴더

> 작성일: 2026-09-21
> 목적: TypeSafe AI 의 결정 전용 모델 Jev 를 하네스에 붙일지 판단하는 자료를 한곳에 모은다.

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
