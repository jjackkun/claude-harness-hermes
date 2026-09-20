---
name: hermes-agent
description: 헤르메스 에이전트 명부·조직·소환·인계를 CLI 로 잇는다. `/hermes-agent` 라고만 치거나 "에이전트 만들자"·"한 명 입사시켜"·"직원 뽑자" 처럼 분야·직급·조직 없이 입사를 말하면 터미널 폼(선택지)을 먼저 띄워 조직 정의 → 입사까지 하고 SOUL 은 기계 초안으로 채운다(사람은 승인만). 사용자가 자연어로 "누구를 입사시켜"(예 "users 담당 입사시켜", "QA 한 명 뽑아"), "이 일을 누구한테 넘겨"(예 "이 로그인 버그 프론트 담당한테 넘겨", "이거 QA 한테 인계해"), "누가 이 일 맡지"(담당 찾기), "누구 은퇴/복직시켜", "명부 보여줘", "지금 나 누구야"(정체성 확인), "누구한테 이거 가르쳐"·"이건 기억해 둬"(가르침·기억) 중 하나를 말할 때 반드시 이 스킬을 쓴다. 담당 배정·인계·입사·조직 얘기가 나오면, "봉투"·"done_when"·"소환"이라는 단어를 쓰지 않더라도 발동한다. 파괴적 판단(은퇴·인계 실패 처리)은 사람 확인을 거친다.
---

# hermes-agent

에이전트 **명부·조직·소환·인계**를 CLI 로 잇는다. 자연어 요청을 아래 명령으로 옮기는 게 이 스킬의 일이다 —
모델이 이벤트를 손으로 만들지 않고, **검증된 CLI 를 거쳐** 이력(journal_events)에 남게 한다.

대상은 이 스킬이 설치된 **현재 프로젝트**다. 어느 프로젝트인지 묻지 않는다.
`python3 scripts/hermes-agent.py …` · `python3 scripts/hermes-summon.py …` 는 프로젝트 루트에서 실행한다.

## 트리거 → 명령 대응

| 사용자가 이렇게 말하면 | 이 명령을 쓴다 | 절 |
|---|---|---|
| `/hermes-agent` · "에이전트 만들자" · "한 명 입사시켜"(축 값 없이) | 폼 먼저 → `hire` | [0](#0-폼-우선--입사는-명령을-외우지-않고-고른다) |
| "users 담당 입사시켜" · "QA 한 명 뽑아" | `hermes-agent.py hire` | [1](#1-입사-hire) |
| "누가 이 일 맡지" · "프론트 담당 찾아줘" | `hermes-agent.py match` | [2](#2-담당-찾기-match) |
| "이 일 QA 한테 넘겨" (즉시 실행) | `hermes-summon.py run` | [3](#3-즉시-위임-소환-run) |
| "이 일 QA 한테 인계해" (성공 기준·기한 명시) | `hermes_handoff.open_handoff` | [4](#4-구조화-인계-봉투) |
| "프론트 담당 은퇴시켜" · "복직시켜" · "승급" | `hermes-agent.py promote/retire/rehire` | [5](#5-생애주기-promote-retire-rehire) |
| "명부 보여줘" · "지금 나 누구야" | `hermes-agent.py list` · `whoami` | [6](#6-조회-list-whoami) |
| "게이트QA 한테 이거 가르쳐" · "이건 기억해 둬" · "이 기억 핀해" | `hermes-agent.py teach` · `note` · `pin` | [7](#7-가르침과-기억-teach--note--pin) |

**언제 소환(run)이고 언제 인계(handoff)인가** — 이 구분이 핵심이다:

- **소환(run)**: 지금 그 자리에서 다른 에이전트를 띄워(claude -p) 일을 시킨다. 빠르지만 성공 기준이 느슨하다.
- **인계(handoff)**: 봉투에 `goal`(무엇을)과 `done_when`(무엇이 되면 끝)을 **반드시** 적어 넘긴다. 받는 쪽은 봉투를
  검사하고 시작한다. "확실히 됐는지 기계가 잴 수 있어야 한다"는 요청, 기한이 있는 요청이면 인계다.
  사용자가 "이게 되면 끝"이라는 기준을 말하거나 넌지시라도 기대하면 인계를 택한다.

---

## 0. 폼 우선 — 입사는 명령을 외우지 않고 고른다

`/hermes-agent` 라고만 치거나 "에이전트 만들자"·"한 명 입사시켜"·"직원 뽑자" 처럼 **축 값(분야·직급·조직) 없이** 입사를
말하면, 명령을 조립하기 전에 **폼을 먼저** 띄운다. `/hermes-loop` 가 옵션 폼을 먼저 보여주는 것과 같은 방식이다.
사람이 **정의된 축 값 중에서 고르므로** 자연어를 축 값으로 판별할 필요가 없고(C-19), 오판으로 잘못된 인자가 들어갈 위험이 사라진다.
축 값을 이미 문장에 정확히 담아 준 경우("`qa,staff,harness` 로 게이트QA 입사")는 폼을 건너뛰고 [1](#1-입사-hire) 로 간다.

폼은 터미널 선택지(`AskUserQuestion`)로만 띄운다. 웹 폼은 답을 다시 CLI 로 옮기는 단계가 는다.

### 0-1. 조직부터 — 축 값이 하나도 없으면

먼저 `.hermes/organization.yaml` 을 읽는다. `discipline`·`rank`·`unit` 이 **전부 비어 있으면** 입사 자체가 거부되므로
입사 폼 대신 **조직 정의 폼**을 먼저 띄운다. 선택지는 `assets/templates/organization/` 의 템플릿 두 가지와 직접 입력이다:

```text
🏢 조직 정의   (이 소우주에 아직 조직이 없습니다)

① 분야(discipline) ▸ 사무형: 총무·회계·영업 / 제품형: 기획·디자인·퍼블리싱·프론트엔드·백엔드·QA·QC / 직접 입력(쉼표로)
② 직급(rank)       ▸ 사무형: 과장·대리·주임·수습사원 / 제품형: 리드·담당 / 직접 입력(위에서 아래 순, 쉼표로)
③ 조직(unit)       ▸ 사무형: 총무부·회계부·영업부 / 제품형: 공통 / 직접 입력(쉼표로)
```

- 세 질문을 한 번의 `AskUserQuestion` 에 담는다. 각 질문의 선택지는 "사무형 템플릿"·"제품형 템플릿" 이고, 직접 입력은 "Other" 로 받는다.
  사무형·제품형의 실제 값은 템플릿 파일(`office.yaml`·`product.yaml`)에서 **읽어서** 보인다 — 외워 적지 않는다.
- **어떤 조직이든 가능하다.** 템플릿은 출발점일 뿐이고, "둘 다" 라고 하면 두 목록을 합치며, 직접 입력한 값은 그대로 쓴다.
  개미 군단(일개미·병정개미·수개미·여왕개미)처럼 템플릿과 무관한 축 값도 사용자가 적으면 그대로 기록한다 — 값을 고치거나 골라내지 않는다.
- 답을 `.hermes/organization.yaml` 에 템플릿과 같은 모양으로 쓴다. 규칙은 넣지 않고 값만 담는다:

  ```yaml
  discipline: [QA, 프론트엔드]
  rank: [리드, 담당]   # 위에서 아래 순. 맨 위 human 은 기계가 붙인다
  unit:
    harness: {}
  ```

  `unit_id` 는 적지 않는다 — 다음 `hire` 가 `ensure_unit_ids` 로 부여한다. `rank` 에 `human` 을 넣지 않는다(기계가 붙인다).
- 쓴 뒤 파일을 한 번 보여주고 0-2 로 이어진다. 축 하나라도 이미 값이 있으면 이 폼은 건너뛴다 — 값 추가는 0-2 의 "새 값 추가" 로 받는다.

### 0-2. 입사 폼 — 분야 → 직급 → 조직 → 이름

`organization.yaml` 에서 읽은 값만 선택지로 보인다. 축이 비어 있으면 그 질문은 빼고 빈 칸으로 둔다.

```text
🪪 에이전트 입사   (대상: 현재 프로젝트)

① 분야   ▸ organization.yaml 의 discipline 값 중 하나        [선택 — 없음 가능]
② 직급   ▸ organization.yaml 의 rank 값 중 하나 (human 제외)  [선택 — 없음 가능]
③ 조직   ▸ organization.yaml 의 unit 이름 중 하나              [선택 — 없음 가능]
④ 이름   ▸ 명부에서 유일한 이름                                [필수 — 기타 입력]
```

- ①~③은 한 번의 `AskUserQuestion` 에 담는다(축이 셋 다 있으면 세 질문). 각 질문에 "없음" 선택지를 두고, 정의에 없는 값은 "Other" 로 받는다.
  선택지는 질문당 4개까지다 — 축 값이 더 많으면 질문 본문에 전부 나열하고 선택지엔 4개만 둔다.
- 사용자가 축 값이나 이름을 산문으로 이미 줬으면 그 축은 묻지 않는다. "둘 다"·"무엇이든" 같은 답은 그 축을 닫는 답이다 — 다시 묻지 않는다.
- **새 값 추가**: 사용자가 Other 로 정의에 없는 값을 적으면(예: 직급 "여왕개미") 그 값을 먼저 `organization.yaml` 의 해당 축에 **덧붙인 뒤** 입사로 간다.
  조직은 언제든 자랄 수 있어야 하고, CLI 는 정의된 값만 받으므로 순서는 항상 "정의 → 입사" 다. 기존 값은 지우지 않는다.
- ④ 이름은 별도 질문으로 받는다. 선택지로 `<분야>담당`·`<조직><분야>` 두 후보를 제안하되 사용자가 "기타" 로 직접 적는 것을 기본으로 여긴다.
  `hermes-agent.py list` 로 명부를 먼저 읽어 **이미 있는 이름(은퇴자 포함)은 후보에서 뺀다**.

### 0-3. 명령 한 줄 보여주고 실행

폼 답으로 명령을 조립해 **실행 전에 한 줄로 보여준다** — 사람이 되돌릴 수 있게:

```bash
python3 scripts/hermes-agent.py hire "<이름>" --org "<분야>,<직급>,<조직>"
```

빈 축은 비워 둔다(`--org "QA,,harness"`). 값을 바꾸거나 지어내지 않는다 — 폼 답 그대로다.

- 이름이 겹치면 CLI 가 `이름 '…' 은 이미 명부에 있다` 로 거부한다. 그러면 **④ 이름 질문만 다시** 띄운다. 추측으로 개명하지 않는다.
- 축 값이 거부되면(`… 은 organization.yaml 에 없다`) 폼과 파일이 어긋난 것이다 — 파일을 다시 읽고 폼을 다시 띄운다.

### 0-4. SOUL 초안 — 기계가 채우고 사람이 승인한다

입사가 성공하면 `정체성: .hermes/agents/<id>/` 가 출력되고, `SOUL.md` 에는 **기계 초안**이 이미 들어 있다(조직 값·코드 경로·직무 템플릿으로 채움, 모델 호출 0).
사람에게 역할·금지·말투를 묻지 않는다 — cumora 는 에이전트가 스스로 쓰고, ECC 는 미리 쓴 역할 템플릿을 쓴다(2026-09-20 대조). 우리는 초안 + 사람 승인이다(D-01).

- 초안 파일 경로와 **역할 문단 한 줄**만 보여준다. "읽고 고친 뒤 초안 표시 줄을 지우면 승인" 이라고 안내한다.
- 사용자가 그 자리에서 고칠 말을 주면 **그 문장 그대로** 해당 절에 옮겨 적고 초안 표시 줄을 지운다. 문장을 지어내거나 다듬지 않는다.
- 옛 에이전트의 SOUL 이 틀 그대로면 `python3 scripts/hermes-agent.py soul-draft "<이름>"` 로 초안을 채운다. 사람이 승인한 SOUL(표시 줄 없음)은 절대 덮지 않는다.

**예** — "/hermes-agent" (빈 조직인 이 저장소에서)
→ 조직 정의 폼(사무형/제품형/직접) → `organization.yaml` 기록 → 입사 폼(분야·직급·조직·이름) →
`python3 scripts/hermes-agent.py hire "게이트QA" --org "QA,담당,harness"` 를 보여주고 실행 → SOUL 초안 경로·역할 한 줄 안내.

## 1. 입사 (hire)

분야를 알면 `python3 scripts/hermes-agent.py templates --discipline <분야>` 로 맞는 역할 템플릿 후보(ECC 68 + cumora 4, `origin` 표시)를 보이고 고르게 한다 — 고른 이름을 `--template` 에 넣으면 그 절이 SOUL 초안에 들어간다. 없는 이름은 거부(exit 2).

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

## 4b. 다른 소우주의 일 — 사람 경유만 (H-04)

봉투에 `universe_id`(다른 소우주의 id)를 적어 `open_handoff` 를 부르면 `task.assigned` 대신 **`handoff.external`** 이벤트만 남고
"사람을 거쳐서만 요청합니다" 안내가 나온다. 에이전트가 다른 소우주 원격에 이슈를 여는 자동 경로는 **없다** — 요청 내용 자체가
이쪽 소우주의 정보다. 사용자에게 "그 저장소에서 직접 요청을 시키고, 결과(커밋·문서)를 이쪽에 알려 주십시오" 라고 안내한다.

**예** — "이거 백엔드 저장소 API 에 필드 추가해 달라고 해" → 이쪽 소우주에서 `handoff.external` 기록 + 사람 안내(자동 배달 없음).

## 4c. 에이전트 공유 — 우주 템플릿 경유 복제 (H-09)

에이전트는 태어난 소우주 하나에만 있다. 다른 소우주에서 같은 실력이 필요하면 **복제**한다: SOUL + 개인 스킬을
일반화해 우주(공장)에 제안하고, 허가되면 우주 공통 직무 템플릿이 되어 전파되며, 그쪽 소우주에서 사람이 `hire --template` 로
**새 id·수습부터** 입사시킨다. 기억·이력·성적은 넘어가지 않는다.

```bash
python3 scripts/hermes-propose.py --reason "<왜 공유하나>" template "<에이전트 이름|id>"   # 봉투 kind=template
python3 scripts/hermes-propose.py --deliver ... template "<이름>"                           # 배달은 사람 명령으로만
```

- SOUL 에 소우주 이름·경로·티켓이 남아 있으면 누출 게이트가 거부한다 — 사람이 SOUL 을 일반화한 뒤 다시.
- 같은 에이전트를 두 소우주에 등록(겸직)하거나 파일을 직접 복사(A→B)하지 않는다.

**예** — "선적QA 를 다른 프로젝트에서도 쓰고 싶어" → `hermes-propose.py --reason "…" template 선적QA` → 봉투 확인 뒤 사용자가 배달 여부 결정.

## 5. 생애주기 (promote / retire / rehire)

```bash
python3 scripts/hermes-agent.py promote "<이름>"   # 승급
python3 scripts/hermes-agent.py retire  "<이름>"   # 은퇴 — 매칭·소환·스킬 주입에서 빠진다(파일은 남는다)
python3 scripts/hermes-agent.py rehire  "<이름>"   # 복직
```

- **은퇴·인계 실패 처리는 파괴적 판단**이다 — 사용자에게 대상과 영향(그 담당이 매칭·소환에서 빠짐)을 확인한 뒤 실행한다.
- 은퇴해도 개인 스킬·SOUL 은 파일로 남는다. `rehire` 로 되돌린다.

## 7. 가르침과 기억 (teach · note · pin)

리뷰가 곧 가르침이다(C-21): 담당이 봉투를 `finished` 로 닫으면 같은 조직의 바로 위 직급에게 **리뷰 봉투가 자동으로** 열리고, 리뷰어가
`approved` / `corrected(about, body)` 로 닫는 순간 리뷰받은 에이전트의 기억(`memory_events`)에 남는다. 같은 `about` 지적이 3회면 그 에이전트의
개인 스킬로 결정화된다. 이 절은 봉투 밖에서 기억을 다루는 세 명령이다.

```bash
python3 scripts/hermes-agent.py teach "<이름>" "<한 줄>" --about <domain>/<slug>   # 사람이 직접 가르친다(C-22)
python3 scripts/hermes-agent.py note "<한 줄>" --about <domain>/<slug>             # 소환된 에이전트가 스스로 남긴다(HERMES_AGENT_ID 세션)
python3 scripts/hermes-agent.py pin "<이름>" <memory_id>                             # 핀/해제 — 세션 시작 주입에 항상 포함
python3 scripts/hermes-agent.py refresh-memory ["<이름>"]                            # MEMORY.md 를 이벤트에서 다시 만든다(파생물)
```

- `about` 은 **`<domain>/<slug>`** 만 받는다 — domain 은 `gate · test · git · debug · workflow · file · sync · agent`, slug 는 영문·숫자·점·밑줄·하이픈.
  주제 없는 문장은 결정화 키가 못 되므로 거부된다. 사용자가 주제를 안 주면 문장에서 **묻지 말고 가장 가까운 domain/slug 를 골라 한 줄로 보여준 뒤** 실행한다.
- 본문은 기록 직전 마스킹된다(비밀값·연락처·주소·기계가 아는 사람 이름). 실제 사람 이름·연락처는 처음부터 적지 않는다.
- 되돌리기는 `unteach` 가 아니라 철회(`memory.retracted`)다 — 철회 뒤 같은 주제를 다시 가르치면 "전에 철회됨" 표시가 붙는다.
- 리뷰 봉투를 닫는 것은 코드로: `from hermes_review import close_review; close_review(db, ".", "<리뷰 봉투 id>", "corrected", "agent:<리뷰어>", about="gate/r-size", body="지적 한 줄")`.

**예** — "게이트QA 한테 400줄 넘기 전에 나누라고 가르쳐"
→ `python3 scripts/hermes-agent.py teach 게이트QA "400줄 넘기 전에 파일을 나눈다" --about gate/r-size` (about 은 문장에서 골라 보여준 값)

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
