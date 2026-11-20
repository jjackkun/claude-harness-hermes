# 2026-11-20-worktree-finish — worktree 세션을 끝내면 main 에 합치고 worktree 를 지운다

- 상태: Step 6 전파 끝 · G7 복제본 확인에서 결함 3개를 찾아 공장에서 고침(2026-11-20, 커밋 전). 남은 것: 고친 판 커밋·재전파 → 회고·completed 이동.
- 계기 프로젝트: jj-agent-room (2026-11-19~20 결재 작업).

## 1. 동기 (Why)

데스크톱 앱은 Code 세션마다 worktree 를 만든다. 세션이 일을 끝내도 그 브랜치가 main 에 합쳐지지 않고, worktree 도 남는다.
사용자는 이 일을 여러 번 지적했다. 그런데 지적이 강제 장치로 바뀐 적이 한 번도 없다.

2026-11-20 에 확인한 사실은 다음과 같다(값은 §2-bis).

1. **강제 장치가 없다.** "끝나면 로컬 main 에 `merge --ff-only`" 라는 규칙은 공장 프로젝트 메모리 `feedback-no-pr-solo.md` 한 곳에만 있다(2026-11-12).
   이 메모리는 공장 세션만 읽는다. 다른 프로젝트로 전파되지 않는다. worktree 를 지운다는 문장도 없다.
2. **학습 루프에 구멍이 있다.** 실수 감지 훅은 "워크트리 … 반영" 지적을 `worktree-not-synced` 로 센다.
   `hermes-increment.py` 는 count 만 올린다. 임계(3)를 넘으면 `CRYSTALLIZE:` 를 stderr 로 내지만, 훅이 이를 `2>/dev/null` 로 버린다.
   결정화는 세션 저장(`hermes_save_session_storage.py` 81줄 루프)이 그 세션 요약에서 뽑은 키에만 건다.
   그래서 jj-agent-room 에서 104번 쌓인 지적이 결정화 대상에 한 번도 오르지 않았다.
3. **전역 규칙이 빈칸을 남긴다.** 전역 `CLAUDE.md` 5번과 `git-workflow.md` 18줄은 "포그라운드 세션에서는 worktree 를 쓰지 않는다" 뿐이다. 앱이 만든 worktree 를 어떻게 끝내는지는 없다.
4. **실제 손해가 났다.** jj-agent-room 에서 아래 일이 일어났다.
   - 세션 A 가 결재 A1·A2 를 커밋하지 않은 채 멈췄다.
   - 세션 B 가 그 파일을 가져가 A1~A6 를 끝냈다.
   - 세션 A 는 그것을 모르고 A3 를 다시 만들었다. 이 중복 작업은 버렸다.
   - 같은 날 main 에 합쳐지지 않은 브랜치 3개와, 커밋하지 않은 계획서 변경 1개가 worktree 에 남아 있었다. 사용자가 지적한 뒤에야 합쳤다.

## 2. 목표 (What — 검증 가능한 형태)

### G1 마무리 스킬 `worktree-finish`

순서는 아래와 같다. 푸시는 하지 않는다.

1. 검사(아래 멈춤 조건)
2. 커밋(커밋 게이트를 거친다)
3. ff 직전의 main 해시를 기록한다
4. 로컬 main 위로 rebase 한다
5. 메인 체크아웃에서 `merge --ff-only` 로 합친다
6. 셸 위치를 메인 체크아웃으로 옮긴다
7. `worktree remove`(**`--force` 를 쓰지 않는다**)
8. `branch -d`(**`-D` 를 쓰지 않는다**)

멈춤 조건이 걸리면 이유를 한 줄로 보이고, 조건마다 다른 0 이 아닌 값으로 끝난다.

- ① 메인 체크아웃이 `main` 브랜치에 있지 않다. 판정: `git -C <main> symbolic-ref --short HEAD` 가 `main` 이 아니다.
- ② 이 worktree 가 detached HEAD 이거나, 이 브랜치가 `main` 자신이다.
- ③ 이 브랜치가 원격에 있다. 판정: upstream 이 설정됐거나 `git branch -r --contains` 가 비지 않았다. rebase 가 해시를 바꾸기 때문이다.
- ④ 메인 체크아웃에 커밋 안 된 변경이 있고, 그 파일이 합칠 파일과 겹친다.
- ⑤ rebase 가 충돌한다. 이때 `rebase --abort` 로 브랜치를 되돌린 뒤 멈춘다.
- ⑥ 커밋 게이트가 막는다.
- ⑦ rebase 와 ff 사이에 main 이 움직여 ff 가 실패한다. 4~5 를 한 번 다시 한다. 또 실패하면 멈춘다.
- ⑧ worktree 의 무시 파일 가운데 허용 목록 밖의 것이 있다. 허용 목록은 `node_modules/` · 설치된 `.claude/` 하위 · `.env` 심볼릭 링크 · `.harness/` · `.hermes/` 의 기록 파일이다. 판정은 `git status --ignored --porcelain` 으로 한다. 예: `server/uploads/`.
- ⑨ `worktree remove` 나 `branch -d` 가 거부된다. 우회 플래그를 쓰지 않고 멈춘다.
- ⑩ 같은 저장소에서 마무리가 이미 진행 중이다. 판정: `<git-common-dir>/worktree-finish.lock` 이 있다. 잠금은 끝날 때 지운다.

7(지우기)은 맨 마지막에 한 번만 한다. 그 전에 셸 위치를 메인 체크아웃으로 옮긴다. 지울 worktree 가 현재 셸 위치이면 이후 Bash 가 모두 실패하기 때문이다(2026-11-20 실측).

복구: 어느 단계에서 멈추든 main 은 3의 해시보다 뒤로 가지 않는다. 브랜치는 rebase 를 시작하기 전 상태이거나 이미 합쳐진 상태다. 멈춘 지점과 되돌리는 명령을 보고에 쓴다.

— 검증: `bash tests/worktree-finish-test.sh`. 임시 저장소에서 정상 1가지와 멈춤 ①~⑩ 각 1가지, 모두 11가지를 돌린다. 경우마다 확인하는 것은 아래와 같다.
  - 종료 코드
  - `git worktree list`
  - `git log main` 의 끝 해시(멈춤이면 3의 해시와 같다)
  - 남은 잠금 파일이 없는지

### G2 Stop 훅 — "끝났다고 해 놓고 main 에 안 합친 것" 을 한 번 막는다

- worktree 안 판정: `git rev-parse --git-dir` 와 `--git-common-dir` 가 다르다.
- "끝났다" 판정: 이 브랜치가 `docs/exec-plans/active/X` 를 `completed/X` 로 옮겼다. 두 군데를 함께 본다.
  - 커밋된 이동: `git diff --name-status --diff-filter=R main...HEAD`
  - 커밋 전 이동: `git status --porcelain` 에서 `active/X` 삭제와 `completed/X` 추가가 함께 있다.
- 막는 조건: "끝났다" 이면서, main 에 없는 커밋이 있거나 커밋 안 된 변경이 있다.
- 통과 조건은 아래 다섯이다.
  - `stop_hook_active` 가 참이다(재진입이다).
  - 세션 cwd 가 없다(마무리로 이미 지웠다).
  - worktree 가 아니다.
  - 이미 main 에 합쳐졌다(`main...HEAD` 가 비었다).
  - 같은 상태에서 이미 한 번 막았다. "같은 상태" 는 `HEAD 해시 + status 출력 해시` 다. 기록은 `<git-common-dir>/worktree-finish-guard/<session_id>` 에 둔다.
- 훅 메시지에 빠져나가는 법을 쓴다. "합치지 않을 이유가 있으면 그 이유를 사용자에게 말하고 끝내십시오. 같은 상태에서는 다시 막지 않습니다."
- 끄기: `WORKTREE_FINISH_GUARD_DISABLED=1`.

— 검증: `bash tests/worktree-finish-guard-test.sh`. 막음 2(커밋된 이동 · 커밋 전 이동), 통과 5(위 다섯)를 확인한다.

### G3 시작 알림

세션을 시작하면 main 에 안 들어간 worktree 목록을 한 번 알린다. 막지 않는다.
- 알리는 것: 브랜치, main 보다 앞선 커밋 수, 커밋 안 된 변경 수, 마지막 커밋 시각.
- 최대 10개까지 보이고, 나머지는 수만 보인다.
- 시간 상한은 5초다. 넘으면 알리지 않고, `.hermes/hooks.log` 에 한 줄 남긴다.
- 끄기: `WORKTREE_NOTICE_DISABLED=1`.

— 검증: `bash tests/worktree-unmerged-notice-test.sh`. 임시 저장소에 worktree 3개를 만든다. 합쳐짐 1, 안 합쳐짐 1, 변경만 있음 1 이다. 뒤의 2개만 나오는지 확인한다.

### G4 같은 계획서 편집 경고

같은 active 계획서를 다른 worktree 가 고치는 중이면, 편집 전에 경고한다.
- "고치는 중" 판정: 그 worktree 의 브랜치가 main 에 없는 커밋으로 그 파일을 건드렸거나, 커밋 안 된 변경이 있다.
- 동작 범위: Edit·Write 의 대상 경로가 `docs/exec-plans/active/` 아래일 때만 동작한다.
- 시간 상한은 2초다. 넘으면 통과한다.
- 경고는 막지 않는다. worktree 이름과 마지막 커밋 시각을 보인다.
- 끄기: `PLAN_OVERLAP_GUARD_DISABLED=1`.

— 검증: `bash tests/plan-overlap-guard-test.sh`. 겹침 1(경고), 안 겹침 1(조용함), active 밖 경로 1(조용함)을 확인한다.

### G5 실수 감지 키가 결정화 대상에 오른다

- 고칠 곳: `hermes_save_session_storage.py` 의 요약 키 루프 **밖**에 질의를 하나 더한다.
  `SELECT pattern_key FROM pattern_count WHERE count >= 3 AND crystallized = 0 AND pattern_key IN (<실수 감지 키 목록>)`
  결과를 `crystallize_targets` 에 덧붙인다. 실수 감지 키 목록은 `scripts/hermes_mistake_keys.py` 한 곳에 두고, 시험이 훅 안의 키와 같은지 대조한다.
- `hermes-increment.py` 의 `CRYSTALLIZE:` stderr 출력은 그대로 둔다. 아무 데도 닿지 않지만 지울 이유도 없다.
- `repeated-mistake` 는 목록에서 뺀다. "계속"·"반복" 한 단어로 걸리는 키라 규칙으로 만들 내용이 없다.

— 검증: `python3 -m pytest tests/test_hermes_increment_crystallize.py`. 아래 세 가지를 확인한다.
  - (a) 임시 DB 에서 `hermes-increment.py` 를 3번 부른 뒤, 세션 저장 함수의 **반환값**에 그 키가 있다.
  - (b) `repeated-mistake` 는 count 5 여도 반환값에 없다.
  - (c) 결정화된 뒤(`crystallized=1`)에는 다시 오르지 않는다.

### G6 규칙 문서

`assets/rules/common/git-workflow.md` 의 worktree 절을 아래처럼 나눈다.
- "**직접** `git worktree add` 하지 않는다(포그라운드)"
- "**앱이 만든** worktree 세션은 끝낼 때 `worktree-finish` 로 합치고 지운다. PR 은 열지 않는다. 푸시는 지시가 있을 때만 한다."

공장 메모리 `feedback-no-pr-solo.md` 는 이 규칙을 가리키도록 줄인다.

— 검증: 아래 둘을 확인한다.
  - `grep -n "worktree-finish" assets/rules/common/git-workflow.md` 가 1줄 이상이다.
  - `python3 assets/hooks/doc_counts.py check README.md presets/workflow/harness.conf` 가 0 으로 끝난다.

### G7 전파와 실제 확인

사용자 승인 뒤 프로젝트들에 설치한다. 확인은 셋이다.
- (a) 설치된 프로젝트의 `.claude/rules/common/git-workflow.md` 에 `worktree-finish` 가 있다.
- (b) jj-agent-room 에서 worktree 세션 하나를 이 스킬로 끝낸다. 그 뒤 `git worktree list` 에 그 worktree 가 없고, `git log main` 에 그 커밋이 있다.
- (c) 스킬을 부르지 않고 끝낸 worktree 하나가 있으면, 다음 세션 시작에 G3 알림이 나온다.

## 2-bis. 착수 전 확인한 사실 (2026-11-20)

| 확인한 것 | 결과 |
| --------- | ---- |
| 공장 저장소·전역 `~/.claude` 에서 "마무리 시 합치기·worktree 지우기" 훅·스킬 | 0개. 검색어 `worktree` · `ff-only` · `merge` · `메인에 반영` · `마무리` · `cleanup` |
| 공장 메모리 `feedback-no-pr-solo.md` | 있음(커밋 `fe087d1`). 공장 프로젝트 메모리에만 있다 |
| jj-agent-room `pattern_count` 의 `worktree-not-synced` | count 104 · crystallized 0 · last_seen 2026-11-20 02:30 |
| 공장 `pattern_count` 의 `worktree-not-synced` | count 7 · crystallized 0 |
| jj-agent-room `.hermes/hooks.log` 에서 `worktree-not-synced` 결정화 시도 줄 | 0줄(전체 28,684줄) |
| `hermes-increment.py` 67줄 | count ≥ 3 이면 `CRYSTALLIZE:` 를 stderr 로 낸다 |
| `claude-userpromptsubmit-mistake-detect.sh` 95줄 | `hermes-increment.py ... 2>/dev/null` — 위 출력을 버린다 |
| 같은 훅 85줄 | `repeated-mistake` 는 `자꾸·몇번째·또야·계속·반복·여러번` 중 한 단어로 걸린다 |
| `hermes_save_session_storage.py` 81줄 | `for key in patterns:` — 세션 요약 키만 돈다 |
| 훅 등록 위치 | `assets/hooks/claude-settings-hooks.json` 은 문서 전용(2줄 `_comment`). 실제 등록은 `presets/workflow/*.conf` 의 `STOP_HOOKS+=` 등을 `lib/generate_settings.py` 가 읽는다. 예: `presets/workflow/korean.conf` 26줄 |
| Stop 훅 본보기 | `assets/hooks/claude-stop-korean-guard.sh`(32줄). 판정은 py 모듈이 하고, 셸은 stdin·끄기·시간 상한(2초)만 맡는다. `stop_hook_active` 는 보지 않는다 |
| 2026-11-20 jj-agent-room 정리 전 worktree | 6개. 2개는 합쳐짐, 3개는 main 에 없는 커밋 1~2개, 1개는 커밋 안 된 계획서 변경 |
| 지울 worktree 가 현재 셸 위치일 때 | 2026-11-20 실측. 지운 뒤 다음 Bash 의 cwd 가 다른 곳으로 재설정됐다 |

## 3. 비목표 (Out of Scope)

- 원격 푸시와 PR. 사용자는 혼자 일하므로 PR 을 쓰지 않는다. 푸시는 따로 지시가 있을 때만 한다.
- 앱이 worktree 를 만드는 방식은 바꾸지 않는다(앱 설정이다).
- 오래된 worktree 를 자동으로 지우지 않는다. G3 는 알리기만 한다.
- 남의 세션의 커밋 안 된 변경을 옮기거나 합치지 않는다. G1 은 자기 worktree 만 다룬다.
- 원격에 이미 있는 브랜치의 마무리. G1 ③ 에서 멈추고 사람에게 넘긴다.

## 4. 영향 영역

- 코드(고침):
  - `presets/workflow/harness.conf` — 새 훅 3개 등록(`STOP_HOOKS+=` · SessionStart · PreToolUse 배열)
  - `lib/generate_settings.py` — 새 배열 종류가 필요하면 손댄다
  - `assets/hooks/claude-settings-hooks.json` — 문서 표에 3줄 추가
  - `presets/workflow/hermes.conf` — 복사 목록에 `hermes_mistake_keys.py` 한 줄(훅은 고치지 않았다 — 시험이 둘을 대조한다)
  - `scripts/hermes_save_session_storage.py` — G5 질의
  - `assets/rules/common/git-workflow.md` — G6
  - `assets/hooks/doc_counts.py` 가 세는 문서 숫자
- **신규 파일 목록**:
  - `assets/skills/worktree-finish/SKILL.md` — 마무리 순서와 멈춤 조건을 사람 말로 적는다
  - `assets/skills/worktree-finish/scripts/finish.sh` — 마무리 순서를 기계로 실행하고, 멈춤 조건마다 다른 종료 코드를 낸다
  - `assets/hooks/worktree_state.py` — 한 worktree 의 상태를 계산한다(main 보다 앞선 커밋, 변경 수, 건드린 active 계획서, completed 이동 여부, 허용 목록 밖 무시 파일)
  - `assets/hooks/claude-stop-worktree-finish-guard.sh` — G2 Stop 훅의 셸(stdin·끄기·시간 상한)
  - `assets/hooks/worktree_finish_guard.py` — G2 판정(막음/통과 다섯 조건, 한 번만 기록)
  - `assets/hooks/claude-sessionstart-unmerged-worktrees.sh` — G3 시작 알림의 셸(stdin·끄기·시간 상한)
  - `assets/hooks/worktree_notice.py` — G3 판정(main 에 안 들어간 worktree 고르기·10개까지 문장으로)
  - `assets/hooks/claude-pretooluse-plan-overlap-guard.sh` — G4 같은 계획서 편집 경고의 셸
  - `assets/hooks/plan_overlap.py` — G4 판정(같은 active 계획서를 고치는 다른 worktree 찾기)
  - `scripts/hermes_mistake_keys.py` — 실수 감지 키와 결정화 제외 키(`repeated-mistake`)의 한 목록(hermes 프리셋이 깐다)
  - `tests/worktree-finish-test.sh` — G1
  - `tests/worktree-finish-guard-test.sh` — G2
  - `tests/worktree-unmerged-notice-test.sh` — G3
  - `tests/plan-overlap-guard-test.sh` — G4
  - `tests/test_hermes_increment_crystallize.py` — G5
  - `tests/test_worktree_state.py` — Step 1 상태 판정의 단위 시험(임시 git 저장소)
  - `tests/worktree-hooks-lib.bash` — G2·G3·G4 시험이 함께 쓰는 임시 저장소 도우미(`.bash` 라서 시험 수에 세지 않는다)
- 룰: git-workflow 의 worktree 절. 결정화 경로(헤르메스 C 계열).
- 데이터: 없음. `pattern_count` 표는 그대로 두고 고르는 질의만 더한다.
- 외부 의존: git 2.38 이상(`worktree list --porcelain`)과 python3. 둘 다 이미 쓰고 있다.

## 5. 단계 (Steps)

모든 단계는 끝난 뒤에도 공장이 동작하는 상태로 남는다. 새 훅은 Step 3 에서 등록하기 전까지 아무 데서도 불리지 않는다.

### Step 1. 상태 판정 모듈 [Impl] — 끝(2026-11-20)
- 산출: `worktree_state.py` 와 그 단위 시험. G1~G4 가 함께 쓴다.
- 검증: 임시 저장소 시험이 통과한다.
- 결과: `.venv/bin/pytest -q tests/test_worktree_state.py` → 13 passed. 결함 4가지(`--no-renames` 빼기 · `--ignored=matching` → `--ignored` · `.env` 링크 판정 빼기 · `--untracked-files=normal`)를 하나씩 넣었더니 매번 1개씩 실패했다. 원본으로 되돌린 뒤 13 passed. 공개 이름은 6개다.

### Step 2. 마무리 스킬 [Plan/Impl/Review] — 끝(2026-11-20)
- 산출: `worktree-finish` 스킬과 `finish.sh`. 멈춤 조건 ①~⑩. 리뷰 뒤 21(main 은 그대로인데 ff 거부) · 23(합친 뒤 확인 불일치)을 더했다.
- 검증: G1. git 을 쓰는 스크립트라 데이터 손실 위험이 있으므로 code-reviewer 리뷰를 받는다.
- 결과: `bash tests/worktree-finish-test.sh` → 62 통과 · 0 실패. `.venv/bin/pytest -q tests/test_worktree_state.py` → 15 passed.
  - 결함 8가지를 넣었을 때 시험이 모두 잡았다(처음 1가지는 못 잡아서 단언을 더했다).
  - code-reviewer(opus) 판정은 BLOCK 이었다. HIGH 2 · MEDIUM 3 · LOW 3, 파일 6/6 을 읽었다(coverage 1.0). 지적은 모두 반영했다(LOW 3 의 부분 스테이징 손실은 받아들이고 SKILL.md 에 적었다).
  - 고치기 전 동작 3가지(ff 직전 재확인 없음 · 짧은 이름 · `-z` 없음)를 다시 넣었을 때 새 시험이 각각 4 · 2 · 1 실패로 잡았다.

### Step 3. 훅 3개와 등록 [Impl] — 끝(2026-11-20)
- 산출: G2 · G3 · G4 훅과 `presets/workflow/harness.conf` 등록.
- 검증: G2 · G3 · G4 시험. 공장 자기 설치 뒤 `.claude/settings.json` 에 세 훅이 있는지 본다.
- 결과: `worktree-finish-guard-test.sh` 32 · `worktree-unmerged-notice-test.sh` 18 · `plan-overlap-guard-test.sh` 11 — 모두 통과(리뷰 반영 뒤).
  - code-reviewer(sonnet) 판정 WARNING: CRITICAL 0 · HIGH 1 · MEDIUM 4 · LOW 3. H1·M1~M4·L1·L3 을 반영했다. 반영한 동작 5가지를 되돌리면 시험이 각각 1개씩 실패한다(실측).
  - 공장 자기 설치 대신 **임시 프로젝트에 `project-claude.sh <임시> harness` 로 설치**해 확인했다. `settings.json` 에 세 훅이 있고, Stop 칸에 G2 가 있고, 모듈 4개와 `finish.sh` 가 복사됐다(공장 자신의 `.claude/settings.json` 은 건드리지 않았다).
  - 결함 9가지를 넣었을 때 시험이 모두 잡았다(처음 1가지는 못 잡아 시험을 보강했다).
  - `run-all.sh` 에 시험 4개를 등재했고, README·프리셋 숫자를 고쳤다(훅 18→21 · 모듈 19→23 · 스킬 13→14 · 시험 161→165). `doc_counts.py check` 종료 0.
  - 상태 모듈의 남은 짧은 브랜치 이름 2곳도 `refs/heads/` 로 바꿨다(Step 2 리뷰 H2 와 같은 이유).

### Step 4. 결정화 구멍 [Impl] — 끝(2026-11-20)
- 산출: G5.
- 결과: `.venv/bin/pytest -q tests/test_hermes_increment_crystallize.py` → 9 passed. 결함 3가지(질의 빼기 · 제외 목록 빼기 · 중복 허용)를 넣었을 때 각각 1 실패.
  - jj-agent-room `.hermes/state.db` 를 **복사본**으로 돌렸다(원본은 읽기 전용으로만 열었다). 고른 대상은 `worktree-not-synced`(107) · `css-property-missing`(14) 두 개, `repeated-mistake`(103)는 빠졌다.
  - 다음 세션 끝에서 이 두 키가 결정화(haiku 호출)에 한 번씩 들어간다. 판정(1 또는 -1)이 나면 다시 오르지 않는다. 실제 결정화 결과는 아직 보지 않았다.
- 검증: G5 시험. 그 뒤 jj-agent-room 에서 실제로 확인한다. 세션 하나를 끝낸 뒤 `worktree-not-synced` 의 crystallized 값이 0 에서 1 또는 -1 로 바뀌었는지 본다(한 번 판정됐다는 뜻).

### Step 5. 규칙 문서와 메모리 [단순] — 끝(2026-11-20)
- 산출: G6. 스킬이 생긴 뒤에 규칙이 그 스킬을 가리켜야 하므로 Step 2 뒤에 한다.
- 결과: `assets/rules/common/git-workflow.md` 의 worktree 줄을 "직접 만들지 않는다" 로 고치고, 「worktree 세션 마무리」 절(4줄 + 이유)을 더했다. `grep -n worktree-finish` → 25줄. `doc_counts.py check` 종료 0. 옛 문구에 기대는 시험·코드는 없었다(grep).
  - 공장 메모리 `feedback-no-pr-solo.md` 두 벌(공장 저장소 `.claude/memory/` · `~/.claude/projects/…/memory/`)에 "규칙으로 옮김" 단락을 더했다. 두 벌은 같다(diff).
  - 전역 `~/.claude/rules/common/git-workflow.md` 는 공장 HEAD 판과 같다 — Step 6 전파 때 함께 바뀌는지 확인한다.

### Step 6. 전파 [사용자 승인] — 끝(2026-11-20, 사용자 "커밋 후 전파")
- 산출: G7. 설치 대상 프로젝트 수와 바뀌는 훅 수를 보이고 승인을 받는다.
- 결과:
  - 공장 커밋 `a45d291` 푸시. 게이트가 두 번 막았다 — ① R-test: 게이트가 넘긴 `GIT_*` 위치 변수로 test_worktree_state 15 errors → `worktree_state._git`·시험이 그 변수를 지우게 고침. ② R-cx 4건 → 함수 나눔(최대 11). 남은 경고: R-dep-4(새 모듈 5개에 `.deprc` tier 없음) · R-eval.
  - `update-all.sh` → 성공 4 · 실패 0. 4곳 모두 `settings.json` 에 훅 3개 · `worktree-finish` 스킬 있음. 전역 `~/.claude/rules/common/git-workflow.md` 에 `worktree-finish` 2줄(G7 a). 프로젝트 안에는 공통 규칙 사본이 없다(전역 하나를 쓴다).
  - 설치물 커밋: 공장 `3770e41`(푸시) · apt-curtain `4384989`(원격 추적 브랜치 없음 — 푸시 안 함, 브랜치 `design/result-screen-trial`) · drh-cloth-shop `afb0a3e`(푸시) · jj-agent-room `835cdb5e`(푸시, 앞서 합친 커밋 5개 포함 6개).
  - drh-cloth-shop · jj-agent-room 은 R-privacy 가 막았다 — 「올리기 전 확인」 안 된 결정화 스킬 4개. 판정은 사용자 몫이라 스테이징에서만 빼고 작업 트리에 남겼다.
  - G5 실측: 설치 뒤 jj-agent-room 세션 끝에서 `worktree-not-synced` · `css-property-missing` 이 crystallized 0→1 (hooks.log 28907~28909). 스킬 3개 생김: `sync-worktree-to-main-checkout.md` · `copy-worktree-edits-to-main.md`(키 worktree-not-synced) · `flex-parent-display-required.md`. 모두 확인 대기(커밋 안 됨).
- 남은 G7: (b) 실제 worktree 세션 하나를 `worktree-finish` 로 끝내기 · (c) 스킬 없이 끝낸 worktree 가 다음 시작에 알림으로 나오는지.
- G7 확인(2026-11-20, 사용자 "확인해봐"): 남의 세션 worktree 는 건드리지 않고, jj-agent-room 을 임시 폴더에 복제해 앱과 같은 모양의 worktree(메인의 `settings.local.json` 사본 · `.env` 링크)를 만들고 계획서를 가지에서 쓰고 completed 로 옮겨 커밋 2개를 쌓았다.
  - 설치본으로 돌린 결과 — G3 알림: 나옴. **G2 Stop: 침묵(결함 ①).** **G1: `bash .claude/skills/worktree-finish/scripts/finish.sh` → 파일 없음(결함 ③).** 실제 jj worktree 3곳의 `.claude/settings.local.json` 이 "잃는 파일" 로 잡혀 G1 은 늘 멈춤 18 이었을 것(결함 ②).
  - 결함 ① 가지에서 태어나 끝난 계획서는 main 의 active/ 에 없어 "active 에서 지워짐" 조건을 못 채웠다 → 완료 = main 과 비교해 completed/ 에 새로 생긴 계획서.
  - 결함 ② 앱이 메인의 `settings.local.json` 을 worktree 로 복사한다(바이트 같음, 실측) → 메인과 같으면 잃지 않는 파일로 본다.
  - 결함 ③ jj 는 `.claude/skills/*` 를 git 이 무시해 worktree 에 스킬 파일이 없다 → SKILL.md·Stop 메시지가 상대 경로 대신 스킬 기준 폴더를 쓴다.
  - 고친 판으로 같은 복제본 재실행: G2 block · G3 `claude/g7-test · 커밋 2` · G1 `result: merged … (52a13cfc..bcd1639d)` 종료 0, worktree 0 · 브랜치 0, 합친 뒤 G3 빈 출력. 시험: pytest 27 · finish 62 · guard 34 · notice 18 · overlap 11 — 모두 통과. 결함 재현 시험 3개(고치기 전 2 실패 확인).
  - 실제 앱 세션(사람이 띄운 worktree 세션)에서의 확인은 아직이다.

## 6. 의사결정 로그

- 2026-11-20: 합치기는 로컬 main 에 `--ff-only` 로 하고, 그 전에 rebase 한다 — 근거: 메모리 `feedback-no-pr-solo`, 2026-11-20 jj-agent-room 에서 실제로 쓴 방법 — 손해: rebase 는 브랜치 해시를 바꾼다. 그래서 원격에 있는 브랜치는 G1 ③ 에서 멈춘다(리뷰 반영으로 확정).
- 2026-11-20: Stop 훅은 "계획서를 completed 로 옮겼는데 main 에 없음" 일 때만 막는다 — 근거: 진행 중 세션은 턴마다 Stop 이 오므로 매번 막으면 일이 끊긴다. 계획서 완료가 "끝났다" 의 가장 분명한 신호다 — 손해: 계획서 없이 끝낸 작은 작업은 G2 에 걸리지 않는다. 그 경우는 G3 가 다음 세션 시작에 알린다.
- 2026-11-20: 오래된 worktree 를 자동으로 지우지 않는다 — 근거: 남은 worktree 에는 다른 세션의 커밋 안 된 변경이 있을 수 있다(메모리 `cleanup-only-this-session`) — 손해: 사람이 G3 목록을 보고 직접 정해야 한다.
- 2026-11-20 리뷰 반영: G5 는 증가 스크립트가 아니라 세션 저장 쪽 질의를 고친다 — 근거: `CRYSTALLIZE:` stderr 는 훅이 버리고, 저장 루프는 요약 키만 돈다(§2-bis) — 손해: 실수 감지 키는 세션이 끝날 때에야 결정화된다. 즉시 결정화되지 않는다.
- 2026-11-20 리뷰 반영: `repeated-mistake` 는 결정화하지 않는다 — 근거: 한 단어로 걸리는 키라 규칙으로 만들 내용이 없다 — 손해: 정말 반복된 실수가 이 키로만 잡혔다면 규칙이 되지 않는다. 그런 실수는 대개 다른 키에도 걸린다.
- 2026-11-20 리뷰 반영: `worktree remove --force` 와 `branch -D` 를 쓰지 않는다 — 근거: 우회하면 무시 파일·안 합친 커밋을 잃는다 — 손해: 멈춤이 늘어 사람이 손대는 일이 생긴다. 2026-11-20 수동 정리 때는 --force 를 썼다. 그때는 사람이 미리 대조했다.

- 2026-11-20 Step 1: 무시 파일 허용 목록에 `.hermes/` 전체와 캐시 폴더(`__pycache__` · `.pytest_cache` · `.ruff_cache` · `.mypy_cache`)를 넣었다 — 근거: 모두 다시 만들어지거나 세션 기록이다 — 손해: worktree 에만 있던 `.hermes/state.db` 기록은 지울 때 함께 사라진다.
- 2026-11-20 Step 1: 무시 파일은 `git status --ignored=matching` 으로 읽는다 — 근거: 기본(traditional)은 `server/uploads/` 를 바깥 폴더 `server/` 로 뭉개서 허용 판정이 틀린다(실측) — 손해: 없음.
- 2026-11-20 Step 1: 계획서 완료 판정은 이름 바꾸기 감지에 기대지 않고 지움+추가 쌍으로 본다(`--no-renames`) — 근거: 많이 고친 뒤 옮기면 rename 으로 잡히지 않는다(시험) — 손해: 같은 이름의 다른 계획서를 지우고 새로 만든 경우도 "완료" 로 읽는다.

- 2026-11-20 Step 2: 브랜치 이름은 전체 이름(`refs/heads/…`)으로 쓰고, ff 뒤 `main == 브랜치 끝` 일 때만 지운다 — 근거: 리뷰 H1·H2 재현(같은 이름 태그를 합치거나, 도중에 바뀐 다른 브랜치에 합치고 "합침" 으로 끝냈다) — 손해: 없음.
- 2026-11-20 Step 2: 시험용 환경변수 틈(`WORKTREE_FINISH_TEST_BEFORE_FF`)을 없애고 시험이 `post-rewrite` 훅으로 재현한다 — 근거: 실제 실행에서도 그 값을 셸로 돌렸다(리뷰 LOW) — 손해: 시험이 git 훅 동작에 기댄다.
- 2026-11-20 Step 2: `.claude/settings.local.json` 은 허용 폴더 안이어도 지우면 잃는 파일로 본다 — 근거: 그 세션에서 승인한 권한이다(리뷰 M3) — 손해: 이 파일이 있는 worktree 는 사람이 옮겨야 마무리된다.
- 2026-11-20 Step 2: 게이트가 커밋을 막으면 스테이징을 모두 푼다 — 근거: 반쯤 스테이징된 상태로 남기는 것보다 단순하다 — 손해: 사용자가 일부만 스테이징해 둔 구분이 사라진다(파일 내용은 그대로).

- 2026-11-20 Step 3: 시험의 공용 도우미는 `.bash` 확장자로 둔다 — 근거: `doc_counts.py` 가 `tests/*.sh` 를 모두 시험으로 센다 — 손해: 다른 시험 도우미와 확장자가 다르다.
- 2026-11-20 Step 3: G3 은 메인 체크아웃을 세지 않는다 — 근거: 메인의 커밋 안 된 변경은 평소 작업이다 — 손해: 메인에 오래 방치된 변경은 알리지 않는다.
- 2026-11-20 Step 3: 설치 확인은 공장 자기 설치 대신 임시 프로젝트 설치로 했다 — 근거: 자기 설치는 공장의 `.claude/settings.json` 과 `scripts/hooks/` 를 바꾼다(사용자 요청 없는 설정 변경) — 손해: 공장 자신에는 아직 새 훅이 깔리지 않았다. Step 6 전파 때 함께 깐다.

- 2026-11-20 Step 3 리뷰: 세 훅은 `.hermes/` 를 만들어서라도 오류·시간 초과를 `.hermes/hooks.log` 에 남긴다(H1). harness 프리셋이 `.hermes/hooks.log` 를 `.gitignore` 에 넣는다 — 근거: worktree 에는 `.hermes/` 가 없어 오류가 사라졌다 — 손해: 프리셋을 다시 깔지 않은 프로젝트에서는 이 로그가 추적 안 된 파일로 보이고, `finish.sh` 의 `git add -A` 가 커밋에 넣을 수 있다. 훅과 무시 줄은 같은 프리셋으로 함께 깔리므로 실제로는 같이 들어간다.
- 2026-11-20 Step 3 리뷰: Stop 훅은 세션마다 "완료 계획서 묶음" 당 한 번만 막는다(M2) — 근거: HEAD+status 를 키로 쓰면 커밋할 때마다 다시 막는다 — 손해: 같은 계획서로 일을 더 해도 다시 알리지 않는다. 다음 세션 시작에 G3 이 알린다.
- 2026-11-20 Step 3 리뷰: main 과 내용이 같으면 합친 것으로 본다(M3) — 근거: squash 로 합치면 조상 관계가 없다 — 손해: main 이 그 뒤로 움직였으면 squash 로 합쳤어도 막는다. 안내 문구에 PR 경로를 한 줄 넣었다.
- 2026-11-20 Step 3 리뷰: main 이름은 `WORKTREE_MAIN_BRANCH` → `origin/HEAD` → main → master 순으로 찾는다(M4) — 손해: 둘 다 아닌 이름(trunk 등)은 판정 실패로 통과하고 로그에만 남는다.
- 2026-11-20 Step 3 리뷰: 시작 알림은 startup·resume 에서만 띄운다(L1). 7일 지난 Stop 기록은 쓸 때 지운다(L3). 편집 경고가 같은 파일 편집마다 다시 뜨는 것(L2)은 받아들인다 — 손해: 겹치는 동안 같은 경고가 반복된다.

- 2026-11-20 Step 4: 대상은 실수 감지 키 목록으로 고른다. "어느 세션에도 기록되지 않은 키" 로 고르지 않는다 — 근거: 그 방식은 jj-agent-room 11개 · 공장 31개를 골랐고, 대부분 `agent-message` · `clear` 같은 쓰레기 키였다(복사본 실측). 결정화마다 모델을 부르므로 비용이 든다 — 손해: 새 실수 감지 키를 훅에 더할 때 목록도 고쳐야 한다(시험이 어긋남을 잡는다).
- 2026-11-20 Step 4: 결정화가 실패(SKIP)하면 다음 세션 끝에서 다시 시도한다 — 근거: 요약 키와 같은 동작이다 — 손해: claude CLI 가 없는 환경에서는 세션마다 시도 기록만 남는다.

- 2026-11-20 Step 5: 메모리는 줄이지 않고 "규칙으로 옮김" 단락만 더했다 — 근거: 사용자의 원래 말(Why)과 겹침 확인 방법(How)은 규칙보다 자세하다 — 손해: 같은 내용이 메모리와 규칙 두 곳에 있다. 다르게 고쳐지면 규칙이 우선이다.
- 2026-11-20 Step 5: 규칙의 근거 줄은 `active/` 경로를 가리킨다. 계획을 끝낼 때 `completed/` 로 바꾼다(헤르메스 규칙 finalize-completed-exec-plan).

## 7. 발견·예외
- 2026-11-20 Step 2 사고: 첫 시험이 상대 경로 `git rev-parse --git-common-dir`(`.git`)를 써서 **공장 저장소의 `.git/hooks/pre-commit` 을 "항상 실패" 훅으로 덮었고, `.git/worktree-finish.lock` 을 만들었다.** `assets/hooks/pre-commit.sh` 를 복사해 되살렸다(sha256 `f855a9c5…` = 설치 장부 값). 잠금 폴더는 지웠다. 시험은 이제 `cd "$TMP"` 안에서만 돌고 모든 git 폴더를 `--path-format=absolute` 로 받는다. 다른 공장 시험에도 같은 위험이 있는지는 보지 않았다 — backlog 후보.

- 2026-11-20 jj-agent-room 정리 중: 합친 worktree 하나(`wonderful-engelbart`)에 통합 시험이 남긴 `server/uploads/help/` 파일 163개(668KB)가 있었다. 이것이 G1 멈춤 조건 ⑧ 의 근거다.
- 2026-11-20: 결정화 구멍(G5)은 worktree 키만의 문제가 아니다. 실수 감지 훅이 세는 모든 키(`css-property-missing` 등)가 같은 경로를 탄다.
- 2026-11-20 리뷰: 본보기 Stop 훅(korean-guard)은 `stop_hook_active` 를 보지 않는다. G2 는 이 필드를 본다. korean-guard 도 같은 보강이 필요한지는 이 계획 밖이다. backlog 후보다.

- 2026-11-20 Step 3: `tests/harness-hooks-smoke.sh` 가 "CLAUDE.md <= 100 줄" 에서 실패한다. 이 계획 전부터 102줄이었다(스킬 등록을 빼고 돌려 확인). `worktree-finish` 스킬 한 줄로 103줄이 됐다. 공장의 CLAUDE.md 생성 분량 문제라 이 계획 밖이다 — backlog 후보.

- 2026-11-20 Step 6: `worktree-not-synced` 결정화가 스킬 2개를 만들었다. 그중 `copy-worktree-edits-to-main.md` 는 "worktree 파일을 `cp -r` 로 메인에 복사" 라고 적어 `worktree-finish`(rebase → ff)와 어긋난다. 결정화 프롬프트가 기존 스킬·규칙과 충돌하는지 보지 않는다 — backlog 후보. 이 파일은 확인 대기라 아직 어디에도 올라가지 않았다.
- 2026-11-20 Step 6: apt-curtain 은 기능 브랜치(`design/result-screen-trial`)에 설치물이 커밋됐다. 원격 추적 브랜치가 없어 푸시하지 않았다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
