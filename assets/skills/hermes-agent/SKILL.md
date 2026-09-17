---
name: hermes-agent
description: 헤르메스 에이전트 명부·조직·소환·인계를 CLI 로 잇는다. 사용자가 자연어로 "누구를 입사시켜"(예 "users 담당 입사시켜", "QA 한 명 뽑아"), "이 일을 누구한테 넘겨"(예 "이 로그인 버그 프론트 담당한테 넘겨", "이거 QA 한테 인계해"), "누가 이 일 맡지"(담당 찾기), "누구 은퇴/복직시켜", "명부 보여줘", "지금 나 누구야"(정체성 확인) 중 하나를 말할 때 반드시 이 스킬을 쓴다. 담당 배정·인계·입사·조직 얘기가 나오면, "봉투"·"done_when"·"소환"이라는 단어를 쓰지 않더라도 발동한다. 파괴적 판단(은퇴·인계 실패 처리)은 사람 확인을 거친다.
---

# hermes-agent

에이전트 **명부·조직·소환·인계**를 CLI 로 잇는다. 자연어 요청을 아래 명령으로 옮기는 게 이 스킬의 일이다 —
모델이 이벤트를 손으로 만들지 않고, **검증된 CLI 를 거쳐** 이력(journal_events)에 남게 한다.

대상은 이 스킬이 설치된 **현재 프로젝트**다. 어느 프로젝트인지 묻지 않는다.
`python3 scripts/hermes-agent.py …` · `python3 scripts/hermes-summon.py …` 는 프로젝트 루트에서 실행한다.

## 트리거 → 명령 대응

| 사용자가 이렇게 말하면 | 이 명령을 쓴다 | 절 |
|---|---|---|
| "users 담당 입사시켜" · "QA 한 명 뽑아" | `hermes-agent.py hire` | [1](#1-입사-hire) |
| "누가 이 일 맡지" · "프론트 담당 찾아줘" | `hermes-agent.py match` | [2](#2-담당-찾기-match) |
| "이 일 QA 한테 넘겨" (즉시 실행) | `hermes-summon.py run` | [3](#3-즉시-위임-소환-run) |
| "이 일 QA 한테 인계해" (성공 기준·기한 명시) | `hermes_handoff.open_handoff` | [4](#4-구조화-인계-봉투) |
| "프론트 담당 은퇴시켜" · "복직시켜" · "승급" | `hermes-agent.py promote/retire/rehire` | [5](#5-생애주기-promote-retire-rehire) |
| "명부 보여줘" · "지금 나 누구야" | `hermes-agent.py list` · `whoami` | [6](#6-조회-list-whoami) |

**언제 소환(run)이고 언제 인계(handoff)인가** — 이 구분이 핵심이다:

- **소환(run)**: 지금 그 자리에서 다른 에이전트를 띄워(claude -p) 일을 시킨다. 빠르지만 성공 기준이 느슨하다.
- **인계(handoff)**: 봉투에 `goal`(무엇을)과 `done_when`(무엇이 되면 끝)을 **반드시** 적어 넘긴다. 받는 쪽은 봉투를
  검사하고 시작한다. "확실히 됐는지 기계가 잴 수 있어야 한다"는 요청, 기한이 있는 요청이면 인계다.
  사용자가 "이게 되면 끝"이라는 기준을 말하거나 넌지시라도 기대하면 인계를 택한다.

---

## 1. 입사 (hire)

```bash
python3 scripts/hermes-agent.py hire "<이름>" --org "<분야>,<직급>,<조직>" [--template <템플릿>]
```

- 이름은 명부에서 **유일**해야 한다(은퇴자 이름 포함). 겹치면 CLI 가 거부한다 — 사용자에게 다른 이름을 받는다.
- `--org` 는 **쉼표**로 나눈 `분야,직급,조직` 이다(빈 칸은 비워 둔다: `QA,,users`). 슬래시로 주면 세 값이 한 덩어리로 읽혀 거부된다(2026-09-17 실측). 값은 `organization.yaml` 에 **정의된 축 값**만 받는다. 값이 확실치 않으면 먼저 `list` 로 기존 조직을 보이고,
  없는 값이면 사용자에게 조직 정의부터 물어본다(추측해 넣지 않는다).
- 최상위 직급 `human` 은 기계가 고정한다 — 사람이 아닌 에이전트를 `human` 으로 입사시키지 않는다.

**예 1** — "users 담당 백엔드로 한 명 입사시켜"
→ `python3 scripts/hermes-agent.py hire "유저스담당" --org "backend,staff,users"`
→ 출력의 `정체성: .hermes/agents/<id>/` 경로를 사용자에게 알리고, **SOUL.md 는 사람이 채운다**고 안내한다(에이전트가 쓰지 않는다).

## 2. 담당 찾기 (match)

```bash
python3 scripts/hermes-agent.py match [--discipline <분야>] [--rank <직급>] [--unit <조직>]
```

- 축 값으로 후보를 좁힌다. 맞는 담당이 없으면 `ask:` 를 출력한다 — 그때는 **사람에게 문의**하지, 아무나 고르지 않는다.
- 사람이 "이 영역은 담당을 두지 않는다" 고 답하면 `python3 scripts/hermes-agent.py no-owner --discipline <분야> [--unit <조직>]` 로 기억해 둔다. 이후 같은 영역의 `match` 는 `ask:` 대신 `no-owner: …(날짜)` 를 내고 다시 묻지 않는다.
- 사람 없는 세션(루프·크론, `HERMES_HEADLESS=1`)은 담당이 없어도 멈추지 않고 `main` 이 수행한 뒤 "담당 없음" 제안을 남긴다. 다음 대화형 세션 시작 훅이 `[owner-proposals] … N건` 으로 알리면 사용자에게 **입사시킬지, 담당을 두지 않을지** 묻고 그 답을 `hire` 또는 `no-owner` 로 기록한다.
- 은퇴한 에이전트는 결과에서 빠진다.

**예** — "이 결제 버그 누가 맡지"
→ `python3 scripts/hermes-agent.py match --discipline payments`
→ 후보가 여럿이면 목록을 보이고 사용자에게 고르게 한다. `ask:` 면 "맞는 담당이 없습니다 — 입사가 필요합니다"로 안내.

## 3. 즉시 위임 (소환 run)

```bash
python3 scripts/hermes-summon.py run "<이름|id>" --task "<한 줄 지시>" [--discipline <분야>] [--unit <조직>] [--timeout <초>]
```

- 이름/ID 를 주거나, 축 값(`--discipline`·`--unit`)으로 매칭시킨다. 은퇴자는 소환할 수 없다.
- 소환은 `task.assigned` → `claude -p` 실행 → `task.finished` 를 이력에 남긴다. nonce 로 사칭을 막는다(러너만 발급).
- **주의**: 세션 안에서 `claude -p` 를 직접 부르면 소환 가드가 막는다. 반드시 이 러너를 거친다.

**예** — "이 로그인 깨진 거 프론트 담당한테 지금 넘겨"
→ `python3 scripts/hermes-summon.py run --discipline frontend --task "로그인 리다이렉트 깨짐 수정"`

## 4. 구조화 인계 (봉투)

성공 기준·기한을 명시해 넘길 때. 봉투는 `goal` 과 `done_when` 이 **없으면 기계가 막는다** — 원문 붙여넣기도 막힌다.

```bash
python3 - <<'PY'
import sys; sys.path.insert(0, "scripts")
from hermes_handoff import open_handoff
hid = open_handoff(
    ".hermes/state.db", ".", "<받는 에이전트 id 또는 이름>",
    {
        "goal": "<무엇을 원하는가, 한 줄>",
        "done_when": "<완료 기준, 아래 다섯 형식 중 하나>",
        "inputs": ["<파일 경로>", "<이벤트 id>"],   # 참조만 — 원문 문장은 거부된다
        "expires_at": "2026-09-20T00:00:00Z",       # 선택 — 없으면 만료 없음
    },
    by="human:<사람 이름>",
)
print("handoff:", hid)
PY
```

**`done_when` 다섯 형식** (이것만 허용, `manual` 만 사람이 잰다):

| 형식 | 뜻 | 판정 |
|---|---|---|
| `test:<이름>` | 그 테스트의 종료 코드 | pass / fail |
| `file:<경로>` | 파일 존재 | pass / fail |
| `gate:<규칙>` | `.harness/gate-events.jsonl` 최근 판정 | pass / fail |
| `commit:<해시\|HEAD>` | 저장소에 그 커밋이 있는가 | pass / fail |
| `manual` | 사람이 잰다 | none |

**되돌아오는 네 방식** — 받는 쪽이 봉투를 이렇게 닫는다:

```bash
python3 - <<'PY'
import sys; sys.path.insert(0, "scripts")
from hermes_handoff import resolve
# how 는 다섯 중 하나: finished(완료) · declined(거절) · question(되묻기) · expired(만료) · blocked(규칙 위반으로 막힘)
resolve(".hermes/state.db", ".", "<handoff_id>", "finished", "<행위자>")
# finished 는 done_when 을 기계가 다시 재서 verified 를 채운다.
# declined·question 은 reason= 에 사유를 적는다(필수).
# blocked 는 reason="rule:<이름>" 꼴만 받는다 — 예: resolve(db, ".", hid, "blocked", "agent:…", reason="rule:R-secret")
PY
```

- **봉투의 `kind` 는 기계가 정한다** — 보내는 쪽·받는 쪽의 조직 관계로 지시(위→아래, 사람→에이전트) · 협업(같은 unit) · 요청(다른 unit). **지시는 거절할 수 없다** — 규칙(R 룰·결정 원장의 멈추는 네 경우)에 걸리면 거절이 아니라 `blocked` 로 되돌린다. 협업·요청은 사유를 적어 거절할 수 있다. 명부에 없는 상대끼리면 `요청(미상)` 으로 두어 거절 가능하게 한다.
- **만료**는 시간 데몬이 아니라 **세션 시작 훅**이 처리한다: 기한이 지났는데 시작(`task.started`)도 되묻기(`handoff.question`)도
  없는 봉투에 자동으로 `handoff.expired` 를 붙인다. 사용자가 손댈 일은 없다 — 다음 세션 시작 때 알림만 뜬다.

**예** — "이 결제 리팩터 QA 한테 인계해. 회귀 테스트 통과하면 끝이고, 금요일까지."
→ `goal="결제 리팩터 QA"`, `done_when="test:payments-regression.sh"`, `expires_at="2026-09-19T…Z"`, `to_agent="QA담당"`.

## 5. 생애주기 (promote / retire / rehire)

```bash
python3 scripts/hermes-agent.py promote "<이름>"   # 승급
python3 scripts/hermes-agent.py retire  "<이름>"   # 은퇴 — 매칭·소환·스킬 주입에서 빠진다(파일은 남는다)
python3 scripts/hermes-agent.py rehire  "<이름>"   # 복직
```

- **은퇴·인계 실패 처리는 파괴적 판단**이다 — 사용자에게 대상과 영향(그 담당이 매칭·소환에서 빠짐)을 확인한 뒤 실행한다.
- 은퇴해도 개인 스킬·SOUL 은 파일로 남는다. `rehire` 로 되돌린다.

## 6. 조회 (list / whoami)

```bash
python3 scripts/hermes-agent.py list      # 명부 전체(상태·이름·id·조직·템플릿)
python3 scripts/hermes-agent.py whoami    # 지금 세션의 에이전트(HERMES_AGENT_ID 기준)
```

읽기 전용 — 확인 없이 바로 실행해도 된다.

---

## 원칙

- **CLI 를 거친다.** 이벤트(입사·소환·인계)를 손으로 SQL 로 넣지 않는다 — CLI 가 검증·nonce·이력을 책임진다.
- **추측해 넣지 않는다.** 조직 축 값·담당·이름이 불확실하면 사용자에게 묻는다(실측·정의 우선).
- **파괴적 판단은 확인.** 은퇴·인계 거절/만료 강제 같은 되돌리기 어려운 일은 사람 확인을 거친다.
- **SOUL.md 는 사람 몫.** 입사가 만든 정체성 파일의 SOUL 은 에이전트가 채우지 않는다.
