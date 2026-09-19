# council — 설계 결정에 구조적 반론(다중 시선) 을 넣는다

> 출처: `docs/audits/2026-09-19-ecc-gap-list.md` (ECC v2.2.1 대비 결핍 목록, 사용자 "다 필요한 것들" 확정 2026-09-19) — #9 (가치 중)

## 문제

C-21~C-26 같은 설계 결정은 `architect-lite` 한 시선으로 검토된다(R7). 반대 입장을 맡는 검토자가 없어 결정이 확정 편향으로 굳는다.

## ECC 의 실체

`skills/council/` — 네 목소리(찬성·반대·비용·운영) 로 구조적 반론 뒤 종합. `council-multi-model/` 은 Codex 로 외부 비판 1회.

## 고칠 때 후보

- 새 에이전트 `assets/agents/devil-advocate.md`(Read·Grep·Glob 만): "이 결정이 틀렸다면 어디서 틀렸나" 만 답한다. 모델은 sonnet.
- R7 표에 `*-design.md` 저장 시 architect-lite **다음에** devil-advocate 를 붙일지 사용자에게 한 번 묻는 행 추가. 자동 실행 아님.
- 다중 모델 반론은 R3(구독 CLI 단일 경로) 안에서 Codex 세션 프리셋이 있는 소우주에만 — 선택.

## 착수 조건

다음 `*-design.md` 작성 시점에 한 번 시험해 본 뒤 유지 여부 결정. 사람이 먼저 "반론이 유용했다" 고 말해야 남긴다.
