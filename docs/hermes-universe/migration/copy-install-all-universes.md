# 이전 절차 — 등록된 모든 소우주를 복사 설치로 전환한다

> 작성일: 2026-09-16
> 목적: 사람이 실행하는 절차만 담는다. 명령 순서, 저장소마다 확인할 것, 커밋 방법. 설계 근거는 [copy-install.md](../design/world/copy-install.md), 계획은 `docs/exec-plans/active/2026-09-15-copy-install.md` Step 7.

## 개요

`update-all.sh` 한 번이면 이 컴퓨터에 등록된 **12개 소우주 전부**에서 공장 절대경로 심링크가 복사본으로
바뀐다. 각 저장소에는 링크 → 파일 모드 변경(`120000 → 100644`) diff 와 새 파일 두 개
(`.claude/.factory-manifest.json`, `.hermes/factory.json`)가 생긴다. **커밋은 저장소마다 사람이 한다.**
자동 커밋은 없다.

## 1. 실행 전 확인

```bash
cd ~/PROJECT/claude-harness-hermes
wc -l < .installed-projects                 # 등록 수 (2026-09-16 실측: 12)
grep -c zeroday-frontend .installed-projects # 1 이어야 함
git status --short | wc -l                   # 공장 작업 트리가 깨끗한지 (0)
git log --oneline -1                         # 이 커밋 해시가 각 소우주 factory.json 의 installed_version 이 된다
```

- 공장 작업 트리가 깨끗하지 않으면 먼저 커밋한다. `installed_version` 은 공장 HEAD 를 적으므로
  미커밋 상태로 전파하면 소우주가 존재하지 않는 버전을 가리킨다.
- 등록되지 않은 소우주는 이 절차가 닿지 않는다. 있다면 `bash setup.sh` 로 먼저 등록한다.

## 2. 전파

```bash
bash update-all.sh 2>&1 | tee .harness/out/copy-install-migration.log
grep -E "이행: 기존 심링크|링크 → 복사본" .harness/out/copy-install-migration.log
```

- 소우주마다 `이행: 기존 심링크 N건을 설치 목록에 옮겨 적음` 과 `링크 → 복사본 N건` 이 한 번씩 나온다.
  zeroday-frontend 는 41건(스킬 22 · 규칙 6 · 에이전트 14 — 2026-09-15 실측), 공장 자신은 이행 25건에
  "링크 → 복사본" 은 0건(상대경로 링크로 남는다).
- 두 번째 실행부터는 이행 문구가 나오지 않는다(목록이 이미 있음).

## 3. 저장소마다 확인하고 커밋

각 소우주에서:

```bash
cd <소우주>
git status --short | head -50
```

| 확인 | 기대 |
|---|---|
| 심링크 잔존 | `find .claude/skills .claude/rules .claude/agents -type l \| wc -l` → `0` |
| git 추적 링크 | `git ls-files -s .claude \| awk '$1==120000' \| wc -l` → `0` (커밋 후) |
| 설치 목록 | `.claude/.factory-manifest.json` 이 새 파일로 보임 |
| 공장 위치 | `.hermes/factory.json` 이 새 파일로 보임 (`.gitignore` 예외 `!.hermes/factory.json`) |
| 소우주 자체 스킬 | 그대로 있음. 목록에 없는 폴더는 설치기가 건드리지 않는다 |
| 이름 겹침 백업 | `*.backup-<날짜>` 폴더가 생겼다면 소우주 자체 자산이 공장 이름과 겹친 것 — 내용을 보고 정리 |

문제가 없으면 커밋한다. **add 경로를 손으로 고르지 않는다** — 설치기가 이번에 쓴 파일 목록
(`.claude/.last-install.txt`, 설치 영수증)을 그대로 쓴다. 2026-09-16 에 경로를 손으로 골라
`scripts/hermes-*.py` 사본 7개를 5곳에서 빠뜨렸다(계획 `2026-09-16-install-receipt.md`).

```bash
git add $(git ls-files -co --exclude-standard -- $(cat .claude/.last-install.txt))
git commit -m "chore(harness): 공장 심링크를 복사 설치로 전환한다 (.factory-manifest.json 추가)"
```

빠뜨리면 다음 세션 시작 때 `[install-uncommitted WARN] 설치물 N건이 커밋되지 않았습니다` 가 뜬다.

zeroday-frontend 는 동료 3명이 있는 저장소다. 커밋 내용은 "설치물이 링크에서 파일로 바뀜" 뿐이고,
동료가 pull 하면 깨져 있던 스킬·규칙·에이전트가 처음으로 동작한다.

## 4. 다른 컴퓨터에서 확인

```bash
git pull
ls .claude/skills/*/SKILL.md | head -3        # 실제 파일이어야 함 (링크가 아님)
python3 -c "import json;print(len(json.load(open('.claude/.factory-manifest.json'))['items']))"
```

공장이 없는 컴퓨터에서도 동작한다. 공장이 있어도 재설치 전까지는 pull 받은 복사본을 그대로 쓴다.

## 5. 되돌리기

복사 설치는 공장 자산의 사본이므로 되돌릴 것이 없다. 링크로 돌아가려면 옛 공장 커밋(`25e4ce0` 이전)으로
`update-all.sh` 를 돌리면 되지만, 그러면 다른 컴퓨터에서 다시 깨진다 — 권하지 않는다.

## 6. 저장소 크기

복사 설치로 소우주 저장소가 커진다. 2026-09-16 공장 실측: `assets/skills` 1.3MB · `assets/rules` 276KB ·
`assets/agents` 84KB (설치 프리셋에 따라 일부만 복사됨). 줄이는 일은 이번 범위 밖.
