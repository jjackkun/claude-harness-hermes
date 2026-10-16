# 2026-10-16-redact-llm-input-gaps — LLM 으로 나가는 사람 입력 6곳에 가림을 건다

## 1. 동기 (Why)

2026-10-16 OmniRoute 검토 중 LLM 호출 경로를 전수 조사했다. summarize·persona 는 LLM 에 보내기 전
`hermes_redact.redact()` 를 거치지만, 아래 6곳은 사람이 친 원문(또는 가려지지 않은 저장값)을
그대로 `claude -p` 프롬프트에 싣는다. 사용자 원칙 "저장·전송 전에 가린다" 와 어긋난다.

| # | 경로 | 원문이 들어오는 자리 |
|---|------|------------------|
| 1 | `scripts/hermes_search_fallback.py` `haiku_fallback` | 검색 질의 `query` |
| 2 | `scripts/hermes-evolve-skill.py` `generate_evolved_content` | `--feedback` |
| 3 | `scripts/hermes-summon.py` `cmd_run` | `--task` (프롬프트·`HERMES_TASK_HINT`) |
| 4 | `scripts/hermes-manager.py` `format_unread` (cron 경로) | `messages.content` — `hermes-message.py send` 가 가리지 않고 저장 |
| 5 | `scripts/hermes_loop_prompt.py` `build_iteration_prompt` | goal.md 를 사람이 직접 고친 목표·조건·로그 |
| 6 | `scripts/hermes_mesh_gate.py` `stage2_is_general` | 스킬 본문 (통과 뒤에만 가렸음) |

## 2. 목표 (What — 검증 가능한 형태)

- [x] 6곳 모두 LLM 에 넘어간 프롬프트에 형태 기반 비밀(GitHub 토큰·이메일)이 남지 않는다 — 검증: 가짜 `claude` 로 stdin 을 받아 대조하는 `tests/hermes-redact-llm-input-test.sh`
- [x] 경로(프로젝트 디렉터리·goal.md 경로)는 깨지지 않는다 — 검증: 같은 시험에서 loop 프롬프트에 `project_dir` 원문이 남는지 확인
- [x] 기존 마스킹 시험이 그대로 통과한다 — 검증: `tests/hermes-redact*-test.sh`, loop·summon·mesh 관련 시험

## 2-bis. 착수 전 확인한 사실 (2026-10-16)

| 확인한 것 | 결과 |
| --------- | ---- |
| `redact()` 가 OS 사용자명을 가리는가 | 가린다 (`hermes_known_values.py:50` `getpass.getuser()`) — 프롬프트 전체를 가리면 `/home/<user>/` 경로가 깨진다 |
| loop 저장 경계 마스킹 | 있음 (`hermes_loop.py:146·156·217·282`) — goal.md 직접 편집분만 빈다 |
| cron 로그 git 추적 | 안 함 (`.gitignore:46` `.hermes/*`) — 로컬에만 남는다 |
| `messages` 저장 시 마스킹 | 없음 (`hermes-message.py:47`) |

## 3. 비목표 (Out of Scope)

- 공통 LLM 어댑터·구독/API 전환 (OmniRoute 미도입 결정, 필요 실측 시 재검토)
- cron 로그 파일(에이전트 출력) 마스킹 — git 밖 로컬 파일
- `hermes_redact` 패턴 보강(유선전화·JWT·PEM·타인 이름) — 별도 백로그
- `messages` 저장 시점 마스킹 — 전송 경계에서 막으면 이번 목적은 충족

## 4. 영향 영역

- 코드: 위 표 6개 파일 (각 1~3줄, 사람 입력 필드에만 `redact()`)
- **신규 파일 목록**:
  - `tests/hermes-redact-llm-input-test.sh` — 6개 LLM 전송 경계가 비밀을 가리는지 가짜 claude 로 검증
- 룰: R3 인접(LLM 경로), R-privacy
- 데이터: 없음
- 외부 의존: 없음

## 5. 단계 (Steps)

### Step 1. 실패하는 시험 작성 [단순]
- 산출: `tests/hermes-redact-llm-input-test.sh` — 6개 모두 ✗ 확인

### Step 2. 6곳 수정 [단순]
- 프롬프트 전체가 아니라 사람 입력 필드만 가린다(경로 보존)

### Step 3. 검증 [단순]
- 새 시험 전부 ✓, 기존 마스킹·loop·summon·mesh 시험 통과, `run-all.sh` 에 새 시험 등록

## 6. 의사결정 로그

- 2026-10-16: 프롬프트 전체가 아닌 입력 필드만 가린다 — 근거: OS 사용자명 마스킹이 경로를 깨뜨림
- 2026-10-16: cron 은 저장(`cmd_send`)이 아니라 전송(`format_unread`)에서 가린다 — 근거: 이번 목표는 LLM 전송 경계, DB 는 로컬

## 7. 발견·예외

- 결과(2026-10-16): 새 시험 RED 6/6 LEAK → GREEN 6/6 CLEAN. 관련 기존 시험 18개 rc=0.
- evolve 는 `project_dir` 을 넘겨야 `.env` 값 대조가 걸린다 — 실측: 넘김 → 노출 False / 안 넘김(cwd 다른 폴더) → 노출 True. `evolve_skill` 이 `project_dir_for_db(db_path)` 를 넘긴다.
- code-reviewer(HIGH): 사람 입력 안의 `/home/<user>/…` 경로도 이름 규칙에 깨졌다 → `hermes_redact.redact_keep_paths` 추가, summon·loop 에 적용. 시험 T3·T5 에 홈 경로 사례를 넣어 RED(PATH-BROKEN) → GREEN 확인.
- code-reviewer(LOW): summon 이중 가림 → 프롬프트는 `build_task_prompt(agent, 원문, project)` 한 곳에서 가린다. loop 조건 문구가 가려지면 에이전트의 체크박스 문자열 매칭이 어긋날 수 있다는 지적은 비밀이 조건에 들 때만 생겨 두었다(드라이버는 원본 파일로 센다).
- 패턴 구멍(유선전화·JWT·PEM·명부 밖 이름)은 `docs/exec-plans/backlog/redact-pattern-gaps.md` 로 넘겼다.

## 8. 회고 (완료 시 작성)

- 잘된 것: 가짜 CLI 로 stdin 을 받아 대조하니 6개 경계를 한 시험 파일로 고정할 수 있었다. 경로 깨짐(OS 사용자명 마스킹)을 착수 전에 발견해 "입력 필드만 가린다" 로 정했다.
- 잘못된 것: 착수 전 발견을 "프롬프트 전체" 에만 적용하고 입력 필드 안의 홈 경로는 놓쳤다 — code-reviewer 가 잡았다(HIGH). 또 hermes-manager 의 tier(0) 를 확인하지 않고 redact(1) 를 import 해 R-dep 에 막혔다.
- 다음 룰 후보: "LLM 을 부르는 새 코드는 사람 입력 필드에 redact(경로를 쓰는 에이전트 프롬프트는 redact_keep_paths) 를 건다" — 호출 지점 13곳이 흩어져 있어 기계 강제는 공통 어댑터가 생길 때 검토.
