# 커뮤니티 프로젝트 모음 — 사람들은 Jev 로 무엇을 하나

> 작성일: 2026-09-22
> 목적: Jev 로 만든 프로젝트를 모아 둔 아카이브 사이트 3곳과 각 사이트의 성격을 적어 둔다.

## 개요

Threads 사용자 leonkkkkk 가 올린 글에서 출발했다. 원문은 아래와 같다.

> 사람들은 Jev로 무얼 하고 있을까:
> Jev 프로젝트들을 모아 소개해주는 아카이브 링크를 몇개 정리해본다.
> - jevable.com
> - logicrw.github.io/aweso…
> - madewithjev.com
>
> 항공편 검색부터 이력서/포지션 매칭까지 정말 다양한걸 그 짧은 시간동안 만드는 걸 보면 에너지를 리스펙하게된다.

원문에서 잘린 두 번째 링크의 전체 주소는 `https://logicrw.github.io/awesome-jev-projects/ko/` 이다.

이 폴더의 검토는 종료됐다([README.md](README.md) 종료 요약). 이 문서는 다시 열 조건을 볼 때 참고할 **바깥 사례 모음**이며, 붙이는 결정을 바꾸지 않는다.

## 사이트 3곳

아래 운영자·개수·예시는 2026-09-22 에 각 사이트 첫 화면을 열어 확인한 값이다. 사이트가 스스로 밝힌 숫자이고 이 저장소에서 따로 세지 않았다.

| 사이트 | 성격 | 운영 | 규모 (사이트 표기) |
|---|---|---|---|
| <https://jevable.com/> | 완성 프로젝트 쇼케이스 갤러리 — 에이전트·게임·개발 도구·생산성 앱 | Nikunj Kothari | 프로젝트 194개 |
| <https://logicrw.github.io/awesome-jev-projects/ko/> | 오픈소스 프로젝트 목록 (awesome 리스트, 한국어 페이지) — 사람이 확인한 항목만 싣는다고 밝힘 | @0xLogicrw | 약 478개, 17개 분류 |
| <https://madewithjev.com/> | 빌드·가이드·사용 사례 갤러리 (Peerlist 에서 큐레이션) | Jon Kraayenbrink (@kraayenjon) | 빌드 457 · 가이드 105 · 사용 사례 8 |

### jevable.com — 무엇을 만들었나

- Drape — 영상으로 옷을 입혀 보는 실시간 가상 피팅 (약 620ms)
- Mario Never Dies — 마리오가 죽을 때마다 Jev 가 갈림길을 골라 조종하는 게임
- Instant Generative UI — JSON 으로 화면 부품을 밀리초 단위로 만든다
- An Autonomous Trading Experiment — Jev 에 $10,000 를 맡겨 스스로 매매하게 한 실험
- Search Your Inbox by Intent — Gmail 을 의도(자연어)로 검색

### awesome-jev-projects — 어디에 붙였나

기존 오픈소스 도구에 Jev 를 **판단 단계로** 끼운 사례가 많다. 가장 큰 분류는 SDK·결정 프레임워크(90개)이고, 브라우저 자동화·모델 라우팅·컨텍스트 관리·보안·평가 분류가 있다.

- LangChain — Python 워크플로에 Jev 분류를 선택 기능으로 붙임
- LiteLLM — 요청의 복잡도를 Jev 로 판정해 모델을 고른다
- Composio — 도구와 인자 선택을 Jev 로
- Browser-use — 텍스트 생성 없이 DOM 에서 다음 동작을 고른다
- Pydantic AI — 정형 출력 필드를 Jev 질문으로 바꾼다

### madewithjev.com — 얼마나 들었나

사례마다 걸린 시간과 비용을 함께 적어 둔 것이 특징이다.

- Flight search with Browser Use — 항공편 검색 7초, $0.004
- AI Slop Detector — 웹사이트의 AI 생성 흔적 35가지를 243ms, $0.00015 에 검사
- Fraud detection with Jev and Kimi K3 — 메일 100통 분류, 정확도 96%, 약 $0.07
- Jev plays Super Mario Bros — 빠른 추론과 정형 출력으로 게임을 실시간 플레이
- Post scoring with SuperX — 초안 하나에 질문 61개로 바이럴 가능성 채점, 약 1초, $0.0004

## 이 폴더의 다른 문서와 이어지는 곳

| 사이트에서 보인 사례 | 이 폴더에서 다룬 곳 |
|---|---|
| Browser-use · 항공편 검색 (브라우저 다음 동작 결정) | [use-case-playwright.md](use-case-playwright.md) · [playwright-in-sessions.md](playwright-in-sessions.md) |
| LiteLLM (복잡도 라우팅) · Composio (도구 선택) | [use-cases-top5.md](use-cases-top5.md) 2번 라우터 · [decision-points.md](decision-points.md) |
| 사기 탐지 | [use-cases-top5.md](use-cases-top5.md) 3번 |

사이트에 적힌 시간·비용은 각 제작자의 주장이다. 원본 대화의 수치와 같은 방식으로 [fact-check.md](fact-check.md) 기준에서는 **미확인**으로 본다.
