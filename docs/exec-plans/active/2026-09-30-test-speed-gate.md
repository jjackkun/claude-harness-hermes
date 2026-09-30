# 2026-09-30-test-speed-gate — 커밋 게이트의 pytest 가 프로젝트 가상환경으로, 느린 원인이 보이게, 시험 DB 는 로컬에

> 작성일: 2026-09-30
> 목적: 소우주의 백엔드 시험이 느린 원인(원격 DB 왕복)과 게이트의 결함(가상환경 못 찾음)을 고치고, 검증된 방법을 공통 규칙으로 올린다.
> 짝 계획: terminal-shipping `docs/exec-plans/active/2026-09-30-local-test-db.md`(로컬 시험 DB 로 옮기기 — 실측의 출처).
> 순서(사용자 결정 2026-09-30): **① 이 계획 Phase A(게이트 결함)** → ② terminal-shipping 로컬 시험 DB → ③ 그 숫자로 **Phase B(공통 규칙)** → 전파.

## 1. 동기 (Why)

2026-09-30 terminal-shipping 백엔드 실측: 1,465개 · 18분 · **CPU 7%**. 시험 DB 가 SSH 터널 너머 운영 PC 에 있어 쿼리 왕복이 34 ms(연결 285 ms)다. 시험이 느린 것은 개수가 아니라 거리였다.

공장 쪽에서 드러난 것:
1. **R-test 가 프로젝트 가상환경을 못 찾는다.** `assets/hooks/pre-commit.sh` R-test 는 `backend/venv/bin/pytest`·`venv/bin/pytest` 만 본다. `uv` 로 만든 `backend/.venv`·`.venv` 는 모르고 시스템 pytest(`~/.local/bin/pytest`)로 떨어진다. terminal-shipping 에서 69번 "통과" 로 기록됐지만 **프로젝트 의존성으로 돈 것인지 보증이 없다.**
2. **R-test 가 얼마나 걸렸는지 아무도 모른다.** 게이트 기록(`gate-events.jsonl`)에 시간이 없다. 18분짜리가 커밋마다 돌아도 기록만으로는 알 수 없다.
3. **"시험 DB 는 로컬" 이라는 원칙이 어디에도 없다.** 소우주마다 같은 함정(원격 DB 에 시험을 붙임)에 빠질 수 있다.

> 여기까지 다시 읽었다: Phase A 는 지금 고칠 수 있는 게이트 결함(1·2)이다. Phase B(3)는 terminal-shipping 에서 로컬 전환의 효과를 **잰 뒤에** 쓴다 — 재기 전에 일반화하지 않는다(CLAUDE.md PDF 11쪽).

## 2. 목표 (What — 검증 가능한 형태)

**Phase A — 게이트 결함 (지금)**
- [x] 목표 1 — **R-test 는 프로젝트 가상환경의 pytest 를 먼저 쓴다.** 찾는 순서: `backend/.venv` → `backend/venv` → `.venv` → `venv` → 시스템. 시스템으로 떨어지면 경고 한 줄을 남긴다(조용한 대체 금지). 실행 위치는 지금처럼 저장소 루트이고 pytest 가 `backend/pyproject.toml` 을 찾아 rootdir·`pythonpath` 를 잡는다 — 이 전제가 실제로 맞는지 **terminal-shipping 에서 `.venv` pytest 로 게이트를 한 번 돌려** 수집 오류가 없는지 확인한다. 검증: `bash tests/r-test-venv-test.sh`(`.venv` 만 있는 가짜 프로젝트에서 그 pytest 가 불린다 · 아무것도 없으면 시스템 + 경고) · terminal-shipping 실측 1회.
- [x] 목표 2 — **R-test 가 걸린 시간을 남기고, 길면 원인을 짚는다.** pytest 앞뒤로 `date +%s` 를 재서 게이트 기록 `detail` 문자열에 `N초` 를 덧붙이고(기존 `gate_add` 시그니처 그대로 — `gate_report.py` 는 `detail` 을 파싱하지 않으므로 영향 없음을 확인한다), 에이전트 도구 한도(600초)의 절반(300초)을 넘으면 경고한다: "CPU 사용률이 낮으면 DB·네트워크를 기다린 것 — 시험 DB 가 원격인지 보라". 통과여도 결과의 건너뜀(skipped) 수가 통과 수보다 많으면 "대부분 건너뜀 — 시험 DB 가 꺼져 있을 수 있다" 도 경고한다(skip 이 통과로 보이는 틈, 계획 검토 지적). 검증: 같은 시험(느린 가짜 pytest → 경고 · 빠른 것 → 경고 없음 · 기록에 초가 남음 · 건너뜀이 많으면 경고).

**Phase B — 공통 규칙 (terminal-shipping 실측 뒤)**
- [ ] 목표 3 — **규칙: 시험 DB 는 시험하는 PC 에 둔다.** `docs/design-docs/core-beliefs.md` 에 원칙과 근거(terminal-shipping 전후 수치)를 적고, `run-to-the-end` 스킬의 "오래 걸리는 시험" 절에 "먼저 CPU 사용률을 잰다 — 낮으면 기다림이 원인" 을 넣는다. 검증: 문서 대조 리뷰 · 스킬 발동 문구 확인.
- [ ] 목표 4 — **작업 중에는 바뀐 부분만, 전체는 푸시 전 한 번.** 바뀐 파일에 닿는 시험만 고르는 방법(`pytest-testmon` 또는 경로 규칙)을 terminal-shipping 에서 써 보고, 효과가 확인되면 스킬·기억 규칙(`전체 시험은 마지막 한 번`)에 도구로 넣는다. 검증: terminal-shipping 에서 한 파일 변경 때 고른 시험 수·시간 실측.
- [ ] 목표 5 — **등록·전파.** 새 시험을 `tests/run-all.sh` 에 등록, 문서 수치 동기화, 전체 시험 한 번, 소우주 전파(설치 커밋·푸시).

## 2-bis. 착수 전 확인한 사실 (2026-09-30)

| 확인한 것 | 결과 |
| --- | --- |
| R-test 가 찾는 pytest | `backend/venv/bin/pytest` · `venv/bin/pytest` → 없으면 시스템 `pytest` (`assets/hooks/pre-commit.sh` R-test 블록) |
| R-test 가 돌리는 범위 | 프로젝트 파이썬이 바뀐 커밋이면 `tests` 또는 `backend/tests` **전체**(`"$PYTEST_BIN" "$PYTEST_DIR" -q`) |
| terminal-shipping 기록 | R-test pass 69 · block 2 (시간 기록 없음) |
| terminal-shipping 가상환경 | `backend/.venv`(uv) — 게이트가 못 찾음 |
| 규칙 문서 | `core-beliefs.md#r-test` 는 세 상태(실패·수집 0·실행 불가)만 다룬다. 시간·가상환경 언급 없음 |

## 3. 비목표 (Out of Scope)

- 소우주의 시험 DB 를 공장이 직접 옮기지 않는다(프로젝트마다 DB·역할·포트가 다르다 — terminal-shipping 계획이 한다).
- R-test 가 "바뀐 부분만" 돌리게 바꾸는 것은 Phase B 실측 전에는 하지 않는다(덜 돌린 시험이 조용해지는 위험).
- 시험 병렬화(xdist)는 다루지 않는다.

## 4. 영향 영역

- 코드(수정): `assets/hooks/pre-commit.sh`(R-test 가상환경 순서 · 시간 기록 · 경고, 약 15줄) · 공장 자기 설치본 `.git/hooks/pre-commit`(설치로 반영) · `tests/run-all.sh` · `docs/design-docs/core-beliefs.md#r-test` · Phase B 에서 `assets/skills/run-to-the-end/SKILL.md`.
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `tests/r-test-venv-test.sh` — 가짜 프로젝트에서 R-test 가 고르는 pytest 와 시간 경고를 확인한다.
- 룰: R-test(바뀜) · R-size(`pre-commit.sh` 는 이미 큼 — 추가 최소화).
- 되돌리기: git. 전파 뒤 회귀하면 공장에서 되돌린 커밋을 다시 전파한다(소우주는 설치물만 바뀌므로 같은 절차).

## 5. 단계 (Steps)

### Phase A
- Step A1. 시험 먼저 → 가상환경 순서·시스템 대체 경고. 검증: 새 시험 · 기존 R-test 시험.
- Step A2. 시간 기록·경고(300초). 검증: 같은 시험.
- Step A3. 공장 재설치 · 전체 시험 한 번 · 커밋. 전파 전에 12곳의 `venv`/`.venv` 유무를 훑는다(둘이 함께 있는 곳은 고르는 가상환경이 바뀐다). **전파는 terminal-shipping 로컬 시험 DB 계획이 끝난 뒤** — 먼저 전파하면 terminal-shipping 커밋이 새로 잡힌 `.venv` 로 18분 게이트를 돈다.

### Phase B (terminal-shipping 로컬 시험 DB 완료 뒤)
- Step B1. 전후 수치를 받아 규칙·스킬 문구를 쓴다.
- Step B2. 바뀐 부분만 고르는 방법을 terminal-shipping 에서 재고 도구로 넣을지 정한다. 채택 기준: 한 파일 변경 때 고른 시험이 전체의 절반 이하이고, 일부러 깨뜨린 변경을 고른 시험이 잡아내는 것(놓침 0).
- Step B3. 등록·전체 시험·전파·회고.

## 6. 의사결정 로그

- 2026-09-30: 소우주별 설정(로컬 DB)과 공통 원칙(게이트·규칙)을 나눠 두 계획으로 둔다 — 근거: DB 종류·역할·포트는 프로젝트 사정이고, 게이트는 공장 소유다(사용자 결정).
- 2026-09-30: 규칙(Phase B)은 terminal-shipping 실측 뒤에 쓴다 — 근거: 재기 전에 일반화하지 않는다. 손해: 다른 소우주는 그때까지 같은 함정에 빠질 수 있다.
- 2026-09-30: 시간 경고 기준 300초 — 근거: 에이전트 도구 한도 600초의 절반이면 전체 시험을 앞에서 기다리는 일이 위험해진다. 손해: 원래 긴 시험이 있는 프로젝트는 매번 경고를 본다(경고일 뿐 차단 아님).

## 7. 발견·예외

- ~~R-test 는 프로젝트 파이썬이 바뀐 커밋마다 전체 시험을 돈다~~ → **정정(2026-09-30 실측):** R-test 는 `tests` 를 `backend/tests` 보다 먼저 고르는데 terminal-shipping 에는 둘 다 있어 **루트 `tests/`(도구 시험 292개, 8.6초)만** 돌아 왔다. 백엔드 1,465개는 커밋 때 한 번도 돌지 않았고, 18분 실행은 에이전트가 직접 돌린 `pnpm test` 였다. 백엔드 시험을 게이트에 넣는 것은 로컬 시험 DB 전(18분)에는 하지 않는다 — terminal-shipping 계획이 끝난 뒤 Phase B 에서 "두 폴더 모두" 를 정한다.
- 소우주 가상환경 조사(2026-09-30): `backend/venv`(pytest 있음) — rim-kanban · upbit-ai-trading · kis-trading / `backend/.venv` — terminal-shipping(이번에 처음 제 가상환경으로 돈다) / 없음 — 나머지(시스템 pytest, 경고 없음). `.venv` 와 `venv` 가 함께 있는 곳은 없다.
- 시스템 pytest 경고는 처음 설계("시스템으로 떨어지면 항상 경고")가 기존 스모크 시험("통과하면 침묵")에 걸렸다 — 가상환경 없이 시스템 pytest 를 쓰는 구성(이 공장 포함)은 정상이다. **가상환경 폴더가 있는데 pytest 가 없을 때만** 경고하도록 좁혔다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
