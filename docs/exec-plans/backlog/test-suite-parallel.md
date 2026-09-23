# test-suite-parallel — 전체 시험 묶음이 35분이다

## 1. 동기 (Why)

**실측 2026-09-23.** `bash tests/run-all.sh` 107개가 **35분** 걸렸다(09:41 → 10:16, 107/107 통과).

원인은 느린 시험 하나가 아니라 **구조**다. `tests/*.sh` 중 **17개가
`project-claude.sh` 전체 설치를 수행**하고, 설치 한 번이 파일 95개 복사 + settings 생성 +
CLAUDE.md 생성이다. 그 17개가 **순차로** 돈다 — `run_step` 은 서브셸로 한 번에 하나씩 부른다.

전체 설치를 하는 시험(2026-09-23 기준 17개):
`eval-reminder` · `harness-doctor` · `hermes-roster` · `hermes-universe` · `copy-install` ·
`hermes-role-templates` · `update-all-roundtrip` · `install-receipt` · `preset-lock-tracked` ·
`plan-stale-completion` · `uninstall-roundtrip` · `windows-smoke` 외 5

### 무엇이 실제로 아팠나

2026-09-22~23 한 세션에서 전체 묶음을 **4번** 돌렸고 **3번을 중간에 죽였다** —
도는 동안 저장소 파일을 바꿔 결과가 무의미해졌기 때문이다(`copy-install-test.sh:170` 이
실 `.installed-projects` 의 불변을 단언한다). 벽시계로 100분 넘게 태웠고,
사용자가 "26분째 하고 있어. 이게 맞아?" 라고 물었다.

즉 비용은 35분이 아니라 **"돌리는 동안 아무것도 못 고친다 × 반복 횟수"** 다.

## 2. 목표 후보

- [ ] 목표 후보 1 — 전체 묶음이 **10분 이내**. 검증: `time bash tests/run-all.sh` 를 3회 재서 중앙값.
- [ ] 목표 후보 2 — 병렬로 돌려도 판정이 같다. 검증: 같은 커밋에서 순차/병렬 결과의
      통과·실패 집합이 일치(일부러 깨뜨린 시험 1개 포함).
- [ ] 목표 후보 3 — 실패한 시험의 출력이 뒤섞이지 않는다. 검증: 2개를 동시에 깨뜨리고
      각 실패 블록이 온전히 읽히는지.
- [ ] 목표 후보 4 — **실 저장소를 건드리는 시험은 병렬에서 뺀다.** 검증: 그 목록이 명시돼 있고,
      `.installed-projects`·`.hermes/dashboards/` 를 읽는 시험이 거기 들어 있다.

## 3. 비목표

- 시험을 지우거나 단언을 줄여 시간을 버는 것. 107개는 오늘 실제로 결함 3건을 잡았다.
- 설치 자체를 빠르게 만드는 것(복사 95건). 그건 별건이고 위험이 크다.
- CI 이관만으로 끝내는 것. 로컬에서도 돌 수 있어야 한다 — CI 는 60회 연속 실패한 이력이 있다.

## 4. 착수 전 확인할 것

| 확인할 것 | 왜 |
| --- | --- |
| 17개 설치 시험이 **정말** 서로 격리돼 있나 (`mktemp` · `HOME` 치환) | 하나라도 공유 자원을 쓰면 병렬에서 깨진다 |
| 실 저장소(`$REPO_ROOT`)를 **쓰는**(읽기 아님) 시험 목록 | 이들은 순차로 남겨야 한다 |
| `run_step` 의 출력 수집 방식 (CI 에서만 `tee`) | 병렬이면 항상 파일로 모아야 섞이지 않는다 |
| 머신 코어 수 · 설치의 I/O 대 CPU 비중 | 병렬도를 정하는 근거. 무작정 `-j$(nproc)` 는 아니다 |
| `SKIP_TESTS`·`SKIP_INTERACTIVE` 와의 상호작용 | 기존 환경변수 계약을 깨지 않는다 |

## 5. 관련

- `tests/run-all.sh` — `run_step` (서브셸 순차 실행)
- `tests/run-all-orphan-guard-test.sh` — 목록 누락 검사. 병렬화해도 이 계약은 유지해야 한다
- `docs/exec-plans/completed/2026-09-23-r-lock.md` §8 — 같은 세션에서 나온 "실행 중 파일 수정" 교훈
- 룰 후보 **R-testrun-clean**(`2026-09-22-universe-dashboard-auto.md` §8) — 묶음이 도는 동안
  저장소를 바꾸면 경고. 이 계획과 짝이다: 실행이 짧아지면 그 사고도 줄어든다.
