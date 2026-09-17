# 에이전트 정체성 — id · 이름 · 상태 · 조직 값과 행위자 형식

> 작성일: 2026-09-15
> 목적: 기록·스킬 제안·메시지에 "어디 소속의 누구"를 정확히 찍기 위한 정체성 구조를 정한다.

## 개요

지금은 에이전트가 하나뿐이고 스킬로 역할을 흉내 낸다. 그래서 기록에 "누가 했는가"가 없다.
에이전트마다 **평생 바뀌지 않는 id**와 **부르는 이름**을 주고, 모든 기록에는 기계가 `종류:id` 형식의
행위자를 찍는다. 직무·소속·직급 같은 조직 정보는 공장이 정하지 않고 **소우주 조직 정의의 값**으로 가진다.

## 1. 에이전트를 분리해서 실제로 얻는 것

모델은 같다. 분리로 얻는 것은 세 가지다.

| 얻는 것 | 설명 |
|---|---|
| 컨텍스트 격리 | 남의 대화가 섞이지 않는다 |
| 권한 격리 | 쓸 수 있는 도구가 달라진다 |
| 기록의 주인 | 누가 한 일인지 남는다 |

"이전 일을 기억한다"는 결국 **자기 이름이 붙은 기록을 시작할 때 읽는가**로 정해진다. 그래서 정체성, 작업
이력([work-journal.md](work-journal.md)), 기억([memory-events.md](memory-events.md))이 설계의 중심이다.

## 2. 정체성 칸

| 칸 | 예 | 누가 정하나 | 성질 |
|---|---|---|---|
| **id** | `<불변 id>` | 공장 | 평생 바뀌지 않고 **재사용하지 않는다** |
| **이름 (a.k.a.)** | `하늘` | 사람(수동 입사) / 기계 임시 이름(자동) | 소우주 안에서 겹치지 않는다. 은퇴한 이름도 같은 소우주에서 재사용하지 않는다 |
| **상태** `status` | `probation` / `active` / `retired` | 공장 형식, 전환은 사람 | 수습 기간 → 정식 → 은퇴 |
| **조직 값** | `{discipline: 프론트엔드, rank: 담당, unit: users}` 또는 `{discipline: 회계, rank: 대리, unit: 회계부}` | **소우주 조직 정의** | 옮기거나 바꿀 수 있다 |
| **직무 템플릿** (선택) | `code-reviewer@factory` | 우주 공통 템플릿 | 상속한 역할 정의 |

- a.k.a.는 "also known as"(~라고도 불리는)의 약자다.
- 사람이 읽는 주소는 이름과 조직 값으로 만든다. 예: `하늘(프론트엔드·users)@zeroday-frontend`
- **id와 이름을 나누는 이유:** 이름을 바꾸거나 조직 값을 옮겨도 id가 같아 이력이 끊기지 않는다. 은퇴한 에이전트 이름을 새 에이전트가 쓰더라도 id가 달라 이력이 섞이지 않는다.
- 조직 축과 값, 담당 매칭은 [creation-and-organization.md](creation-and-organization.md).

> 변경 이력:
> - 논의 초기에는 머리말 `name`에 직무(`code-reviewer`)를 넣었다. 직무는 이름이 아니므로 바로잡았다.
> - 이어서 "id · 이름 · 직무 · 소속" 네 칸으로 정했다.
> - 에이전트 생성 논의에서 "조직 구조는 소우주가 정한다"로 바뀌면서, 직무·소속을 고정 칸에서 **조직 값**으로 옮기고 **상태** 칸을 더했다.

## 3. 행위자 형식 (확정, A-03)
모든 기록의 주체는 `종류:id`로 적는다.

| 종류 | 예 | 누구 |
|---|---|---|
| `human:` | `human:jjackkun` | 사람 |
| `agent:` | `agent:<불변 id>` | 에이전트. 화면에는 이름 주소로 보여 준다 |
| `system:` | `system:hermes-crystallize`, `system:installer` | 훅·결정화·드리밍·설치기처럼 사람도 에이전트도 아닌 자동 장치 |

- **`system:`이 필요한 이유:** zeroday-frontend의 결정화 스킬 1088개는 결정화 스크립트가 자동으로 만들었다. 종류가 둘뿐이면 이런 기록을 사람이나 에이전트 이름으로 잘못 적게 되고, 그래프에 거짓 기록이 생긴다.
- 접두어가 종류를 알려 주므로 id 안에 `ag_` 같은 접두어는 두지 않는다.
- **사람 id만 소우주를 넘나든다.** 사람은 실제로 여러 프로젝트에 걸쳐 일하므로 격리 원칙과 부딪히지 않는다.
- 사람 id는 기계가 `git config user.name`(현재 `jjackkun`)에서 읽어 찍고, 명부와 대조한다. 저장소마다 git 사용자 설정이 다를 수 있기 때문이다.

## 4. 수행자와 지시자 (확정, A-04 · A-05)
```json
{"actor": "agent:<main 의 id>", "requested_by": "human:jjackkun"}
```

- 사람이 시키고 AI가 수행하는 일을 한 칸으로는 온전히 기록할 수 없다. 그래서 `actor`(수행자)와 `requested_by`(지시자)를 나눈다.
- **에이전트를 지정하지 않고 연 세션**은 소우주 **기본 에이전트 `main`**이 수행한 것으로 기록한다.
- 에이전트가 다른 에이전트에게 일을 맡길 때도 `requested_by`를 쓴다. 이 칸으로 "누가 누구에게 시켰는가"가 그래프로 이어진다.

### 세션별 지시자 (확정, RV-05)

| 세션 | `requested_by` | 값이 오는 곳 |
|---|---|---|
| 대화형 세션 | 세션을 연 사람 `human:<git user.name>` | 훅이 `git config user.name` 을 읽음 |
| 헤드리스 루프(`hermes-loop-run.sh`) | 루프를 시작한 사람 `human:<id>` | 루프 기록 `loops.started_by` 칸 |
| cron 자동 실행(`hermes-cron-run.sh`) | `system:hermes-cron` — 사람이 아니라 스케줄이 시켰다 | 러너가 고정값 주입 |
| 하위 에이전트(`SubagentStop`) | 부른 세션의 `requested_by` 그대로 | 훅 입력 `agent_type` 은 직무 템플릿 이름이라 `evidence.template` 에만 적는다(V-4 확인) |

지시자 칸이 비면 "누가 시켰는가" 그래프가 끊긴다. C-05("사람 없는 세션은 `main` 수행")는 수행자만 정했고 지시자는 비어 있었다(근거: 리뷰 R-6).

### 배선 (확정, RV-05 · RV-06)
| 장치 | 내용 |
|---|---|
| 환경변수 `HERMES_REQUESTED_BY` | 러너(`hermes-loop-run.sh` · `hermes-cron-run.sh` · `hermes-summon.py`)가 대상 세션에 넣는다. 값은 `human:<id>` 또는 `system:hermes-cron` |
| `loops.started_by` 칸 | 루프 생성 시 `human:<git user.name>` 또는 `system:hermes-cron` 을 적는다. 러너는 이 값을 `HERMES_REQUESTED_BY` 로 넘긴다 |
| 결정 순서 | 이벤트 기록기는 **환경변수 → 훅 입력 `agent_type` → 기본 `main`** 순으로 행위자·지시자를 정한다. 에이전트 본문에서 읽지 않는다 |

- 수행자 `actor` 의 `agent:<id>` 는 러너가 넣은 `HERMES_AGENT_ID` 와 7절의 소환 토큰 검증 결과로 정해진다. 환경변수가 없으면 `main`.

## 5. 선언하는 곳

### SOUL.md 머리말 (합의, A-09)
```yaml
---
agent_id: <불변 id>
name: <이름>
status: probation
org:
  discipline: <직군>
  rank: <수직>
  unit: <수평>
template: <직무 템플릿>@factory
universe_id: <.hermes/universe.id 값>
created_at: <생성일>
approved_by: human:<사람 id>
---
```

본문에는 역할, 책임 경계("이건 내 일이 아니다"까지), 원칙, 금지 사항, 쓸 수 있는 도구 목록을 쓴다.

### SOUL.md와 기억을 나누는 이유

| 대상 | 내용 | 누가 고치나 | 저장 |
|---|---|---|---|
| SOUL.md | 정체성 | 사람 승인으로만 | 파일 |
| 기억 | 스스로 배운 사실 | 에이전트 | 추가 전용 기억 이벤트, `MEMORY.md`는 보기 ([memory-events.md](memory-events.md)) |

둘을 섞으면 배운 내용이 쌓이면서 정체성 문서가 조금씩 변질된다.

- **한계:** "사람 승인으로만" 을 기계로 막는 장치는 아직 없다. 공장 자산 변조 경고 훅은 설치 목록 기준이라 소우주 파일인 SOUL.md 는 대상 밖이다. 세션 안 SOUL.md 편집 차단은 백로그 후보 `soul-edit-guard` 로 남긴다.

### 명부

소우주에 명부 `.hermes/agents.json`을 둔다. 이름 오타와 사칭은 여기서 막힌다.

| 칸 | 형식 | 규칙 |
|---|---|---|
| `agent_id` | UUIDv7 | 불변, 재사용 없음 |
| `name` | 문자열 | 소우주 안에서 유일. **은퇴한 이름도 재사용 금지**(복직 자리를 지키기 위해, [creation-and-organization.md](creation-and-organization.md) 4절) |
| `status` | `probation` / `active` / `retired` | 전환은 사람(`hermes-agent.py promote` · `retire` · `rehire`) |
| `org` | `{discipline, rank, unit}` | 값은 `.hermes/organization.yaml` 에 있는 것만 |
| `template` | `<직무 템플릿>@factory` (선택) | `assets/agents/*.md` 이름 |
| `created_at` | ISO-8601 UTC | 기계 |
| `created_by` · `approved_by` | 행위자 형식(`human:` · `system:`) | 입사는 `human:`, 설치 시 `main` 만 `system:installer` |

- 설치 시 `main` 한 명이 자동 등록된다: `status: active`, `created_by: system:installer`, `org` 는 `empty.yaml` 조직(수직 `human → main`) 기준.
- 검증기는 중복 이름 · 은퇴 이름 재사용 · 모르는 상태값을 거부한다.
- **명부에 없는 id 나 소환 토큰 짝이 맞지 않는 세션은 멈추지 않는다.** 대신 그 세션의 이력은 `actor` 를 `system:unverified-session` 으로 찍어 **출처 불명으로 표시**한다(7절). 훅 오류 하나로 헤드리스 루프 전체가 멈추면 안 되기 때문이다.
- 은퇴(`retired`) 에이전트는 명부에 남지만 소환 대상 · 담당 매칭 · 스킬 주입에서 빠진다. 복직하면 돌아온다.

## 6. 폴더 (합의, A-08)
```text
<소우주>/.hermes/agents/<agent_id>/
  SOUL.md
  MEMORY.md        # 기억 이벤트에서 만든 보기
  skills/          # 개인 스킬
```

> 폐기: `teams/<팀>/agents/<이름>/`. 이름과 소속은 바뀔 수 있으므로 폴더 키가 될 수 없다.

### git 추적 (확정, A-10)
정체성 자산은 다른 컴퓨터로 가야 하므로 git 을 탄다. 현행 `.gitignore` 마커는 `.hermes/*` 로 **내용물을** 무시하므로, 예외는 **디렉터리 단계마다** 풀어야 한다(`!.hermes/skills/` + `!.hermes/skills/**` 두 줄과 같은 이유).

```gitignore
.hermes/*
!.hermes/agents/
!.hermes/agents/*/
!.hermes/agents/*/SOUL.md
!.hermes/agents/*/skills/
!.hermes/agents/*/skills/**
!.hermes/organization.yaml
!.hermes/agents.json
.hermes/agents/*/MEMORY.md
.hermes/summons/
```

| 경로 | 추적 | 이유 |
|---|---|---|
| `agents/<id>/SOUL.md` · `agents/<id>/skills/**` · `organization.yaml` · `agents.json` | 예 | 정체성 · 조직 · 명부는 소우주의 원천 |
| `agents/<id>/MEMORY.md` | 아니오 | 기억 이벤트에서 만든 파생물. 원본은 `state.db` 와 원격 `memory/` 조각 |
| `summons/` | 아니오 | 1회용 소환 토큰 파일(7절). 컴퓨터 안에서만 뜻이 있다 |

- 예외를 푼 **뒤에** 재무시 줄(`MEMORY.md` · `summons/`)이 와야 한다. 순서가 바뀌면 파생물이 커밋된다.

## 7. 이름을 기계가 찍는 방법

에이전트에게 "저는 코드리뷰어입니다"라고 본문에 쓰게 하면 잊거나 틀린다. 정체성은 **기계가 쓰는 칸**이다.

| 경로 | 방법 | 상태 |
|---|---|---|
| 헤드리스 (`claude -p`) | 러너가 `HERMES_AGENT_ID` 와 `HERMES_SUMMON_NONCE` 를 넣고, 세션 시작 훅이 읽어 검증한 뒤 찍는다 | 확정 |
| 대화형 세션의 하위 에이전트 | `SubagentStop` 입력의 `agent_type` 은 직무 템플릿 이름이지 명부 id 가 아니다(V-4 확인). `evidence.template` 에 적고, 수행자는 소환 토큰 없이는 `main` 으로 남는다 | 확정 |

### 사칭 방지 — id 는 러너가 찍고 에이전트는 고르지 못한다

> ✅ 리뷰 확정 (2026-09-15, RV-06) — 근거: 리뷰 R-5, cumora K-6

명부는 "없는 id" 를 막지만 **등록된 남의 id** 는 못 막는다. 세션 안 에이전트가 `HERMES_AGENT_ID=<남의 id> claude -p …` 를 Bash 로 띄우면 명부 검사는 통과한다. cumora 는 신원을 요청 본문이 아닌 서명 토큰에서만 읽고, 모델 프로세스에는 토큰 자체를 주지 않는다(`SECURITY.md`, `docs/BYOA.md`).

| 규칙 | 내용 |
|---|---|
| 소환은 러너만 | 다른 에이전트를 부르는 유일한 경로는 러너 `scripts/hermes-summon.py` 다. 러너가 명부에서 대상 id 를 찾아 환경변수를 넣고 `task.assigned` 를 남긴다. 에이전트가 `claude -p` 를 직접 띄우는 것은 PreToolUse 훅이 막는다. **허용 목록:** 공장이 설치한 러너(`hermes-loop-run.sh` · `hermes-cron-run.sh` · `hermes-summon.py`) 경유는 통과 — zeroday-frontend 가 쓰는 헤드리스 루프가 이 경로다 |
| 지시자는 현재 세션 | 러너는 `requested_by` 를 **호출한 세션의 actor** 로 찍는다. 호출하는 쪽이 자기를 다른 누구로 적을 수 없다 |
| 검증 가능 | 이력의 `actor` 는 러너가 남긴 소환 이벤트(`task.assigned`)와 짝이 맞아야 한다. 짝 없는 `actor` 는 보기에서 "출처 불명" 으로 표시한다 |

- 이것은 Claude Code 훅 위에 선 방어라 Codex 세션에서는 약하다([encryption-keys.md](../protection/encryption-keys.md) 4절과 같은 한계).

**"러너 경유" 를 훅이 아는 방법** (2026-09-15 리뷰 후속). 명령줄 문자열로 판정하면 `bash -c 'exec hermes-loop-run.sh …'` 처럼 흉내 낼 수 있다. 그래서 명령줄이 아니라 **러너만 만들 수 있는 1회용 소환 토큰**으로 판정한다.

| 단계 | 내용 |
|---|---|
| 발급 | 러너가 소환 직전에 `state.db` `summons` 테이블에 `(nonce, agent_id, requested_by, expires_at, used)` 를 INSERT 하고, 같은 nonce 로 파일 `.hermes/summons/<nonce>.pending` 을 만든 뒤, 대상 세션에 `HERMES_AGENT_ID` 와 `HERMES_SUMMON_NONCE` 를 넣는다. `state.db` 는 러너(사람 권한)가 쓰고, 세션 안 Bash 는 훅이 `summons` 테이블 쓰기를 막는다. 러너가 nonce 파일을 못 만들면 소환을 중단하고 사람에게 알린다 |
| 허용 판정 | PreToolUse 훅은 **명령줄이 아니라 nonce 파일 존재**로 "러너 경유" 를 판정한다. `bash -c 'exec hermes-loop-run.sh …'` 흉내는 nonce 파일이 없어 차단된다 |
| 검증 | 대상 세션의 시작 훅이 `(nonce, agent_id)` 짝이 `summons` 에 있고 `used` 가 아니며 미만료인지 확인한 뒤 `used` 표시. 짝 없음 · 재사용 · 만료 어느 경우든 `agent:` 대신 `system:unverified-session` 으로 찍고 경고한다 — **세션은 멈추지 않고** 그 이력만 "출처 불명" 이 된다 |
| 짝 맞춤 | `summons` 행이 곧 `task.assigned` 이벤트의 근거다. 위 표 "검증 가능" 이 이 짝으로 계산된다 |

- cumora 의 K-6 과 같은 모양이다: 신원은 모델이 고르는 값이 아니라 러너가 발급한 토큰에서 온다.
- 러너 이름 · 허용 목록 · 훅 판정 규칙은 위로 확정됐다(G-29 닫힘). `expires_at` 의 기본 길이는 근거 있는 값이 없어 미정이다 — 러너가 발급 시 명시한다.
- 구버전 DB(`summons` 테이블 없음)에서는 시작 훅이 죽지 않고 한 줄 알린 뒤 exit 0 하고, 첫 실행 때 테이블을 만든다.

## 8. 소우주 밖으로 나가는 곳에서

GitHub 이슈 봉투처럼 소우주 밖으로 나가는 곳에는 `agent_id`와 `universe_id`만 넣는다. 이름·조직 값·소우주
이름은 소우주 안 명부에서만 풀린다([skill-proposal-delivery.md](../world/skill-proposal-delivery.md)).
