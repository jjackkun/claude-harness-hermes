# 2026-11-25-worktree-finish-open-docs — 계획서·기획서가 끝나지 않았으면 worktree 를 지우지 않는다

- 계기 프로젝트: jj-agent-room (2026-11-25 역할 레이블 계획 Step 3).
- 앞 계획: `docs/exec-plans/completed/2026-11-20-worktree-finish-plan.md` (worktree-finish 스킬 · Stop 훅 · 시작 알림).
- 순서: 계획 → planner-lite 리뷰(반영함, §7) → 구현(Step 1~3) → 복제본 실측 → 사용자 승인 뒤 전파(Step 4).

## 1. 동기 (Why)

2026-11-25 jj-agent-room 에서 에이전트가 계획서 Step 하나를 끝낸 뒤 `worktree-finish` 를 불렀다. 스크립트는 합치고 worktree 와 브랜치를 지웠다. 계획서 §2 에는 목표 7개가 아직 `[ ]` 였다. 에이전트는 다음 일(개발 서버 로그 확인)을 하려다 셸 폴더가 사라진 것을 알았다. 사용자는 "왜 자꾸 작업 중간에 워크트리를 지우냐" 고 크게 짜증냈다. 헤르메스 회상에 따르면 직전 세션(같은 계획 Step 2)도 같은 식으로 합치고 지웠다.

규칙과 스킬은 이렇게 적혀 있었다(값은 §2-bis).

1. **스킬 본문은 막으라고 적었다.** `SKILL.md` ①: "계획서의 §2 목표가 모두 확인됐는지 본다. 끝나지 않았으면 이 스킬을 쓰지 않는다." description 끝: "아직 일이 끝나지 않은 중간 커밋 … 에는 쓰지 않는다."
2. **그런데 발동 문구가 반대로 읽힌다.** description 은 "'끝났습니다' · '마무리' · '완료 보고' 를 쓰려는 자리에서 반드시 이 스킬을 쓴다" 고 한다. Step 하나의 완료 보고도 "완료 보고" 다. 전역 규칙 `git-workflow.md` 23줄도 "일을 끝내면" 이라고만 한다 — 무엇이 "일" 인지 없다.
3. **기계 검사가 없다.** `finish.sh` 의 멈춤 조건 14개(10~23)에 "계획서가 아직 열려 있다" 는 없다. 그래서 에이전트가 문장을 잘못 읽으면 그대로 지운다. 앞 계획의 Stop 훅(G2)은 계획서를 `completed/` 로 옮긴 경우만 본다 — 이번에는 옮기지 않았으므로 관여하지 않았다.

사용자 요구(2026-11-25): "문서 하나의 작업(기획서나 계획서)이 완료가 아직 안 되었는데 지우지 않게 해야 해."

## 2. 목표 (What — 검증 가능한 형태)

용어:
- **이 worktree 의 문서** = 이 브랜치가 main 과 비교해 더하거나 고친 문서, 그리고 커밋 안 된 변경이 있는 문서(`state_of` 의 `names` — diff + status). 대상은 셋이다.
  - `docs/exec-plans/active/YYYY-MM-DD-*.md` (진행 중 계획서)
  - 이 worktree 가 `completed/` 에 새로 만든 계획서(`_completed` 가 돌려주는 것과 같은 집합)
  - `docs/product-specs/*/prd.md` (기획서)
  - 다른 세션이 쓰는 문서는 이 worktree 가 건드리지 않았으면 세지 않는다. 날짜로 시작하지 않는 파일(`README.md` 등)은 계획서로 보지 않는다.
- **본문은 작업 트리에서 읽는다**(커밋 안 된 편집까지 본다). 작업 트리에 없는 경로(이 브랜치가 지운 문서, 이름을 바꾼 옛 경로)는 건너뛴다.
- **열린 문서** = 이 worktree 의 문서 가운데 아래 규칙표에 걸리는 것.

열린 문서 규칙표 — 줄마다 단위 시험 하나(G1):

| # | 규칙 | 시험 이름 |
|---|---|---|
| P1 | 계획서 §2 시작은 줄 맨 앞 `^## 2\.` 다. `## 2-bis` 는 시작이 아니라 끝 경계다 | `test_section_starts_at_h2_2_dot` |
| P2 | §2 끝은 다음 `^## `(해시 정확히 둘) 줄이다. `### G1` 같은 하위 제목에서는 끊지 않는다 — 그 아래 항목도 §2 다 | `test_h3_goals_inside_section` |
| P3 | 열린 항목은 `^\s*[-*+]\s+\[ \]` 다(들여쓴 항목 포함). 문장 속 인라인 코드 "`- [ ]`" 는 줄 맨 앞이 아니므로 세지 않는다 | `test_open_item_regex` · `test_inline_code_not_counted` |
| P4 | `[x]` · `[X]` 는 닫힌 항목이다 | `test_checked_variants` |
| P5 | 코드 펜스(```) 안의 `## ` · `- [ ]` 는 무시한다 | `test_fenced_lines_ignored` |
| P6 | §2 절을 못 찾으면(예: `## 2 목표`, `## 2) 목표`) 열린 문서로 본다 — 이유 `§2 절 없음` | `test_missing_section_is_open` |
| P7 | `completed/` 에 새로 생긴 계획서도 P1~P6 으로 본다 — `[ ]` 가 남았으면 열린 문서다(이유 `completed 인데 §2 미완료 N개`) | `test_completed_with_open_items` |
| P8 | (리뷰 반영) 펜스는 같은 글자로 길이 이상인 줄에서만 닫힌다. 백틱 뒷말에 백틱이 있으면(```x```) 펜스가 아니다. 파일 끝까지 닫히지 않으면 열림 — 이유 `코드 펜스가 닫히지 않음` | `test_fence_rules_from_review` |
| P9 | (리뷰 반영) 번호 목록(`1. [ ]`)도 항목이다. §2 에 체크 항목이 하나도 없으면 열림 — 이유 `§2 항목 없음` | `test_numbered_items_and_section_without_items` |
| D1 | 기획서 상태 줄은 `^\s*[-*]?\s*status:\s*` 뒤 첫 낱말이다(`contract.md:59-63` 의 머리는 `- status: draft \| approved` 불릿 줄이다). 대소문자는 무시하고 따옴표는 벗긴다 | `test_prd_status_bullet` |
| D2 | 상태가 `approved` 면 닫힘, 그 밖(`draft` · 줄 없음 · `draft \| approved` 그대로 · 모르는 값)은 열림이다 | `test_prd_status_open_values` |
| F1 | 작업 트리에 없는 경로는 건너뛴다 · 날짜로 시작하지 않는 `active/` 파일은 계획서가 아니다 | `test_deleted_and_non_plan_skipped` |

- [x] G1 열린 문서 판정은 순수 함수 하나다: (경로와 본문의 목록) → 열린 문서와 이유(`§2 미완료 7개` · `§2 절 없음` · `status: draft`). git 을 부르지 않는다. 위 표의 규칙을 줄마다 시험이 잰다.
      `.venv/bin/pytest -q tests/test_open_docs.py` — 표의 시험 이름 11개가 모두 있고 통과한다
- [x] G2 `finish.sh` 는 열린 문서가 있으면 **아무것도 바꾸지 않고** 새 멈춤 코드 24 로 끝난다: 커밋하지 않고, main 을 움직이지 않고, worktree · 브랜치를 그대로 두고, 잠금을 남기지 않는다. 출력에 열린 문서마다 경로와 이유를 한 줄씩 쓰고, 다음 할 일을 쓴다("계획이 끝날 때까지 worktree 에서 커밋만 하십시오. 사용자가 지금 main 에 넣으라고 했으면 `--keep-worktree` 로 다시 부르십시오").
      검사 순서는 지금의 ② → ① → ③ → ⑧(18) **다음**, 커밋(22 · 16) **앞**이다. 18 과 24 가 함께 걸리면 18 이 먼저다(잃는 파일이 더 급하다).
      `bash tests/worktree-finish-test.sh` — 새 경우: 열린 계획서 → 24 · main 끝 해시 그대로 · worktree 그대로 · 잠금 없음 / 열린 기획서 → 24 / 닫힌 계획서 · `approved` 기획서 → 평소대로 합침 / `completed` 로 옮겼는데 `[ ]` 남음 → 24 / 18 과 24 동시 → 18 / 커밋 안 된 변경 + `--message` 없음 + 열린 문서 → 24(22 가 아님)
- [x] G3 `--keep-worktree` 는 합치기까지만 한다: 커밋 → rebase → 메인 체크아웃에서 `--ff-only` → 사후 확인(23) → **`finish.sh:110-112`(셸 이동 · `worktree remove` · `branch -d`)를 건너뛴다.** 열린 문서가 있어도 이 플래그면 24 로 멈추지 않는다. 끝 줄은 `result: merged <브랜치> into main (<이전>..<이후>), kept <경로>` 다.
      `bash tests/worktree-finish-test.sh` — 새 경우: keep → 끝 줄에 `kept` 가 있고 `removed` 가 없다 · worktree · 브랜치 남음 / keep 직후 바로 한 번 더 keep → 종료 0(앞선 커밋 0, ff "already up to date") / keep 뒤 커밋 하나 더 → 문서를 닫고 keep 없이 → 합치고 지움
- [x] G4 스킬 문장이 Step 완료와 계획 완료를 가른다.
  - `SKILL.md` description(3줄): "완료 보고" 를 "계획서 §2 가 모두 끝난 뒤의 완료 보고" 로 좁히고, "Step 하나 · 단계 하나를 끝낸 보고에는 쓰지 않는다 — 그때는 worktree 에서 커밋만 한다" 를 넣는다.
  - 본문 ① · 흐름 6~8단계(keep 이면 건너뜀) · ③ 결과 읽기("작업 폴더가 사라졌다" 는 keep 이 아닐 때만) · 멈춤 표(`| 24 |`) · 검증 절의 단언 수를 고친다.
  - `finish.sh` 의 머리 주석(멈춤 코드 목록 · 사용법)과 usage 문자열(20줄)에 24 와 `--keep-worktree` 를 더한다.
      `sed -n 3p assets/skills/worktree-finish/SKILL.md | grep -c "Step 하나"` = 1 · `grep -c "^| 24 |" …/SKILL.md` = 1 · `grep -c "keep-worktree" …/SKILL.md …/scripts/finish.sh` 가 둘 다 1 이상
- [x] G5 전역 규칙 `assets/rules/common/git-workflow.md` 의 "앱이 만든 worktree 에서 일을 끝내면" 을 "그 worktree 의 계획서 §2 가 모두 끝나면" 으로 고치고, "끝나지 않은 계획서 · 기획서가 있으면 지우지 않는다 — 스크립트가 24 로 멈춘다. 사용자가 지금 main 에 넣으라고 하면 `--keep-worktree`" 한 줄을 더한다.
      `grep -c "24 로 멈춘다" assets/rules/common/git-workflow.md` = 1 · `python3 assets/hooks/doc_counts.py check README.md presets/workflow/harness.conf` 종료 0
- [x] G6 실제 모양에서 확인한다(앞 계획 회고의 룰 후보 — 전파 **전에** 설치 대상 저장소 복제본으로 돌린다).
  - 준비: jj-agent-room 을 임시 폴더에 `git clone` 한다. `bash ~/PROJECT/claude-harness-hermes/project-claude.sh <복제본> harness` 로 새 판을 설치한다(앞 계획 Step 3 과 같은 길). 앱과 같은 모양의 worktree 를 만든다(메인의 `settings.local.json` 사본 · `.env` 링크). 원본 jj-agent-room 은 건드리지 않는다.
  - 그 worktree 에서 열린 계획서(§2 `[ ]` 있음)를 고쳐 커밋한 뒤 아래 순서로 부른다. 기대값을 표로 고정한다.

    | # | 부르는 법 | 종료 코드 | `git worktree list` 줄 수 | main 끝 해시 |
    |---|---|---|---|---|
    | 1 | `finish.sh --message …`(커밋 안 된 변경 있음) | 24 | 2 | 그대로 · 커밋도 안 생김(게이트가 돌지 않았다) |
    | 2 | `finish.sh --keep-worktree --message …` | 0 | 2 | 브랜치 끝 |
    | 3 | §2 를 모두 `[x]` 로 · `completed/` 로 옮겨 커밋 → `finish.sh` | 0 | 1 | 브랜치 끝 |

      결과(종료 코드 · 줄 수 · 해시)를 §5 Step 4 에 적는다. 셋이 표와 같아야 통과다

## 2-bis. 착수 전 확인한 사실 (2026-11-25)

| 확인한 것 | 결과 |
| --------- | ---- |
| jj-agent-room 이 지운 시점의 계획서 §2 | `docs/exec-plans/active/2026-11-25-music-role-labels-plan.md` — `[x]` 6개 · `[ ]` 7개(G6 · G7 · G8 · G10 · G11 · G12 · G13). 계획서는 `active/` 에 그대로 |
| 그때 합친 범위 | `22a48e06..583a4e80` — 합치기는 맞게 됐다. 손해는 worktree · 셸 폴더가 사라진 것 |
| 스킬 본문의 "끝나지 않았으면 쓰지 않는다" | `assets/skills/worktree-finish/SKILL.md:22` (설치본과 diff 없음 — 제가 `diff` 로 확인) |
| 스킬 description 의 발동 문구 | 같은 파일 3줄 — "'끝났습니다' · '마무리' · '완료 보고' 를 쓰려는 자리 … 반드시 이 스킬을 쓴다" |
| 전역 규칙 문구 | `assets/rules/common/git-workflow.md:23` "앱이 만든 worktree 에서 일을 끝내면", 25줄 "worktree·브랜치 지우기" |
| `finish.sh` 멈춤 코드 | 10~23 (14개). 열린 문서 검사 없음. 110 `cd "$MAIN_DIR"` · 111 `git worktree remove` · 112 `git branch -q -d` · 114 `result:` 줄 |
| `finish.sh` 의 상태 읽기 | 36줄 `field` 가 `json.load(...)[키]` — 키가 없으면 트레이스백으로 죽는다(잠금 안) |
| Stop 훅이 "끝남" 으로 보는 것 | `assets/hooks/worktree_finish_guard.py` — 계획서를 `completed/` 로 옮겼을 때만. 이번 사고에는 관여하지 않았다 |
| 시작 알림이 띄우는 worktree | `assets/hooks/worktree_notice.py:34` `if state.ahead or state.changes` — 앞선 커밋도 변경도 없는 worktree 는 띄우지 않는다 |
| 기획서 머리 | `assets/skills/prd-writer/references/contract.md:59-63` — YAML 이 아니라 불릿 줄 `- status: draft \| approved` |
| `state_of` 가 이미 모으는 것 | `worktree_state.py:176-195` — `names`(diff + status), `touched_plans`(active 의 `.md`), `completed_plans`(`_completed`) |
| `tests/run-all.sh` 와 pytest | `run-all.sh` 에 `pytest` 줄 없음 — 앞 계획도 `.venv/bin/pytest -q tests/test_worktree_state.py` 를 따로 돌렸다 |
| 크기(고치기 전) | `worktree_state.py` 216줄 · `finish.sh` 114줄 · `SKILL.md` 83줄 · `tests/worktree-finish-test.sh` 135줄(앞 계획 기록 단언 62) |
| jj-agent-room `active/` | 날짜로 시작하는 계획서 15개, 그 밖의 파일 0개 |
| 이전 사고 | 헤르메스 회상: 같은 계획 Step 2 세션도 worktree 에서 합치고 지웠다. git 기록으로는 확인하지 않았다(worktree 는 남지 않는다) |

## 3. 비목표 (Out of Scope)

- 앱이 턴이 끝날 때 worktree 를 정리하는 동작 — 앱 설정이다(jj-agent-room 메모리 `worktree-never-end-turn-midwork`).
- Stop 훅(앞 계획 G2)과 시작 알림(G3)의 판정 — 그대로 둔다. 열린 문서가 있으면 Stop 훅은 원래 막지 않는다(completed 이동이 없으므로). P7 로 completed 에 `[ ]` 가 남은 경우 Stop 훅은 "합치라" 고 막고 `finish.sh` 는 24 로 멈춘다 — 메시지가 엇갈리지만 둘 다 사람에게 묻게 하므로 이번에는 고치지 않는다(§7 후보).
- `--keep-worktree` 로 남긴 worktree 의 시작 알림 — 앞선 커밋도 변경도 없으면 알림이 뜨지 않는다(`worktree_notice.py:34`). 계획서가 열려 있어 남긴 것이므로 알리지 않아도 된다.
- `idea-check` 의 `brief.md`, 설계 문서(`docs/design-docs/`)의 완료 판정 — 완료를 적는 칸이 없다. 필요해지면 따로 계획한다.
- 사람이 손으로 `git worktree remove` 하는 것 — 막지 않는다.
- 열린 문서를 무시하고 지우는 플래그 — 만들지 않는다. 지우려면 문서를 닫거나(§2 `[x]` · `approved`) 사람이 손으로 지운다.

## 4. 영향 영역

- 코드(고침):
  - `assets/skills/worktree-finish/scripts/finish.sh` — 24 검사(⑧ 다음 · 커밋 앞) · `--keep-worktree` 분기(110~112 건너뜀, 끝 줄 `kept`) · `field` 가 키 없음을 `stop 2 "worktree_state.py 가 낡았습니다 — 다시 설치하십시오"` 로 바꾼다 · 머리 주석 · usage
  - `assets/skills/worktree-finish/SKILL.md` — description · ① · 흐름 6~8 · ③ · 멈춤 표 · 검증 절(G4)
  - `assets/hooks/worktree_state.py` — `state_of` 가 `names` 와 `completed_plans` 에서 이 worktree 의 문서 경로를 골라 본문을 작업 트리에서 읽고 `open_docs.py` 에 넘겨 `open_docs` 칸을 낸다. `open_docs` 를 import 하지 못하면 `open_docs` 칸에 `["판정 모듈 없음"]` 을 넣는다(지우지 않는 쪽)
  - `assets/rules/common/git-workflow.md` — G5
  - `tests/worktree-finish-test.sh` — G2 · G3 의 새 경우
  - `presets/workflow/harness.conf` — `open_docs.py` 복사 한 줄(`worktree_state.py` 줄 옆)
  - README · 프리셋 숫자(판정 모듈 23 → 24, 새 pytest 파일 하나) — `doc_counts.py` 가 세는 곳. Step 1 에서 `doc_counts.py` 가 무엇을 세는지 먼저 읽는다
- **신규 파일 목록**:
  - `assets/hooks/open_docs.py` — 문서 경로와 본문을 받아 열린 문서와 이유를 돌려준다(순수 함수, git 을 부르지 않음, §2 규칙표 P1~P7 · D1~D2 · F1)
  - `tests/test_open_docs.py` — G1 단위 시험(규칙표의 시험 이름 11개)
- 룰: git-workflow 의 worktree 절.
- 데이터: 없음.
- 외부 의존: 없음.
- 되돌리기: 24 가 오탐으로 모든 마무리를 막으면 공장에서 이 계획의 커밋을 `git revert` 하고 `update-all.sh` 를 다시 돌린다. 급할 때는 막힌 문서를 사람이 닫거나 손으로 `git worktree remove` 한다(우회 플래그는 없다).

## 5. 단계 (Steps)

### Step 1. 열린 문서 판정 [Impl]
- 산출: `open_docs.py` · `test_open_docs.py` · `worktree_state.py` 의 `open_docs` 칸 · `harness.conf` 복사 줄
- 검증: G1. 판정에서 `## 2-bis` 경계를 빼면(§2 를 파일 끝까지 읽으면) P1 시험이 실패하는 것을 본다. P3 정규식을 줄 맨 앞 고정 없이 바꾸면 `test_inline_code_not_counted` 가 실패하는 것을 본다. `.venv/bin/pytest -q tests/test_worktree_state.py` 도 그대로 통과한다

### Step 2. finish.sh 멈춤 24 와 --keep-worktree [Impl → code-reviewer]
- 산출: G2 · G3 와 시험, `field` 의 키 없음 처리
- 검증: `bash tests/worktree-finish-test.sh` — 새 경우마다 종료 코드 · `git worktree list` · `git log main` 끝 해시 · 남은 잠금 없음. 24 검사를 커밋 뒤로 옮기면 "main 그대로 · 커밋 없음" 단언이 실패하는 것을 본다. git 을 쓰는 스크립트라 code-reviewer 를 부른다
- 시험은 `cd "$TMP"` 안에서만, git 폴더는 `--path-format=absolute` 로, `GIT_*` 위치 변수는 지운다(앞 계획 §7 사고)

### Step 3. 스킬 문장과 전역 규칙 [단순]
- 산출: G4 · G5
- 검증: G4 · G5 명령

### Step 4. 복제본 실측 → 전파 [사용자 승인]
- 산출: G6 표의 결과, 그 뒤 `update-all.sh`
- 검증: G6. 전파 전에 설치 대상 수를 보이고 승인을 받는다
- 결과(2026-11-25, 복제본 `jjclone` · 계획서 `2026-11-25-music-role-labels-plan.md`): 표와 같다.
  - 1행: 종료 24 · 줄 수 2 · main `2375b850` 그대로 · 브랜치 끝도 그대로(커밋 안 생김) · 잠금 없음. 출력 "§2 미완료 7개" — §2-bis 의 `[ ]` 7개와 같다.
  - 2행: 종료 0 · 줄 수 2 · main = 브랜치 끝 `2b1a86d0` · 끝 줄 `…, kept <경로>`.
  - 3행: 종료 0 · 줄 수 1 · main = 브랜치 끝 `718e08c4` · 끝 줄 `…, removed <경로>`.
  - 3행 첫 시도는 22 였다. 제가 `sed` 로 고친 뒤 `git add` 없이 `git mv` 해서 `[x]` 편집이 커밋 밖에 남았다. 스크립트는 맞게 멈췄다.
- 전파(`update-all.sh`): 아직 하지 않았다 — 사용자 승인 대기.

## 6. 의사결정 로그

- 2026-11-25: 열린 문서 판정은 이 worktree 가 건드린 문서만 본다 — 근거: `active/` 에는 다른 세션의 계획서가 늘 열려 있다(jj-agent-room 2026-11-25 기준 15개). 전부 세면 아무 worktree 도 지울 수 없다 — 손해: 계획서를 건드리지 않고 코드만 고친 worktree 는 이 검사에 걸리지 않는다(그 경우는 지금처럼 지운다).
- 2026-11-25: 열린 문서가 있으면 합치기도 하지 않고 멈춘다. 합치기만 원하면 `--keep-worktree` 를 따로 준다 — 근거: 이번 사고는 에이전트가 스스로 부른 것이다. 멈추면 에이전트가 사용자에게 묻게 된다. 합치기 자체는 다른 세션의 중복을 막으므로(앞 계획 §1) 길은 남긴다 — 손해: Step 마다 main 에 넣고 싶을 때 플래그 하나를 더 써야 한다.
- 2026-11-25: 열린 문서를 무시하고 지우는 플래그는 만들지 않는다 — 근거: 사용자 요구가 "지우지 않게" 이고, 우회 플래그를 쓰지 않는다는 앞 계획의 원칙과 같다 — 손해: 버리는 계획의 worktree 는 사람이 손으로 지우거나 계획서를 닫아야 한다.
- 2026-11-25: 못 읽는 경우는 모두 열림으로 본다 — §2 절 없음(P6) · 기획서 상태 줄 없음 · 모르는 값(D2) · 판정 모듈 없음 — 근거: 지우지 않으면 되돌릴 수 있고, 지우면 되돌릴 수 없다 — 손해: 템플릿을 따르지 않은 옛 문서를 건드린 worktree 는 24 로 멈춘다.
- 2026-11-25 (리뷰 H3): `completed/` 로 옮긴 계획서도 `[ ]` 가 남았으면 열린 문서로 본다(P7) — 근거: 옮기기만 하면 24 를 지나는 우회로가 된다. completed 는 완료 선언이므로 `[ ]` 가 남은 것은 모순이다 — 손해: 목표 하나를 일부러 남긴 채 닫으려면 그 항목을 `[x]` 로 바꾸고 이유를 적어야 한다.
- 2026-11-25 (코드 리뷰 MEDIUM): §2 에 체크 항목이 하나도 없으면 열림으로 본다(P9) — 근거: §6 "못 읽는 경우는 모두 열림" 과 같다 — 손해: 목표를 산문으로 쓴 계획서를 건드린 worktree 는 24 로 멈춘다. 실제 문서로 쟀다: 공장 계획서 119개 중 1개(`2026-11-20-worktree-finish-plan.md`), jj-agent-room 114개 중 1개.
- 2026-11-25 (코드 리뷰 LOW): 판정 모듈을 불러오다 어떤 예외가 나도 "판정 모듈 없음" 으로 본다 — 근거: 같은 모듈을 Stop 훅 · 시작 알림도 불러오므로 죽지 않아야 한다 — 손해: 모듈의 버그가 원인을 감추고 24 로만 보인다(문구에 "다시 설치" 를 넣었다).
- 2026-11-25 (리뷰 M3): 18(잃는 무시 파일)과 24 가 함께 걸리면 18 을 먼저 낸다 — 근거: 잃는 파일이 더 급하고, 지금 순서에서 18 이 이미 커밋 앞에 있다 — 손해: 18 을 푼 뒤 다시 부르면 24 가 나온다(두 번 부름).

## 7. 발견·예외
- 2026-11-25 code-reviewer(sonnet) 리뷰: WARNING — HIGH 2 · MEDIUM 2 · LOW 3. finish.sh 쪽 지적은 없었다.
  - HIGH 2(한 줄 코드 · 짝 안 맞는 펜스 · 닫히지 않은 펜스가 뒤의 `[ ]` 를 가려 열린 계획서를 닫힘으로 읽음): 제가 네 경우를 실행해 재현했다(모두 0). P8 로 고쳤다.
  - MEDIUM(번호 목록 · 항목 없는 §2): P9 로 고쳤다. NBSP 를 괄호 안에 넣은 `[ ]` 는 고치지 않았다 — 손으로 쓰는 문서에서 나오지 않는다.
  - MEDIUM(한글 · 공백 경로 시험): `test_open_docs_reads_korean_and_space_paths` 를 더했다.
  - LOW: 판정 모듈 없음 문구 · 넓은 예외(§6). completed 에 이미 있던 계획서를 고친 경우는 대상이 아니다 — §2 용어대로다.

- 2026-11-25 planner-lite 리뷰(sonnet, 인용 파일 10개 중 7개 전부 · 3개는 해당 줄만): NEEDS_WORK — HIGH 3 · MEDIUM 5 · LOW 3. 리뷰가 읽지 않은 두 곳(`worktree_notice.py:34` · `run-all.sh` 의 pytest)은 제가 읽었다. 11건 모두 맞아서 반영했다.
  - H1 기획서 머리는 불릿 줄 → D1 · D2. H2 §2 파싱 규칙 → 규칙표 P1~P6 과 시험 이름. H3 completed 우회로 → P7 · §6.
  - M1 지운 · 이름 바꾼 문서와 비계획서 → 용어 · F1. M2 낡은 `worktree_state.py` → §4 `field` 처리 · import 실패 처리. M3 검사 순서 → G2 · §6. M4 keep 뒤 일관성 → G3 시험 3개 · G4 의 usage · 주석 · ③. M5 G6 절차 → 설치 명령 · 기대값 표.
  - L1 · L2 검증 grep 을 새 문장 고유 구절로 · 3줄 지정으로. L3 단언 수 · 모듈 수 → G4 검증 절 · §4 숫자.
- 후보(이 계획 밖): Stop 훅도 P7 을 알아 "completed 인데 `[ ]` 남음" 이면 합치라고 막지 않고 그 사실을 알리는 쪽이 맞다.

## 8. 회고 (완료 시 작성)

- 잘된 것: 복제본 실측에서 실제 사고 계획서를 그대로 썼다. 판정이 "§2 미완료 7개" 로 §2-bis 의 사실과 맞았다. 변이 세 개(§2 경계 · 줄 맨 앞 고정 · 24 위치)를 시험이 모두 잡았다.
- 잘못된 것: 규칙표 P5 를 "펜스 안 무시" 한 줄로 적고 토글로 구현했다. 짝이 안 맞는 펜스가 뒤를 통째로 가리는 길을 계획 리뷰도 저도 보지 못했다. 코드 리뷰가 잡았다. 판정이 "닫힘" 쪽으로 틀리는 경로는 규칙표에 반례 시험을 같이 적어야 한다.
- 잘못된 것: G6 3행 첫 시도에서 `sed` 뒤 `git mv` 로 편집을 커밋 밖에 남겼다. 실측 절차 실수다.
- 다음 룰 후보: "안전 쪽 기본값(못 읽으면 열림)을 쓰는 판정은, 입력을 *가리는* 처리(펜스 · 주석 · 경계)마다 짝이 안 맞는 반례 시험을 둔다."
- 남은 일: 전파(`update-all.sh`)는 사용자 승인 뒤에 한다. Stop 훅의 P7 메시지 엇갈림(§3)은 backlog 후보다.
