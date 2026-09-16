# 이식 켜기 절차 — 소우주의 기억을 다른 컴퓨터로 옮긴다

> 작성일: 2026-09-16
> 목적: 사람이 실행하는 절차만 담는다. 열쇠 생성 → 비상 열쇠 → 정책 켜기 → 백필 → 첫 push → 다른 컴퓨터 합류. 설계 근거는 `design/protection/sync-transport.md` · `encryption-keys.md`, 계획은 `docs/exec-plans/completed/2026-09-15-sync-transport-encryption.md`.

## 개요

기억(대화 원문·작업 이력)은 코드 브랜치가 아니라 `refs/hermes/sync` 라는 별도 참조로 옮긴다.
조각은 `age` 로 잠기고, 여는 열쇠(마스터)는 **컴퓨터마다 자물쇠로 감싸** 원격에 올라간다.
켜기 전에는 로컬 전용이다 — 아무것도 원격으로 나가지 않는다.

**AI 세션 안에서 열쇠 명령을 치지 않는다.** 세션 안 Bash 는 키 가드 훅이 막는다(T-11).
아래는 전부 **따로 연 터미널**에서 한다.

## 0. 서버가 사용자 정의 참조를 받는지 (한 번만)

```bash
cd <소우주>
git push origin HEAD:refs/hermes/sync-probe && git ls-remote origin 'refs/hermes/*'
git push origin :refs/hermes/sync-probe     # 정리
```

- 2026-09-16 실측: gitlab.com · 사내 Gitea(`211.206.116.39:3000`) · github.com 모두 **허용**.
- 거부되면 그 소우주는 **이식을 켜지 않는다**(T-15). `hermes-sync.py status` 가 "이식 불가 —
  사람 판단" 을 낸다. 폴백 브랜치는 동료 브랜치 목록에 보이므로 쓰지 않는다.

## 1. 첫 컴퓨터 — 열쇠 만들기

```bash
scripts/hermes-keys.sh doctor      # age 설치·열쇠 유무 점검
scripts/hermes-keys.sh init        # 마스터 + 이 컴퓨터 자물쇠, 감싼 마스터 1개
scripts/hermes-keys.sh emergency   # 비상 열쇠 — 24단어를 종이에 옮겨 적고 재입력으로 확인
```

- `emergency` 는 24단어를 **한 번만** 보여 준다. 사진·클라우드 메모·저장소 안에 두지 않는다.
  재입력이 맞고 시험 복호가 성공해야 등록되며, 평문 열쇠 파일은 남지 않는다.
- 열쇠는 `~/.hermes/keys/<universe_id>/` 에만 있다(0600). 원격에는 감싼 것만 올라간다.
- `age` 가 없으면: `sudo apt install age` 또는 GitHub 릴리스 바이너리를 `~/.local/bin` 에.

## 2. 정책 켜기 (컴퓨터마다)

```bash
echo '{"push": true}' > .hermes/sync.json
```

- 이 파일은 **컴퓨터 로컬**이다(`.hermes/*` 무시 규칙, 커밋 안 됨). 동료 clone 이 물려받지
  않으므로 열쇠 없는 컴퓨터가 매 세션 "보류" 를 찍지 않는다. 컴퓨터마다 한 번씩 켠다.
- 없으면 로컬 전용(기본). 세션 시작 훅이 "이식 꺼짐" 을 로그에 한 줄 남긴다.

## 3. 백필과 첫 push

```bash
python3 scripts/hermes-sync.py status      # 저장소 없음 → 정상(아직 아무도 안 올림)
python3 scripts/hermes-sync.py backfill    # 기존 원문을 조각으로 만들어 올린다(멱등)
python3 scripts/hermes-sync.py status      # 받은 조각 N건 …
```

- 백필은 두 번 돌려도 조각 수가 늘지 않는다.
- 이후에는 세션 종료 훅이 새 조각을 자동으로 push 한다.

## 4. 다른 컴퓨터 합류

새 컴퓨터(B)에서:

```bash
git clone <원격> && cd <소우주>
bash setup.sh   # 또는 공장에서 project-claude.sh — universe.id 는 clone 으로 이미 있다
age-keygen -o ~/.hermes/keys/<universe_id>/computer.key   # 이 컴퓨터 자물쇠(마스터는 아직 없음)
age-keygen -y ~/.hermes/keys/<universe_id>/computer.key   # 자물쇠(age1…)를 복사
echo '{"push": true}' > .hermes/sync.json
python3 scripts/hermes-sync.py pull       # "열쇠가 없습니다 — 조각 N건" (정상, H-10)
```

첫 컴퓨터(A)에서 B 의 자물쇠를 등록하고 올린다:

```bash
scripts/hermes-keys.sh add-computer age1…   # B 의 자물쇠
python3 scripts/hermes-sync.py push
```

다시 B 에서:

```bash
python3 scripts/hermes-sync.py pull       # "감싼 마스터를 받아 풀었습니다" → 조각 복호
python3 scripts/hermes-reindex.py --db .hermes/state.db --project .   # 또는 다음 세션 시작 훅
```

- B 의 `~/.hermes/keys/<universe_id>/master.key` 가 생기고(0600) 이후는 A 와 같다.

## 5. 문제가 생겼을 때

| 증상 | 뜻 | 할 일 |
|---|---|---|
| `원격에 기억 저장소가 없습니다` | 아직 아무도 push 안 함 | 첫 컴퓨터에서 backfill |
| `열쇠가 없습니다 — 조각 N건` | 이 컴퓨터 자물쇠가 미등록 | 4절 합류 절차 |
| `기억 0건` | 저장소·열쇠는 있으나 조각 없음 | 정상. 세션을 쓰면 쌓인다 |
| `이식 불가 — 사람 판단` | 서버가 참조 거부 | 그 소우주는 켜지 않는다 |
| `age 가 없어 … 건너뜁니다` | 이 컴퓨터에 age 없음 | 1절 설치 |
| 컴퓨터 분실 | 그 자물쇠로 마스터를 풀 수 있음 | `revoke <지문>` + `rotate-master`(옛 조각은 옛 마스터로만) |
| 컴퓨터 전부 분실 | 비상 열쇠 24단어만 남음 | 새 컴퓨터에서 24단어로 열쇠 복원 → `add-computer` |

## 6. 비상 삭제 (tombstone)

비밀값이 원문에 새어 들어간 것을 발견했을 때만. **사람이 세션 밖에서**:

```bash
python3 scripts/hermes-sync.py tombstone history/<session_id>/<순번>.enc --confirm
```

원격 참조를 재작성하고 로컬 조각을 지운다. 코드 이력은 건드리지 않는다. 이미 pull 한 다른
컴퓨터의 사본은 그 컴퓨터에서 따로 지워야 한다.

## 7. 적용 순서 (2026-09-16 기준)

1. terminal-shipping — 혼자 쓰는 저장소. 여기서 먼저 켠다.
2. zeroday-frontend — 동료 3명. 서버(Gitea)가 참조를 허용함을 확인했으므로 켤 수 있다.
   동료가 `age` 를 설치하지 않으면 그 컴퓨터는 매 세션 한 줄("age 가 없어 건너뜁니다")만 남긴다.
3. 나머지 소우주 — 필요할 때.

각 소우주의 `.gitignore` 변경(원문 예외 제거)은 공장 재설치 때 이미 반영됐다. 이미 추적 중인
평문 파일(zeroday 241 · terminal-shipping 31)은 그대로 둔다(T-03).
