# 기억 운반 가이드 — 원본 에이전트의 기억이 컴퓨터를 따라간다

> 설계: T-17 ~ T-21 (`docs/hermes-universe/decision-log.md` §7) · 근거 `docs/audits/2026-09-20-transport-keys-rethink.md`.
> 원칙: **원본 에이전트는 어느 컴퓨터에서든 같은 기억을 갖는다.** 복제(H-09)만 기억 없이 새로 시작한다. **읽을 권리 = 저장소 접근권.**

## 기본: 아무것도 하지 않는다

`bash update-all.sh`(또는 `setup.sh`)가 소우주를 설치할 때 **저장소가 비공개(PRIVATE·INTERNAL)면 운반을 켜고 첫 push 까지 한다.** 열쇠도 명령도 없다.

- 켜지면 `.hermes/sync.json` 이 `{"push": true, "mode": "plain"}` 로 생기고, 그 뒤는 훅이 한다: 세션 종료 때 push, 세션 시작 때 pull, pull 뒤 `MEMORY.md` 재생성.
- 공개 저장소(PUBLIC)나 판별 불가(origin 없음·`gh` 없음·미인증)면 **꺼진 채** `sync.json` 에 이유가 적힌다.
- 이미 `sync.json` 이 있으면 설치기는 손대지 않는다. 사람이 정한 값이다.

| 옮기는 길 | 내용 | 비고 |
|---|---|---|
| 코드 브랜치(`main`) | SOUL.md · 개인 스킬 · `agents.json` · `organization.yaml` · 결정화 스킬 | 보통의 push/pull |
| `refs/hermes/sync` (평문) | 세션 요약(에이전트별 대화 요약 포함, C-29) · 패턴 수 · 기억 이벤트 · 작업 이력 | 업로드 직전 마스킹 세 겹(비밀값·개인정보·기계가 아는 이름) |
| 안 옮김 | 대화 원문 · `MEMORY.md`(파생) · `state.db` 나머지 | 원문은 그 컴퓨터의 기록. 옵션(아래) |

## 에이전트의 지식은 어디까지 따라가나

> 작성일: 2026-09-28 · 근거: 이 저장소에서 `git check-ignore -v` 로 파일마다 잰 값, `scripts/hermes_sync_learning.py`·`scripts/hermes-sync.py` 가 올리는 항목.

명부 에이전트(예: 게이트QA)를 다른 컴퓨터에서 불렀을 때 **무엇을 알고 시작하나.**

| 에이전트의 지식 | 어디에 있나 | git pull 만 | 운반(`refs/hermes/sync`)까지 |
|---|---|---|---|
| 정체성 | `.hermes/agents/<id>/SOUL.md` | **따라감** | 따라감 |
| 명부·조직 | `.hermes/agents.json` · `organization.yaml` | **따라감** | 따라감 |
| 그 에이전트의 개인 스킬 | `.hermes/agents/<id>/skills/` | **따라감** | 따라감 |
| 소우주 공통 결정화 스킬 | `.hermes/skills/` | **따라감**(공장 저장소만 예외 — 아래) | 따라감 |
| 배운 것·가르친 것(기억) | `state.db` `memory_events` → `MEMORY.md`(파생) | 안 따라감 | **따라감**(`memory/`) |
| 나와 나눈 대화 요약(C-29 — 방·`@hag`·`@` 호출) | `state.db` `session_summary`(`agent_id` 붙은 행) | 안 따라감 | **따라감**(`summary/`, `agent_id` 포함) |
| 작업 이력(불린 기록·방 주인) | `state.db` `journal_events` | 안 따라감 | **따라감**(`journal/`) |
| 대화 원문 | `.hermes/history/` · 세션 기록 | 안 따라감 | 잠금 모드(`"history": true`)일 때만 |

- 한 줄로: **git 은 "누구인지·무엇을 할 줄 아는지"(SOUL·스킬)를, 운반은 "무엇을 겪었는지"(기억·대화·이력)를 옮긴다.**
  운반이 꺼져 있으면 다른 컴퓨터의 에이전트는 **자기가 누구인지는 알지만 나와 나눈 대화와 배운 것은 모른다.**
- **운반은 저장소마다 켜짐/꺼짐이 다르다.** 비공개 저장소는 설치 때 자동으로 켜지고(평문 모드), 공개 저장소는 꺼져 있다 — 공개 저장소에서 옮기려면 아래 잠금 모드.
- **공장 저장소(claude-harness-hermes) 예외:** `.gitignore` 끝에서 `.hermes/skills/` 를 다시 무시한다(공장은 소우주가 아니라 결정화 스킬을 코드에 싣지 않는다, 2026-09-16).
  (대화 원문 `.hermes/history/` 는 공장만의 예외가 아니다 — 설치기 블록이 풀어 주지 않아 **모든 저장소에서** git 으로 안 옮긴다.)
  그래서 공장에서는 공통 결정화 스킬도 git 으로 안 따라간다. 공장은 공개 저장소라 운반도 꺼져 있다(`sync.json`: `"push": false`).
- `MEMORY.md` 는 파생물이라 옮기지 않는다 — 받은 쪽에서 `memory_events` 로 다시 만든다(pull 뒤 자동).

직접 재 보기:

```bash
git check-ignore -v .hermes/agents/<id>/SOUL.md .hermes/skills/<파일> .hermes/state.db   # 출력이 있으면 git 이 안 옮긴다
cat .hermes/sync.json                                                                  # "push": true 면 운반이 켜짐
```

## 확인

```bash
cat .hermes/sync.json                     # push · mode · visibility · set_by
python3 scripts/hermes-sync.py status     # 저장소 유무 · 받은/안 받은 조각 수
python3 scripts/hermes-agent.py refresh-memory   # MEMORY.md 를 이벤트에서 다시 만든다(파생물)
```

- 비공개인데 꺼져 있으면(판별 실패): `echo '{"push": true, "mode": "plain"}' > .hermes/sync.json`.
- 다른 컴퓨터에서 clone 뒤 `update-all` 만 돌리면 같은 상태가 된다. 열쇠·합류 절차 없음.

## 옵션: 대화 원문까지 올리기 (잠금 모드)

공개 저장소이거나, 비공개라도 원문(`history/`)까지 옮기고 싶을 때만. 이때는 암호화와 열쇠가 필요하고, **열쇠는 AI 세션 밖 터미널에서 사람이** 만든다(T-11).

```bash
# 첫 컴퓨터
bash scripts/hermes-keys.sh init          # 마스터 열쇠 + 이 컴퓨터 자물쇠
bash scripts/hermes-keys.sh emergency     # 비상 24단어 — 옮겨 적어 보관
echo '{"push": true, "mode": "locked", "history": true}' > .hermes/sync.json
python3 scripts/hermes-sync.py push
# 다음 컴퓨터
bash scripts/hermes-keys.sh lock          # 이 컴퓨터 자물쇠만 → 출력된 age1… 을 첫 컴퓨터에서
bash scripts/hermes-keys.sh add-computer age1…   # (첫 컴퓨터) → push
python3 scripts/hermes-sync.py pull       # (다음 컴퓨터) 감싼 마스터를 받아 푼다
```

- `age` 는 설치기가 깐다(`lib/tool_installers.sh`). 손으로 설치하지 않는다.
- 평문 모드 컴퓨터와 잠금 모드 컴퓨터가 같은 원격을 쓰면 평문 컴퓨터는 암호문 조각을 건너뛴다. 한 소우주는 한 모드로.
- 평문 모드에서 `"history": true` 는 push 가 거부한다 — 원문은 잠금 모드에서만.

## 하지 않는 것

- 열쇠 파일을 저장소·채팅·세션에 넣지 않는다.
- 복제 에이전트(`hermes-propose.py template`)에 기억을 싣지 않는다.
- `state.db` 를 커밋하지 않는다. 사람이 관리하는 개인정보 목록도 두지 않는다(마스킹은 자동, T-20).
