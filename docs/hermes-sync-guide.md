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
| `refs/hermes/sync` (평문) | 세션 요약 · 패턴 수 · 기억 이벤트 · 작업 이력 | 업로드 직전 마스킹 세 겹(비밀값·개인정보·기계가 아는 이름) |
| 안 옮김 | 대화 원문 · `MEMORY.md`(파생) · `state.db` 나머지 | 원문은 그 컴퓨터의 기록. 옵션(아래) |

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
