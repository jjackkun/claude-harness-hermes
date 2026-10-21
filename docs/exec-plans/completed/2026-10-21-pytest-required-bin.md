# 2026-10-21-pytest-required-bin — setup·update-all 이 pytest 를 프로젝트 가상환경에 깐다

## 1. 동기 (Why)

R-test 게이트(harness 프리셋)는 pytest 가 있어야 돈다. 그런데 컴퓨터마다 사람이
`sudo apt-get install -y python3-pytest` 를 손으로 친다. 손 설치는 컴퓨터마다 켜짐/꺼짐이 갈린다
(2026-09-20 age 와 같은 문제). 이미 `REQUIRED_BINS` 경로(lib/tool_installers.sh)가 setup·update-all 에서
도구를 깐다. pytest 도 거기에 태운다.

**단, 파이썬 패키지는 전역에 깔지 않는다** (사용자 지시 2026-10-21) — 전역 설치는 다른 프로젝트의
파이썬 환경에 영향을 준다. 각 프로젝트의 가상환경에만 깐다. sudo 도 쓰지 않는다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 — harness 프리셋이 `REQUIRED_BINS+=(pytest)` 와 `GITIGNORE_ENTRIES+=(".venv/")` 를 선언한다 — 검증: grep
- [x] G2 — 파이썬 시험(`tests/`·`backend/tests/` 아래 `test_*.py`·`*_test.py`)이 없는 프로젝트는 아무것도 만들지 않는다 — 검증: 시험 [5]
- [x] G3 — 가상환경(R-test 와 같은 순서 `backend/.venv backend/venv .venv venv`)에 실행되는 pytest 가 있으면 무동작 — 검증: 시험 [6]
- [x] G4 — 가상환경은 있는데 pytest 가 없으면 **그 가상환경에만** `pip install pytest==<핀>` — 검증: 시험 [7]
- [x] G5 — 가상환경이 없으면 `<프로젝트>/.venv` 를 만들고 거기에 설치한다 — 검증: 시험 [8]
- [x] G6 — 전역(시스템 파이썬·apt·sudo·~/.local)은 건드리지 않는다 — 검증: 시험 [5]~[9] 에서 sudo/apt 호출 0, 코드에 `sudo`·`apt-get` 없음
- [x] G7 — 실패하면 설치기를 세우지 않고 손으로 칠 명령을 남긴다 — 검증: 시험 [9]
- [x] G8 — 실제 프로젝트에서 동작 — 검증: 공장에서 함수를 돌린 뒤 `.venv/bin/pytest --version`

## 2-bis. 착수 전 확인한 사실 (2026-10-21)

| 확인한 것 | 결과 |
| --------- | ---- |
| `python3 -m venv` | 동작 (sudo 불필요) |
| 파이썬 시험이 있는 소우주 | 6곳 — 4곳은 `backend/venv`·`backend/.venv` 에 pytest 있음, zeroday-frontend·공장은 가상환경 없음 |
| 파이썬 시험이 없는 소우주 | 6곳 — R-test 가 돌지 않으므로 pytest 불필요 |
| R-test 고르는 순서 | `assets/hooks/pytest_gate.sh` `PYTEST_VENV_DIRS=(backend/.venv backend/venv .venv venv)`, 없으면 시스템 |
| PyPI pytest | 최신 9.1.1 |
| 기존 가상환경 pytest 실행 | terminal-shipping 9.1.1 정상. rim-kanban·upbit-ai-trading·kis-trading 은 `bin/pytest` 파일만 있고 `No module named 'pytest'` — R-test 는 `-x` 만 봐서 이 깨진 것을 고른다 |
| 이 컴퓨터 `~/.local/bin/pytest` | python3.10 용 pip 설치물이라 3.12 에서 깨짐 — 가상환경을 먼저 고르므로 R-test 에 영향 없어짐 |

## 3. 비목표 (Out of Scope)

- 시스템 pytest 설치·삭제 — 전역은 손대지 않는다. 깨진 `~/.local/bin/pytest` 도 그대로 둔다.
- 프로젝트 의존성 파일(requirements·pyproject) 수정 — 가상환경에 pytest 만 넣는다.
- 새 `.venv` 의 파이썬 판 고르기 — 설치기가 쓰는 `python3` 를 쓴다.

## 4. 영향 영역

- 코드: `lib/tool_installers.sh`(pytest 분기, skipped 표시), `presets/workflow/harness.conf`(선언), `tests/tool-installers-test.sh`(시나리오 5~9), `README.md`(의존성 줄)
- **신규 파일 목록**:
  - `lib/tool_install_pytest.sh` — 프로젝트 가상환경을 찾거나 만들어 그 안에만 pytest 를 설치한다
- 외부 의존: PyPI (`pip install pytest==<핀>`)

## 5. 단계 (Steps)

### Step 1. 시험 먼저 [단순] — [5]~[9], 빨강 확인
### Step 2. 구현 [단순]
### Step 3. 실측 [단순] — 시험 초록, 공장에서 실제 설치, 전체 시험 한 번

## 6. 의사결정 로그

- 2026-10-21: apt 전역 설치안 폐기 → 프로젝트 가상환경 — 근거: 사용자 지시(전역 파이썬 설치는 타 프로젝트 피해).
- 2026-10-21: 파이썬 시험이 있는 프로젝트만 가상환경을 만든다 — 근거: 시험 없는 곳은 R-test 가 돌지 않는다. 빈 `.venv` 는 디스크·혼란만 남긴다.
- 2026-10-21: 이미 있는 프로젝트 가상환경에는 pytest 만 더한다 — 근거: R-test 가 그 가상환경을 먼저 고르므로, 거기 없으면 시스템으로 떨어져 경고가 난다.
- 2026-10-21: pytest 는 9.1.1 로 고정한다 — 근거: 공급망 원칙(핀 고정). 소우주에서 실제로 도는 유일한 pytest(terminal-shipping backend/.venv)가 9.1.1 이다(실측).
- 2026-10-21: `.venv/` 를 harness 프리셋의 gitignore 블록에 넣는다 — 근거: 설치기가 만든 가상환경이 커밋되면 안 된다.

## 7. 발견·예외

- 2026-10-21: 가상환경 3곳의 pytest 가 깨져 있었다(위 표). 설치기는 "실행되는가"로 판정하므로 이 3곳에도 다시 깐다. R-test 의 `-x` 판정 자체는 이번 범위 밖 — backlog 후보.
- 2026-10-21: key-guard 훅이 `grep` 검색어의 age 열쇠 도구 이름에도 반응한다(오탐). 실행이 아닌 검색이라 우회 없이 검색어를 바꿨다.

- 2026-10-21: 다른 세션(Nbbang-Run)이 `2026-10-21-project-local-install.md` 를 썼다. 그 계획 G2·G3 은 이 계획이 구현했다. 남은 G1(공통 규칙)·G4(R-test 안내 문구에 가상환경 설치 한 줄)·G5(전파)는 그 계획이 이어 맡는다.
- 2026-10-21 실측: tool-installers 29/29 · 공장 `.venv/bin/pytest` 9.1.1 · 시스템 python3 에 pytest 없음(전역 무변화) · run-all 145 중 143 통과. 실패 2건은 이 변경과 무관 — harness-hooks-smoke(생성 CLAUDE.md 103줄, 다른 세션의 스킬 3개 추가) · update-all-roundtrip(단독 재실행 35/35, 동시 설치 간섭).

## 8. 회고 (완료 시 작성)

- 잘된 것: "있음" 을 파일이 아니라 실행 성공으로 판정해, 소우주 3곳의 깨진 가상환경 pytest 를 찾아냈다. 가짜 sudo·apt 를 기록하게 한 시험이 전역 설치를 기계로 막는다.
- 잘못된 것: 처음에 전역 apt 설치로 구현했다 — "파이썬 패키지는 프로젝트 안에" 를 묻기 전에 확인하지 않았다. 사용자 지적 뒤 같은 날 되돌렸다.
- 다음 룰 후보: 설치는 프로젝트 안에만 — `2026-10-21-project-local-install.md` G1 이 공통 규칙으로 올린다. R-test 의 `-x` 판정(깨진 pytest 를 고름)은 backlog 후보.
