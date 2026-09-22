# 2026-09-22-gitignore-judge — 무시 판정을 종료 코드가 아니라 패턴으로 한다

## 1. 동기 (Why)

**실측 2026-09-22 (git 2.25.1, WSL2).** `git check-ignore -q <경로>` 의 종료 코드로
"무시되는가" 를 판정하는 코드가 세 곳 있는데, 옛 git 에서 그 종료 코드가 **예외 규칙(`!`)에
걸린 경로에도 0(무시됨)** 을 준다. 같은 저장소를 신형 git 으로 보면 1 이다.

픽스처로 직접 재현:

```
.gitignore = ".claude/*" + "!.claude/keep.json"

.claude/keep.json   rc=0   .gitignore:2:!.claude/keep.json	.claude/keep.json   ← 예외인데 rc 0
.claude/drop.json   rc=0   .gitignore:1:.claude/*	.claude/drop.json           ← 무시됨, rc 0
```

**종료 코드로는 둘을 못 가른다.** 구분 신호는 `-v` 출력의 **패턴 앞 `!`** 뿐이다.

### 무엇이 깨져 있나

| 자리 | 지금 동작 | 옛 git 에서의 결과 |
| --- | --- | --- |
| `scripts/harness-doctor.py:137` | `check-ignore -q` rc == 0 → `"ignored"` | 예외로 **추적되는** 매니페스트를 `ignored` 로 **오보** |
| `lib/harness_installers.sh:610` | 같은 판정으로 설치 경고 | 멀쩡한 프로젝트에 "추적되지 않습니다" 경고 |
| `tests/copy-install-test.sh:65` | 같은 판정을 직접 단언 | 이 컴퓨터에서만 빨강 |
| `tests/manifest-tracking-test.sh:56` | doctor 경유 | 이 컴퓨터에서만 빨강 |

시험 2건이 빨간 것은 증상이고, **오보하는 제품 코드 2곳이 본체다.** CI(신형 git)는 초록이라
아무도 몰랐다 — 이 컴퓨터에서만 드러났다.

## 2. 목표 (검증 가능한 형태)

- [x] 목표 1 — 무시 판정이 git 판 차이와 무관하게 같다. 검증: `tests/git-ignore-judge-test.sh` —
      `.claude/*` + `!.claude/keep.json` 픽스처에서 keep=무시 아님 · drop=무시됨 · 규칙 밖 경로=무시 아님.
- [x] 목표 2 — 판정기는 **한 곳**에만 있고 세 자리가 그것을 쓴다. 검증: `grep -c "check-ignore"` 가
      `scripts/git_ignore_judge.py` 밖에서 0.
- [x] 목표 3 — doctor 가 옛 git 에서도 예외로 추적되는 매니페스트를 `uncommitted` 로 말한다.
      검증: `bash tests/manifest-tracking-test.sh` 통과(이 컴퓨터, git 2.25.1).
- [x] 목표 4 — 설치 경고가 멀쩡한 프로젝트에 뜨지 않는다. 검증: `bash tests/copy-install-test.sh` 통과.

## 2-bis. 착수 전 확인한 사실 (2026-09-22)

| 확인한 것 | 결과 |
| --- | --- |
| 이 컴퓨터의 git | 2.25.1 |
| `check-ignore -v` 출력 모양 | `<출처>:<줄>:<패턴>\t<경로>` |
| 예외 규칙일 때 rc | **0** (신형 git 은 1) |
| 규칙에 아예 안 걸릴 때 | 출력 없음 |
| `check-ignore` 호출 자리 | 제품 2 (`harness-doctor.py:137` · `harness_installers.sh:610`) + 시험 1 (`copy-install-test.sh:65`) |
| `.deprc` 의 새 모듈 규칙 | `scope: scripts/*.py lib/*.py assets/hooks/*.py`, 표준 모듈만 쓰면 tier 0 |
| scripts ↔ lib 교차 import 선례 | 없음 → 새 모듈은 `scripts/` 에 두고 셸은 CLI 로 부른다 |

## 3. 비목표

- git 최소 판 올리기. 이 컴퓨터의 배포판이 주는 판을 바꾸지 않는다.
- `check-ignore` 를 안 쓰고 `.gitignore` 를 직접 파싱하는 것. 규칙 해석은 계속 git 에게 맡긴다 —
  바뀌는 것은 **답을 읽는 방법**뿐이다.
- 다른 옛 git 차이(직전 세션에서 고친 `init -b` 등) 재점검.

## 4. 영향 영역

- **신규 파일 목록 (파일별 책임 1줄)**
  - `scripts/git_ignore_judge.py` — **git 이 이 경로를 무시하는가** 한 가지만 판정한다(공개: `is_ignored` · `main`).
  - `tests/git-ignore-judge-test.sh` — 그 판정기의 세 경우(예외·무시·규칙 밖)를 픽스처로 단언한다.
- 코드 수정: `scripts/harness-doctor.py`(판정기 사용) · `lib/harness_installers.sh`(CLI 경유) ·
  `tests/copy-install-test.sh`(판정기 사용) · `tests/run-all.sh`(새 시험 등록, 고아 검사)
- 룰: 없음. 데이터: 없음. 외부 의존: 없음(표준 모듈만).

## 5. 단계

### Step 1. 판정기 시험 먼저 (RED)
- 산출: `tests/git-ignore-judge-test.sh` + `tests/run-all.sh` 등록
- 검증: 모듈이 없어 실패한다

### Step 2. 판정기 구현 (GREEN)
- 산출: `scripts/git_ignore_judge.py` + `.deprc` tier 0 등록
- 검증: `bash tests/git-ignore-judge-test.sh` 통과

### Step 3. 세 자리를 판정기로 옮긴다
- 산출: doctor · 설치기 · copy-install 시험
- 검증: `manifest-tracking` · `copy-install` · `harness-doctor` 시험 통과

### Step 4. 전체
- 검증: `bash tests/run-all.sh` — 남는 실패는 `claude-config-scan` 1건(설정 기준선, 별건)

## 6. 의사결정 로그

- 2026-09-22: **판정기를 `scripts/` 의 파이썬 한 곳에 두고 셸은 CLI 로 부른다** — 근거: 같은 판정을
  셸·파이썬 두 벌로 쓰면 한쪽만 고쳐지는 날이 온다(DRY). 교차 import 선례가 없어 import 대신 CLI.
  틀렸을 때 손해: 설치 중 python3 호출이 한 번 는다(설치기는 이미 python3 를 쓴다).
- 2026-09-22: **`.gitignore` 직접 파싱은 안 한다** — 근거: 규칙 해석(부정·디렉터리·전역 무시 파일)은
  git 이 정본이다. 틀렸을 때 손해: git 이 없는 환경에서는 판정 불가(지금도 그렇다).
- 2026-09-22: **`claude-config-scan` 실패는 이번 계획에서 안 고친다** — 근거: 원인이 다르다
  (`.claude/settings.local.json` 의 `Bash(git push *)` 가 기준선 미등록). 설정 변경은 사람 승인 사항.
  틀렸을 때 손해: 전체 시험이 1건 빨간 채 남는다.

## 7. 발견·예외

- **doctor 가 이웃 모듈에 의존하게 되자 자기 검사가 깨졌다.** `tests/harness-doctor-test.sh:56` 은
  doctor 를 `$T/doctor-broken.py` 로 **복사해** 돌려 "sha 대조를 끄면 변조를 못 잡는다" 를 확인한다.
  복사본은 `scripts/` 밖이라 `sys.path.insert(… __file__ …)` 가 판정기를 못 찾아 죽었다.
  → 복사본 실행에 `PYTHONPATH="$(dirname "$DOC")"` 를 줬다. 시험의 의도(대조를 끄면 빨개진다)는 그대로다.
  교훈: **복사해서 돌리는 자기 검사는 그 파일이 단독이라는 전제를 숨기고 있다.** 모듈을 나눌 때 같이 깨진다.
- 목표 2 의 첫 단언이 **주석에 남은 낱말까지 세어** 빨갰다. `git … check-ignore` 호출만 세도록 좁혔다
  (주석 줄·`__pycache__` 제외). 낱말 금지가 아니라 호출 금지가 의도다.

## 8. 회고 (2026-09-22)

- 잘된 것:
  - **증상이 아니라 본체를 고쳤다.** 빨간 것은 시험 2건이었지만 원인은 오보하는 제품 코드 2곳이었다.
    시험만 손봤으면 옛 git 환경의 doctor 는 계속 `ignored` 로 거짓말했을 것이다.
  - 판정기를 한 곳에 두고 **"밖에 호출 0" 을 시험이 지킨다** — 다시 흩어지면 빨개진다.
  - 픽스처로 옛 git 의 실제 출력을 먼저 재현하고 나서 설계했다. 추측한 형식이 아니라 본 형식을 파싱한다.
- 잘못된 것:
  - 목표 2 의 첫 단언이 **주석의 낱말까지 세어** 스스로 빨갰다. 금지 대상은 낱말이 아니라 호출이다.
  - doctor 를 모듈로 쪼개자 **복사해서 돌리는 자기 검사**가 죽었다(§7). 파일을 나눌 때
    "이 파일을 다른 데로 복사해 돌리는 시험이 있는가" 를 먼저 보지 않았다.
- 다음 룰 후보: **R-portable-verdict** — git 명령의 **종료 코드**로 판정하는 새 코드를 경고한다
  (`check-ignore`·`merge-base --is-ancestor` 등 판 차이가 있는 것들 목록). 근거: 옛 git 차이가
  09-21 에 4건, 09-22 에 1건 더 나왔다 — 다섯 번째다.
