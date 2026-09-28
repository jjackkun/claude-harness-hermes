# 기억 운반 가이드 — 원본 에이전트의 기억이 컴퓨터를 따라간다

> 설계: T-17 ~ T-23 (`docs/hermes-universe/decision-log.md` §7) · A-11 · C-30 ~ C-32 (§8) · 근거 `docs/audits/2026-09-20-transport-keys-rethink.md`, 계획 `docs/exec-plans/active/2026-09-28-carry-agent-knowledge.md`.
> 원칙: **원본 에이전트는 어느 컴퓨터에서든 같은 기억을 갖는다.** 복제(H-09)만 기억 없이 새로 시작한다. **읽을 권리 = 저장소 접근권.**

## 두 길: git 파일과 운반

에이전트 지식은 두 길로 컴퓨터를 옮긴다. 둘 다 사람이 할 일은 없다.

| 옮기는 길 | 내용 | 언제 |
|---|---|---|
| 코드 브랜치(`main`) — **git 파일** | SOUL.md · 개인 스킬 · `agents.json` · `organization.yaml` · 결정화 스킬 · **기억(`memory.jsonl`) · 나와 나눈 대화 요약(`conversations/`) · 작업 이력(`journal.jsonl`)** | 세션 끝에 파일로 쓰이고, 보통의 커밋·push/pull 로 간다. 세션 시작에 DB 로 들어온다 |
| `refs/hermes/sync` — **운반** | 패턴 수 · 공통 대화 요약(판정 통과 항목만) | 세션 끝 push, 세션 시작 pull. **공개·비공개 구분 없이 켜진다**(T-22) |
| 안 옮김 | 대화 원문(**저장하지 않는다**, T-23) · `MEMORY.md`(파생) · `state.db` · 방·세션(`--resume`) · `@hag` 상태 | — |

- **올리기 전 묻기(C-31):** 요약·기억·이력 자유 글·스킬은 내보내기 전에 "개인적 · 업무 무관" 인지 판정한다. 걸리거나 판정에 실패한 문장은 **파일에 쓰지 않고** 검토 대기로 둔다. 커밋할 때 R-privacy 게이트가 확인 안 된 문장을 막는다.
- **누구와의 대화인지(C-30):** 대화 요약에는 사람 이름표(git `user.name`)가 붙는다. 에이전트를 부르면 **부른 사람과 나눈 대화만** 들어간다. 이름표일 뿐 신원 증명은 아니다.
- 마스킹(비밀값·개인정보 형태)은 저장 전과 업로드 직전에 그대로 거친다(T-20).

## 에이전트의 지식은 어디까지 따라가나

> 갱신: 2026-09-28 (A-11·T-22·T-23 반영) · 근거: `git check-ignore -v` 로 잰 값, `scripts/hermes-knowledge-files.py` · `scripts/hermes_sync_learning.py` 가 옮기는 항목.

명부 에이전트(예: 게이트QA)를 다른 컴퓨터에서 불렀을 때 **무엇을 알고 시작하나.**

| 에이전트의 지식 | 어디에 있나 | 어떻게 따라가나 |
|---|---|---|
| 정체성 | `.hermes/agents/<id>/SOUL.md` | git |
| 명부·조직 | `.hermes/agents.json` · `organization.yaml` | git |
| 그 에이전트의 개인 스킬 | `.hermes/agents/<id>/skills/` | git |
| 소우주 공통 결정화 스킬 | `.hermes/skills/` | git (공장 포함, C-32) |
| 배운 것·가르친 것(기억) | `.hermes/agents/<id>/memory.jsonl` → DB `memory_events` → `MEMORY.md`(파생) | git (판정 통과 줄만) |
| 나와 나눈 대화 요약(C-29·C-30) | `.hermes/agents/<id>/conversations/<사람>/<세션>.json` | git (5칸 요약, 판정 통과 항목만) |
| 작업 이력(인계·결정·입사·교훈·명부 호출) | `.hermes/journal.jsonl` | git (골라서 — 보조 호출은 안 감) |
| 공통 대화 요약 · 패턴 수 | DB `session_summary`(주인 없음) · `pattern_count` | 운반 |
| 대화 원문 | — | 저장하지 않는다 |

- 한 줄로: **git 이 "누구인지·무엇을 할 줄 아는지·무엇을 겪었는지" 를 옮기고, 운반은 학습 재료(패턴 수·공통 요약)만 옮긴다.**
- 커밋은 사람이 한다. 세션 끝에 파일이 바뀌어 있으면 평소처럼 커밋·push 하면 된다. `.hermes/agents/*/memory.jsonl` 과 `.hermes/journal.jsonl` 은 `merge=union` 이라 두 컴퓨터가 동시에 줄을 더해도 병합이 충돌하지 않는다.
- `MEMORY.md` 는 파생물이라 옮기지 않는다 — 받은 쪽이 `memory.jsonl` 에서 다시 만든다(세션 시작 자동).

직접 재 보기:

```bash
git check-ignore -v .hermes/agents/<id>/memory.jsonl .hermes/journal.jsonl .hermes/state.db   # 출력이 '!' 로 시작하거나 없으면 git 이 옮긴다
python3 scripts/hermes-privacy-review.py list                                                 # 올리기 전 확인할 문장
cat .hermes/sync.json                                                                        # 운반 설정
```

## 확인

```bash
python3 scripts/hermes-knowledge-files.py export   # 판정 → 세 파일 쓰기(세션 끝 훅이 자동으로 한다)
python3 scripts/hermes-knowledge-files.py import   # 세 파일 → DB, MEMORY.md(세션 시작 훅이 자동으로 한다)
python3 scripts/hermes-privacy-review.py           # 검토 대기를 하나씩 보고 지움/둠(터미널)
python3 scripts/hermes-sync.py status              # 운반 저장소 · 받은/안 받은 조각 수
python3 scripts/hermes-agent.py refresh-memory     # MEMORY.md 를 이벤트에서 다시 만든다(파생물)
```

- 세션 안에서는 `hermes-privacy-review.py list` 로 해시를 보고 `decide <해시 앞 8자> keep|drop` 으로 정한다(keep=둠, drop=지움).
- 설치기는 `sync.json` 을 `{"push": true, "mode": "plain", ...}` 로 만든다. 전에 설치기가 끈 값(`"set_by": "installer"`, `"push": false`)은 켜고 로그에 알린다. 사람이 쓴 값은 그대로 둔다.

## 옵션: 운반을 암호화하기 (잠금 모드)

운반 조각(패턴 수·공통 요약)까지 암호문으로 두고 싶을 때만. 열쇠는 **AI 세션 밖 터미널에서 사람이** 만든다(T-11).

```bash
# 첫 컴퓨터
bash scripts/hermes-keys.sh init          # 마스터 열쇠 + 이 컴퓨터 자물쇠
bash scripts/hermes-keys.sh emergency     # 비상 24단어 — 옮겨 적어 보관
echo '{"push": true, "mode": "locked"}' > .hermes/sync.json
python3 scripts/hermes-sync.py push
# 다음 컴퓨터
bash scripts/hermes-keys.sh lock          # 이 컴퓨터 자물쇠만 → 출력된 age1… 을 첫 컴퓨터에서
bash scripts/hermes-keys.sh add-computer age1…   # (첫 컴퓨터) → push
python3 scripts/hermes-sync.py pull       # (다음 컴퓨터) 감싼 마스터를 받아 푼다
```

- `age` 는 설치기가 깐다(`lib/tool_installers.sh`). 손으로 설치하지 않는다.
- 평문 모드 컴퓨터와 잠금 모드 컴퓨터가 같은 원격을 쓰면 평문 컴퓨터는 암호문 조각을 건너뛴다. 한 소우주는 한 모드로.
- 원문 운반(`"history": true`)은 없어졌다(T-23) — 남아 있는 키는 무시된다.

## 하지 않는 것

- 열쇠 파일을 저장소·채팅·세션에 넣지 않는다.
- 복제 에이전트(`hermes-propose.py template`)에 기억을 싣지 않는다.
- `state.db` 를 커밋하지 않는다. 사람이 관리하는 개인정보 목록도 두지 않는다(마스킹은 자동, T-20).
- 이미 쌓인 옛 원문(`session_history`, `.hermes/history/`)을 코드가 지우지 않는다 — 지울지는 사람이 정한다.
