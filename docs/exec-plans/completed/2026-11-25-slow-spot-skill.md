# 2026-11-25-slow-spot-skill — 느린 곳을 재서 하나만 고치고 원래 결과와 대조하는 스킬(공장 전용)

## 1. 동기 (Why)

- 2026-11-25 설치 개선(`completed/2026-11-25-manifest-batch-write.md`)에서 효과를 낸 것은 세 단계였다:
  ① 짐작 말고 잰다(처음 의심한 훅은 0.12초 아래, 실제 범인은 설치 안 `manifest_add` 55%)
  ② 가장 큰 범인 하나만 고친다 ③ 고치기 전 결과를 기준선으로 찍고 바이트까지 같을 때만 남긴다.
- 그때 쓴 도구 둘(bash 줄 단위 프로파일 집계기 · 결과 스냅샷 대조기)은 스크래치에만 있어 다음에 다시 짜야 한다.
- 공장의 `performance-optimizer` 에이전트(448줄)는 최적화 기법 목록이 중심이고, "기준선과 대조해 같을 때만 남긴다" 단계가 없다.
- 계기 영상: `docs/videos/2026-11-24-fast-anything/`. 사용자 결정(2026-11-25): 공장에 먼저 만들고, 효과를 본 뒤 전파한다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 `trace_agg.py` 가 심어 둔 느린 함수를 함수별 1위로 낸다 — 검증: 정적 시험. 함수 `slow_fn` 은 외부 명령
      (`python3 -c pass`)을 20번 띄우고, `fast_fn` 은 셸 내장만 20번 돈다. 기대: 함수별 1위 = `slow_fn`,
      명령별 표에 `python3 ×20`. 형식이 다른 파일은 종료 코드 0 + "추적 줄이 2개보다 적습니다".
- [x] G2 `snapshot.py` 가 내용·모드·링크 대상 변화를 잡고, `--ignore <정규식>`(여러 번) 에 걸린 경로는 무시한다 —
      검증: 정적 시험. 기대: 같은 폴더 두 번 찍기 = 차이 0(종료 0) · 내용/모드/링크 각각 1줄 차이(종료 1) ·
      잡음 경로만 바뀐 경우 차이 0. `.git/` 은 늘 뺀다. 잡음 기본값은 없다 — 프로젝트마다 다르므로 기준선 두 번 찍기로 찾는다.
- [x] G3 스킬 절차로 `tests/harness-eval-test.sh`(기록 217초, 설치와 무관한 시험 중 가장 김)를 잰다 —
      검증: §8 에 함수별 1위와 비중, 그리고 판정 하나. 합격선: 1위가 전체의 20% 이상이면 고칠 후보로 적고(고치면 기준선 대조 필수),
      20% 미만이면 "고르게 퍼짐 — 고칠 곳 없음" 도 합격이다. 재지 못하면 불합격.
- [x] G4 공장 전용 배치 — 검증: `.claude/skills/slow-spot` 링크가 추적됨 · `presets/` 에 이름 0 · README 「공장 전용 스킬」 표 1줄 ·
      `tests/run-all.sh` 등록 — 넷을 정적 시험이 확인한다.

## 2-bis. 착수 전 확인한 사실 (2026-11-25)

| 확인한 것 | 결과 |
| --------- | ---- |
| 공장 전용 스킬 배치 방식 | `assets/skills/<이름>` + 공장 `.claude/skills/<이름>` 추적 링크, 프리셋 미등록(예: harness-eval) |
| 같은 일을 하는 기존 스킬 | 없음(assets/skills 에 perf·slow·prof 이름 0) |
| 옮겨 올 원본 도구 | 앞 작업 스크래치의 `agg.py`(28줄) · `golden.sh`(19줄, 설치 전용) — 집계기는 일반화해 옮기고, 대조기는 폴더 일반용으로 새로 쓴다 |
| 느린 시험 기록 | `.harness/test-durations.tsv`(2026-11-02): copy-install 261 · harness-eval 217 · update-all-roundtrip 206초 |

## 3. 비목표 (Out of Scope)

- 소우주 전파(프리셋 등록) — G3 효과 확인 뒤 따로.
- 다른 언어로 다시 쓰기 · fast-anything 연동.
- 발동 정확도 측정(`run_loop`) — 모델 호출 비용. 사용자 승인 뒤.

## 4. 영향 영역

- **신규 파일 목록**:
  - `assets/skills/slow-spot/SKILL.md` — 재기 → 하나만 고치기 → 대조 절차
  - `assets/skills/slow-spot/scripts/bash_profile.sh` — bash 명령을 시각 찍은 xtrace 로 돌려 추적 파일을 남긴다
  - `assets/skills/slow-spot/scripts/trace_agg.py` — 추적 파일을 함수·줄·명령별 시간과 횟수로 모은다
  - `assets/skills/slow-spot/scripts/snapshot.py` — 폴더 결과를 찍고(take) 두 찍음을 잡음 빼고 대조한다(diff)
  - `assets/skills/slow-spot/references/profilers.md` — Python·Node 프로파일 명령(언어별 참고)
  - `tests/slow-spot-skill-test.sh` — 위 스크립트 정적 시험
- 코드: `.claude/skills/slow-spot`(링크), `tests/run-all.sh`(등록), `README.md`(공장 전용 스킬 표)

## 5. 단계 (Steps)

### Step 1. 스크립트 3개 [Impl]
- 산출: `bash_profile.sh` · `trace_agg.py` · `snapshot.py`. 완료 조건: 셋 다 `--help`/인자 없음에 사용법을 내고 종료 2.
### Step 2. 정적 시험 [Impl]
- 산출: `tests/slow-spot-skill-test.sh`. 완료 조건: G1·G2·G4 단언 통과, `run-all.sh` 등록.
### Step 3. SKILL.md · references/profilers.md [Impl]
- 완료 조건: 본문 200줄 아래. profilers.md 의 명령은 이 컴퓨터에서 실행해 본 것만 "실행 확인" 으로 적고, 나머지는 "미확인" 으로 표시.
### Step 4. G3 적용 [Review]
- 완료 조건: §8 에 측정값과 판정.

## 6. 의사결정 로그

- 공장 전용으로 둔다 — 효과를 한 번 더 본 뒤 전파(사용자 결정).
- 작업 자리: 앞 작업 worktree 를 합쳐 지운 뒤 훅이 메인 체크아웃 쓰기를 막아, 같은 경로에 새 브랜치
  `claude/slow-spot-skill` 로 worktree 를 다시 만들었다(사용자 선택, 2026-11-25).

## 7. 발견·예외

위험과 대응:
- xtrace 는 펼친 명령을 그대로 적는다 — 비밀값이 든 변수가 추적에 남을 수 있다. 추적 파일은 `.harness/out/`(git 무시)에만 두고,
  SKILL.md 에 "추적 파일을 커밋·공유하지 않는다" 를 적는다.
- xtrace 시각 찍기가 줄마다 붙어 전체가 1.1~1.3배 느려진다(2026-11-25 설치: 추적 16.8초 / 추적 없음 14.3초).
  셸 내장이 많은 함수가 실제보다 크게 보일 수 있다 — 순위는 추적으로, 전후 시간은 추적 없이 잰다.
- 기준선을 찍는 동안 대상이 바뀌면 잡음과 결함이 섞인다 — 고치기 전에 기준선을 두 번 찍어 잡음부터 가린다.
- bash 밖(Python·Node)은 집계기가 없다. profilers.md 는 표준 도구 명령만 안내한다.
- 되돌리기: 새 파일만 더하고 기존 코드는 README 표·run-all 목록 각 1줄만 바꾼다. 커밋 하나를 되돌리면 끝난다.

## 8. 회고 (완료 시 작성)

- G1·G2·G4: `tests/slow-spot-skill-test.sh` 24/24(모델 0). G1 함수별 1위 `slow_fn`, 명령별 `python3 ×20`.
- G3 `tests/harness-eval-test.sh` (2026-11-25, 단독):
  - ① 추적 없이 83.2초(PASS 37). 이전 기록 217초는 2026-11-02 전체 묶음 안·설치 개선 전 값이라 조건이 다르다.
  - ② 함수별 1위 `R`(러너 호출) 87.8% · 2위 `main` 12.2%(줄 168 의 러너 직접 호출 9.4초). 명령별 `python3 ×21` 99.9%.
    러너 `scripts/harness-eval.py` 가 호출마다 `_build_template` 에서 `project-claude.sh` 설치를 새로 한다 — 같은 설치 9번.
  - 판정: 20% 이상 → 고칠 후보. 이번 범위(스킬 만들기) 밖이라 `backlog/harness-eval-template-reuse.md` 에 남겼다.
- 스킬을 처음 써서 도구 결함 2개를 찾아 고쳤다:
  1. 시험 안 함수가 `2>파일` 로 표준 오류를 돌리면 그 안의 추적 줄도 그 파일로 빠졌다 — `R` 함수 줄이 통째로 사라져
     "줄 8개가 10초씩 고르게" 로 잘못 보였다. `BASH_XTRACEFD` 로 추적을 따로 내게 고치고 시험 2개를 더했다.
  2. 한 줄에 명령이 여럿이면 줄 견본이 첫 명령(`local rc`)이었다 — 가장 오래 걸린 명령으로 바꿨다.
- 배운 것: 도구를 실제 대상에 한 번 써 봐야 결함이 보인다. 정적 시험(심은 함수)만으로는 1번을 못 잡았다.
- 하지 않은 것: 발동 정확도 측정(모델 호출) · 비교 실행 · 소우주 전파.
