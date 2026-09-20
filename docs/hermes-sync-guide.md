# 기억 운반 가이드 — 원본 에이전트의 기억이 컴퓨터를 따라간다

> 계획: `docs/exec-plans/active/2026-09-19-agent-memory-roundtrip.md` 목표 4. 설계: C-14·C-20(memory-events.md) · T-11(encryption-keys.md) · sync-transport.md.
> 원칙: **원본 에이전트는 어느 컴퓨터에서든 같은 기억을 갖는다.** 복제(H-09)만 기억 없이 새로 시작한다.

## 무엇이 어떻게 옮겨지나

| 옮기는 길 | 내용 | 비고 |
|---|---|---|
| 코드 브랜치(`main`) | SOUL.md · 개인 스킬 · `agents.json` · `organization.yaml` · 결정화 스킬 | 보통의 push/pull |
| `refs/hermes/sync` | 기억 이벤트(`memory/<agent>/<id>.json`) · 작업 이력(`journal/`) · 대화 조각(`history/`) | 별도 ref. 자유 글 칸은 `age` 로 암호화, 기계 칸(id·시각·about)은 평문 |
| 안 옮김 | `MEMORY.md`(파생) · `state.db` 나머지 | pull 뒤 `MEMORY.md` 는 이벤트에서 다시 만들어진다 |

`age` 는 설치기가 깐다(`bash update-all.sh`, `lib/tool_installers.sh`). 손으로 설치하지 않는다.

## 1. 첫 컴퓨터 — 켜기 (한 번)

**열쇠는 AI 세션 밖 터미널에서** 만든다(T-11, 세션 안 Bash 는 가드가 막는다).

```bash
cd <소우주>
bash scripts/hermes-keys.sh doctor          # age 있음 · 열쇠 없음 확인
bash scripts/hermes-keys.sh init            # 마스터 열쇠 + 이 컴퓨터 자물쇠 → ~/.hermes/keys/<universe.id>/
bash scripts/hermes-keys.sh emergency       # 비상 열쇠 24단어 — 옮겨 적고 보관(잃으면 과거 조각을 못 연다)
echo '{"push": true}' > .hermes/sync.json   # 이 컴퓨터에서 올리기 허락(컴퓨터 로컬, 커밋 안 함)
python3 scripts/hermes-sync.py push         # refs/hermes/sync 생성 · 자물쇠·감싼 마스터 업로드
python3 scripts/hermes-sync.py status
```

이후는 자동이다: 세션 종료 훅이 `push`, 세션 시작 훅이 `pull` 한다.

## 2. 다음 컴퓨터 — 합류

새 컴퓨터(B)에서, 역시 세션 밖 터미널에서:

```bash
git clone <원격> && cd <소우주>
bash update-all.sh 로 설치(공장에서) 또는 project-claude.sh   # age 포함
bash scripts/hermes-keys.sh lock            # 이 컴퓨터 자물쇠만 만든다(마스터 X). 출력된 age1… 을 복사
```

마스터가 있는 컴퓨터(A)에서:

```bash
bash scripts/hermes-keys.sh add-computer age1…   # B 자물쇠로 마스터를 한 번 더 감싼다
python3 scripts/hermes-sync.py push
```

다시 B 에서:

```bash
echo '{"push": true}' > .hermes/sync.json
python3 scripts/hermes-sync.py pull         # "감싼 마스터를 받아 풀었습니다" → 조각·이력·기억 복호 적재
python3 scripts/hermes-agent.py list        # 명부는 main 으로 이미 와 있다
cat .hermes/agents/<id>/MEMORY.md           # pull 이 이벤트에서 다시 만든 보기
```

## 3. 확인·문제

- `python3 scripts/hermes-sync.py status` — 저장소·열쇠·받은 조각 수.
- 세션 시작에 `열쇠가 없습니다 … (H-10)` 이 뜨면 2 단계(`lock` → `add-computer`)가 안 된 것이다.
- `age 가 없어 pull 을 건너뜁니다` 가 뜨면 설치기를 다시 돌린다(`bash update-all.sh`). `~/.local/bin` 이 PATH 에 있어야 한다.
- 서버가 `refs/hermes/sync` 를 거부하면(T-15) 이식 불가 — 사람 판단.
- `MEMORY.md` 가 옛것처럼 보이면 `python3 scripts/hermes-agent.py refresh-memory` 로 다시 만든다(파생물이라 손으로 고치지 않는다).

## 4. 하지 않는 것

- 열쇠 파일을 저장소·채팅·세션에 넣지 않는다. 마스터는 감싼 형태로만 원격에 간다.
- 복제 에이전트(`hermes-propose.py template`)에 기억을 싣지 않는다 — 새 id·수습부터.
- `state.db` 를 커밋하지 않는다.
