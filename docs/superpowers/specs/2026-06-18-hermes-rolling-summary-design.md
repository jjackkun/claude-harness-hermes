# 헤르메스 롤링 요약 메모리 설계

> 작성일: 2026-06-18
> 목적: 핑퐁(대화 1왕복)마다 대화를 5슬롯 구조로 롤링 요약해 저장함으로써, 전체 transcript를 들고 있지 않아도 맥락을 빠짐없이 보존하고 다음 세션이 그 맥락을 이어받게 한다. 이 요약은 추후 B(드리밍) 통합 엔진의 연료가 된다.

## 개요

현재 헤르메스는 세션 종료(Stop 훅)마다 **원본 transcript를 통째로 저장(`session_history`)**하고, 거기서 반복 토큰을 뽑아 패턴·스킬로 결정화한다. 즉 "반복되는 실수·패턴"은 선별 학습하지만, **그날 오간 대화의 맥락(무엇을 정했고, 무엇이 미해결이고, 사용자가 무엇을 원했는지)** 자체는 구조적으로 보존하지 않는다.

이 설계의 핵심 의도는 **모든 핑퐁(대화 1왕복)을 빠짐없이 맥락으로 보존**하는 것이다. 기존 헤르메스가 *3회 이상 반복된 패턴만 선별*해 학습하는 것과 달리, 이 설계는 **단 한 번만 오간 대화도 버리지 않고** 핑퐁마다 5슬롯 요약에 녹여 넣는다. "이건 중요하니 넣고 저건 사소하니 버린다"는 선별을 하지 않으며, 실제 핑퐁 하나하나가 정확히 한 번씩 요약에 반영된다(빠지는 왕복 없음). 더해 원본 `session_history`도 그대로 공존하므로, 모든 대화가 *원문 + 증류된 5슬롯 요약* 두 형태로 남는다.

이 설계는 그 빈틈을 **롤링 요약 메모리**로 메운다. 두 개의 분리된 서브시스템 중 **A(요약 메모리 토대)**에 해당하며, **B(드리밍 통합 엔진)**는 별도 설계서로 다룬다. B는 A가 만든 요약을 입력으로 쓰므로 A를 먼저 구축한다.

```
구상 분해
├── A. 롤링 요약 메모리   ← 본 설계 (맥락 보존의 토대)
└── B. 드리밍 통합 엔진   ← 별도 설계 (요약→스킬 결정화·진화·삭제, 그래프 형성)
```

### 범위 (A)

| 포함 | 제외(→ B로) |
|---|---|
| 핑퐁마다 5슬롯 롤링 요약 생성·저장 | 노트 사이 `[[링크]]`·군집·그래프 엣지 형성 |
| 세션 요약의 옵시디언 호환 `.md` 노트 내보내기 | 하루치 요약 통합·결정화·스킬 진화·삭제 |
| 직전 세션 요약 자동주입 + 명령 검색(회상) | 중요도 가중·강한 인식(드리밍 본체) |

## 핵심 메커니즘: 핑퐁마다 갱신되는 5슬롯 롤링 요약

이 설계의 심장이다. 대화를 줄글로 누적하지 않고, **정해진 5개 슬롯에 분류해 담되, 핑퐁이 끝날 때마다 "직전 슬롯 + 이번 핑퐁"만 보고 바뀐 부분만 고쳐 쓴다.**

### 5슬롯 정의

| 슬롯 | 담는 것 |
|---|---|
| `decisions` | 합의해서 정한 결정사항 |
| `open` | 아직 안 끝났거나 답을 못 정한 미해결 과제 |
| `prefs` | 사용자가 원하는 방식 / 하지 말라는 제약 |
| `facts` | 알아둬야 할 핵심 사실·맥락 |
| `next` | 바로 다음에 할 일(다음 액션) |

### 롤링 갱신 원리

```
[핑퐁 N] 사용자 질문 → 어시스턴트 답변
   직전 슬롯(JSON)  ─┐
                     ├─→ Haiku ─→ 갱신된 슬롯(JSON) ─→ session_summary 행 교체
   이번 핑퐁(델타) ─┘
```

- LLM에 넘기는 입력은 **"직전 슬롯 + 이번 핑퐁 1회분"**뿐 → 대화가 100번 오가도 입력 크기·비용이 매번 일정하다.
- 결과물은 항상 "지금까지의 맥락이 정리된 5슬롯"으로 유지된다(전체 재요약 아님).
- 트레이드오프: 요약의 요약이 누적되며 미세정보가 유실될 수 있다 → **원본 `session_history`를 그대로 공존**시켜 B 드리밍이 원본으로 교차검증하는 것으로 보완한다.

## 아키텍처

헤르메스 원칙(`hermes-engineering.md` §10·§11: **기존 Hook 확장, 새 Hook 미생성**)을 따른다. 새 Hook은 만들지 않고, 기존 두 Hook에 단계를 추가하며, 로직은 신규 `hermes-*.py` 스크립트로 분리한다(헤르메스는 이미 다수의 `hermes-*.py`를 둔다).

```
Stop Hook (claude-stop-retrospective.sh, 기존 — 매 턴 setsid 백그라운드)
  └→ hermes-save-session.py      (기존: 원본 transcript 저장 — 유지)
  └→ hermes-summarize.py         (신규: 델타 추출 + Haiku 롤링 요약 + 행 교체 + .md 내보내기)

UserPromptSubmit Hook (claude-userpromptsubmit-mistake-detect.sh, 기존)
  └→ (기존: A신호 키워드 감지 — 유지)
  └→ hermes-recall.py --inject   (신규: 세션 첫 프롬프트면 직전 세션 요약 주입)
```

회상 자동주입은 **새 SessionStart 훅을 만들지 않고**, 기존 UserPromptSubmit 훅이 "이 세션에서 아직 주입한 적 없음"을 확인해 첫 프롬프트에 1회 주입하는 방식으로 처리한다.

## 데이터 흐름

```
[매 핑퐁] Stop 훅 발동
   1. hermes-save-session.py — 원본 transcript 저장 (기존)
   2. hermes-summarize.py
        a. session_summary 에서 이 session_id 의 직전 슬롯(JSON)·last_msg_count 로드
        b. transcript 에서 last_msg_count 이후의 새 핑퐁만 추출(델타 = messages[last_msg_count:])
        c. 델타 없으면 종료 (재저장·중복 방지 — 기존 C2 가드와 동일 원리)
        d. Haiku 호출: [직전 슬롯 + 델타] → 갱신 슬롯(JSON)
        e. session_summary 행 교체, last_msg_count·turn_count·updated_at 갱신
        f. .hermes/vault/<project>-<session>.md 노트 갱신(옵시디언 호환)

[세션 첫 프롬프트] UserPromptSubmit 훅
   1. (기존) A신호 키워드 감지
   2. hermes-recall.py --inject
        a. recall_marker 에 이 session_id 가 있으면 종료(1회만 주입)
        b. 같은 project_id 의 가장 최근 다른 세션 요약 로드
        c. open + decisions 슬롯만 골라 additionalContext 로 출력
        d. recall_marker 에 session_id 기록
```

## 저장 스키마 (`.hermes/state.db`)

```sql
-- 롤링 요약 (세션당 1행, 핑퐁마다 교체)
CREATE TABLE session_summary (
  session_id     TEXT PRIMARY KEY,
  project_id     TEXT,
  slots_json     TEXT,        -- {"decisions":[...],"open":[...],"prefs":[...],"facts":[...],"next":[...]}
  last_msg_count INTEGER,     -- 델타 추적: 지금까지 요약에 반영한 transcript 메시지 개수
  turn_count     INTEGER,
  updated_at     DATETIME
);

-- 회상 1회 주입 가드 (세션당 1회만 자동주입)
CREATE TABLE recall_marker (
  session_id  TEXT PRIMARY KEY,
  injected_at DATETIME
);
```

원본 `session_history`(FTS5)는 변경 없이 그대로 공존한다.

## 표현 레이어: 옵시디언 호환 Vault (하이브리드)

SQLite는 운영 엔진(빠른 질의·델타 추적·결정화), 옵시디언 Vault는 표현(사람이 읽고 탐색, 그래프 시각화)으로 역할을 나눈다.

- `hermes-summarize.py`가 세션 요약을 `.hermes/vault/<project>-<session>.md` 노트 1장으로 함께 내보낸다.
- 노트는 frontmatter + 5슬롯 섹션으로 구성하며, 사용자가 `.hermes/vault/`를 옵시디언 Vault로 열면 즉시 탐색 가능하다.
- **노트 사이의 `[[링크]]`·군집·그래프 엣지(진짜 "뇌")는 A 범위가 아니라 B 드리밍의 산출물**이다. A는 링크 없는 노트들을 쌓아 두는 데까지만 한다.
- `.hermes/vault/`는 `.gitignore` 권장(개인 대화 맥락이므로 저장소에 커밋하지 않음).

## 신규/수정 파일

| 파일 | 책임 | 신규/수정 | 예상 |
|---|---|---|---|
| `scripts/hermes-summarize.py` | 델타 추출 + Haiku 롤링 요약 + 행 교체 + .md 내보내기 | 신규 | ~150줄 |
| `scripts/hermes-recall.py` | 요약 조회·포맷(`--inject` 자동주입 / 키워드 검색) | 신규 | ~90줄 |
| `scripts/hermes-init.py` | `session_summary`·`recall_marker` 스키마 추가 | 수정 | +25줄 |
| `assets/hooks/claude-stop-retrospective.sh` | summarize 단계 연결 | 수정 | +5줄 |
| `assets/hooks/claude-userpromptsubmit-mistake-detect.sh` | recall 자동주입 단계 연결 | 수정 | +5줄 |
| `tests/hermes-pipeline-test.sh` | 롤링 요약·델타가드·회상 회귀 테스트 | 수정 | +60줄 |

`hermes-summarize.py`가 150줄에 근접하므로, 델타 추출·LLM 호출·노트 내보내기 책임이 한 파일에서 비대해지면 `hermes-vault.py`(노트 내보내기)로 분리한다.

## 에러 처리 / 비용 가드

- **델타 없음** → LLM 호출 자체를 건너뜀(불필요 비용 0). 재저장으로 인한 중복요약 차단.
- **Haiku 호출 실패** → 이전 슬롯 보존, `.hermes/hooks.log` 기록, 다음 턴 재시도.
- **JSON 파싱 실패** → 1회 재시도 후 스킵(원본 `session_history`는 이미 안전하므로 데이터 손실 없음).
- **요약 모델** → 기존 결정화와 동일하게 Haiku(저비용) 사용.
- 모든 단계는 Stop 훅의 `setsid` 백그라운드에서 돌아 **사용자 대기 시간에 영향 없음**.

## 테스트

`tests/hermes-pipeline-test.sh` 확장:

1. 가짜 transcript 주입 → `session_summary` 행 생성, 5슬롯 채워짐 검증.
2. 같은 session_id 재저장 → 델타 가드로 중복 요약·LLM 재호출 안 일어남 검증.
3. 새 핑퐁 추가 후 재실행 → 델타만 반영돼 슬롯 갱신됨 검증.
4. `hermes-recall.py --inject` → 직전 세션의 `open`+`decisions`만 출력, `recall_marker`로 2회 주입 안 됨 검증.
5. `.hermes/vault/*.md` 노트 생성·갱신 검증.

LLM 호출은 테스트에서 스텁(stub)으로 대체해 결정적으로 검증한다.

## B(드리밍)와의 경계

A는 **요약을 만들어 저장·회상**하는 데까지다. 다음은 명시적으로 B의 몫이다(본 설계 범위 밖):

- 하루치 세션 요약을 모아 중요도 가중·강한 인식
- 요약 → 헤르메스 스킬 신규 결정화 / 기존 스킬 개선·진화 / 불필요한 스킬 삭제
- 노트 사이 `[[링크]]`·군집 형성(옵시디언 그래프 = 뇌)
- **기억 망각·압축(아래 별도 정리)**

### B가 다룰 기억 망각·압축 (요구사항 — B 설계로 이월)

오래된 요약을 그대로 무한정 들고 있으면 회상의 신호 대 잡음비가 떨어진다. 시간이 지난 기억은 **단계적으로 압축**하고, 낡아 무효가 된 지식은 **흔적만 남기고 강등**해야 한다. 이는 "자면서 정리하는" 드리밍의 본질이므로 B가 담당한다. **A는 변경하지 않는다** — A의 `session_summary.updated_at`(시각)이 이미 경과 시간 계산의 토대를 제공하므로, B는 A 위에서 그대로 구현 가능하다.

서로 다른 두 메커니즘으로 분리한다:

| | 메커니즘 | 트리거 | 예 |
|---|---|---|---|
| ① 시간 기반 압축 | 오래될수록 더 강하게 요약 | 경과 시간 | 한 달 전 대화 → 결정·교훈만, 과정 제거 |
| ② 무효화(supersession) | 새 지식이 옛 지식을 대체 | 내용 변화(버전업 등) | NodeJS 1~9 → "있었다" 흔적만, 운영 디테일 제거 |

②는 시간과 무관하다 — 어제 정보라도 오늘 버전이 바뀌면 즉시 낡는다.

망각 모델: **하드 삭제가 아니라 단계적 강등(tombstone)을 기본으로 한다.**

```
Tier 0  Hot  (당일~수일)   : 5슬롯 원본 유지
Tier 1  Warm (오래됨)      : 주제별 병합·압축. 소진된 next/open 제거, decisions·facts 중심
Tier 2  Cold (많이 오래됨) : 강압축 — 결정·교훈만, 과정 제거
Tombstone (무효화됨)       : "X가 있었다/한때 이랬다" 포인터만. 검색엔 잡히되 컨텍스트 자동주입에선 제외
```

- "있었다는 사실"은 tombstone으로 보존하고 운영 디테일만 떨어뜨린다(완전 삭제는 사용자가 명시할 때만).
- 경계 시점(며칠=Warm, 몇 주=Cold)은 **임의 고정값을 박지 않고** B 설계 때 실제 누적 데이터를 측정해 정한다(매직넘버 금지).

## 미해결 / 추후 결정

- 슬롯별 최대 항목 수 상한(무한 증가 방지) — 구현 시 측정 후 결정.
- 전역(`~/.hermes/global.db`) 회상 여부 — 우선 프로젝트 스코프만, 필요 시 B에서 확장.
