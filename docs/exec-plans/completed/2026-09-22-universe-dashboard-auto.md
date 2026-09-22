# 2026-09-22-universe-dashboard-auto — 우주 대시보드도 세션 시작 훅이 갱신한다

## 1. 동기 (Why)

- 소우주 대시보드는 SessionStart 훅이 24시간마다 자동 갱신한다 (계획 2026-09-18-hermes-dashboard 목표 7).
- **우주 대시보드(`--universe`)를 부르는 비시험 코드는 저장소 전체에 0곳이다.** 스킬 문서와
  `tests/hermes-dashboard-test.sh` 에만 있다. 즉 사람이 직접 칠 때만 생긴다.
- 실측 2026-09-22: `.hermes/universe-dashboard.html` 의 mtime 이 2026-09-21 00:03 — 이틀 묵어 있었다.
  사용자가 "내가 이렇게 항상 말해야만 생기는 거냐" 고 물어 드러났다.
- 묵은 페이지는 "갱신이 멈춘 페이지를 최신으로 오인" 시킨다 — `hermes-dashboard.py:_write` 가
  옛 경로 파일을 지우는 이유와 같은 위험이다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 공장에서 세션을 시작하면 우주 대시보드도 같은 주기로 갱신된다.
      검증: `tests/hermes-dashboard-test.sh` 에서 레지스트리를 둔 픽스처로 훅을 돌려
      `.hermes/dashboards/universe-dashboard.html` 이 생기는지 단언.
- [x] 목표 2 — 소우주(레지스트리 없음)에서는 우주 갱신을 하지 않는다.
      검증: 같은 시험에서 레지스트리 없는 픽스처로 훅을 돌려 그 파일이 **없음**을 단언.
- [x] 목표 3 — 기존 성질(세션 시작 지연 0 · 어떤 경우에도 rc 0 · stdout 무출력 · throttle)이 그대로다.
      검증: `tests/hermes-dashboard-test.sh` 의 기존 훅 단언 6개가 그대로 통과.

## 2-bis. 착수 전 확인한 사실 (2026-09-22)

| 확인한 것 | 결과 |
| --------- | ---- |
| `--universe` 를 부르는 비시험 코드 | **0곳** (스킬 문서·시험만) |
| 훅의 현재 호출 | `python3 "$cli" --project-dir "$project_dir"` 한 줄 |
| 우주 CLI 의 레지스트리 기본값 | `<공장>/.installed-projects` (`hermes-dashboard.py:41-48`) |
| 이 저장소의 레지스트리 | 3줄 — ai-create · wonil · terminal-shipping |
| 훅 파일 사본 2개 | `scripts/hooks/` 와 `assets/hooks/` 가 `diff -q` 동일 |
| 훅 시험이 쓰는 사본 | `assets/hooks/claude-sessionstart-dashboard.sh` (시험 149줄) |
| 대시보드 산출물의 git 추적 | `.gitignore:47 .hermes/*` — dashboards 는 예외 목록에 없음 |

## 3. 비목표 (Out of Scope)

- **대시보드 HTML 을 git 에 올리는 것.** 대시보드는 그 컴퓨터 로컬 `state.db` 의 스냅샷이라
  커밋하면 컴퓨터마다 내용이 달라 풀할 때마다 충돌한다. (B)안으로 검토하고 기각했다.
- throttle 시간(24h) 변경.
- 우주 대시보드의 표·내용 변경.
- `harness-doctor.py` 의 옛 git `check-ignore` 오보 — 별건. 이번 계획에서 건드리지 않는다.

## 4. 영향 영역

- 코드: `scripts/hooks/claude-sessionstart-dashboard.sh` · `assets/hooks/claude-sessionstart-dashboard.sh`
  (두 사본을 동일하게 수정)
- **신규 파일 목록**: 없음. 훅의 책임("세션 시작에 대시보드를 하루 1회 갱신한다")은 그대로고,
  같은 책임 안에서 그리는 장수만 1 → 2 가 된다. 책임이 둘로 갈라지지 않으므로 파일을 나누지 않는다.
- 시험: `tests/hermes-dashboard-test.sh` — 목표 1·2 단언 추가
- 룰: 없음
- 데이터: 없음 (마이그레이션 없음)
- 외부 의존: 없음

## 5. 단계 (Steps)

### Step 1. 시험 먼저 (RED) [단순]

- 입력: `tests/hermes-dashboard-test.sh` 의 "세션 시작 훅" 절
- 산출: 목표 1(공장 픽스처 → universe-dashboard.html 생성) · 목표 2(레지스트리 없음 → 미생성) 단언
- 검증: `bash tests/hermes-dashboard-test.sh` 가 **실패**한다

### Step 2. 훅 수정 (GREEN) [단순]

- 입력: Step 1 의 실패
- 산출: 훅이 `_render()` 로 소우주 한 장을 그리고, `$project_dir/.installed-projects` 가 있을 때만
  `--universe --factory "$project_dir"` 를 한 번 더 부른다
- 검증: `bash tests/hermes-dashboard-test.sh` 통과

### Step 3. 두 사본 동일 + 전체 시험 [단순]

- 산출: `diff -q scripts/hooks/... assets/hooks/...` 무출력
- 검증: `bash tests/run-all.sh` 통과

## 6. 의사결정 로그

- 2026-09-22: **(B) HTML 을 git 에 올리는 안 기각** — 근거: 대시보드는 그 컴퓨터 로컬 DB 의
  스냅샷이라 커밋하면 풀할 때마다 충돌한다. 틀렸을 때 손해: 다른 컴퓨터에서 풀해도
  대시보드가 안 보이는 상태가 남는다(대신 그 컴퓨터의 훅이 스스로 그린다).
- 2026-09-22: **마커를 하나로 공유** — 근거: 한 번의 실행이 두 장을 그리면 throttle 판정이
  하나로 끝난다. 마커를 나누면 경로 2개·판정 2벌이 생긴다(KISS).
  틀렸을 때 손해: 우주만 따로 더 자주 갱신하고 싶을 때 못 한다.
- 2026-09-22: **공장 판별은 `.installed-projects` 존재로** — 근거: 우주 CLI 가 실제로 읽는
  레지스트리 그 자체라 판별과 입력이 어긋날 수 없다. 틀렸을 때 손해: 레지스트리를 지운
  공장에서는 우주 대시보드가 안 그려진다(그릴 대상도 없으므로 무해).

## 7. 발견·예외

- **2026-09-22 — "뒤처짐" 판정이 사본의 최신 여부를 안 본다.** 우주 대시보드를 실제로
  만들어 보니 ai-create·wonil 이 "뒤처짐" 으로 나왔는데, 원인은 미설치가 아니라
  이 컴퓨터의 ai-create 사본이 origin/master 보다 10 커밋 뒤였던 것이다(전파는 다른
  컴퓨터에서 이미 끝나 있었다). `wonil` 은 git 저장소도 아니라 풀로 고칠 길조차 없다.
  → `docs/exec-plans/backlog/dashboard-sync-before-verdict.md` 로 흘려보냈다.
  이번 계획의 비목표(표 내용 변경)라 여기서 고치지 않는다.

## 8. 회고 (2026-09-22)

- 잘된 것:
  - **사람의 기대가 결함을 드러냈다.** "내가 항상 말해야만 생기는 거냐" 는 물음이 없었으면
    `--universe` 를 부르는 곳이 0 이라는 사실을 아무도 안 봤을 것이다. 우주 페이지는 이틀 묵어 있었다.
  - 시험 먼저(빨강 1건 확인) → 훅 수정 → 초록. 훅의 기존 성질 6개(rc 0·무출력·throttle·source 게이트·
    끄기 변수)를 건드리지 않았음을 같은 시험이 계속 지켰다.
  - 공장 판별을 `.installed-projects` **존재**로 한 것 — 우주 CLI 가 실제로 읽는 파일이라 판별과 입력이
    어긋날 수 없다. 별도 플래그를 뒀다면 둘이 갈라지는 날이 왔을 것이다.
- 잘못된 것:
  - **시험을 돌리는 도중에 파일을 두 번 바꿔 결과를 버렸다.** 한 번은 훅, 한 번은 `.installed-projects`
    (`copy-install-test.sh:170` 이 그 파일의 불변을 단언한다). 25분짜리 실행을 두 번 날렸다.
  - 배경 실행 뒤 턴을 끝내 사용자가 "아직도 돌리고 있어?" 를 묻게 했다 — `run-to-the-end` 가 경고하는 그대로다.
- 다음 룰 후보: **R-testrun-clean** — 전체 스위트가 도는 동안 저장소 파일을 바꾸면 PreToolUse 훅이
  경고한다(실행 중 표식 파일 + Edit/Write/Bash 쓰기 감지). 근거: 09-22 하루에 두 번.
