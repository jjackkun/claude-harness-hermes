# 2026-09-20-install-doctor-repair — 소우주 설치 상태 진단(doctor)·복구(repair) 명령

> 출처: backlog `install-doctor-repair`(ECC 결핍 #1, 가치 상) → 2026-09-20 사용자 "doctor 착수하자".
> 근거 사고 둘: (1) 2026-09-19 terminal-shipping 재설치에서 `adhd` 룰이 lock 에 없다는 이유로 조용히 제거됨.
> (2) 2026-09-20 role-templates 에서 새 스크립트 2개를 hermes.conf 복사 목록에 빠뜨려 설치본이 ModuleNotFoundError — 폐로 테스트가 잡을 때까지 아무도 몰랐다.
> 설계 인용: copy-install.md §4(설치 목록 `.factory-manifest.json`: name·kind·factory_commit·sha256·src·mode), I-02, E-02(공장 자기 설치는 링크).

## 1. 동기 (Why)

복사 설치는 설치·갱신만 있고 진단·복구가 없다. 어긋남은 세션 훅의 `[factory-link WARN]`(깨진 링크)·`[factory-tamper WARN]`(편집 순간)로만 드러나고,
"지금 이 소우주가 공장과 얼마나 어긋났는가" 를 한 번에 보는 명령이 없다. 고치는 길은 `update-all`(전부 재설치) 또는 사람 손이다.
매니페스트에 sha256 이 이미 있으므로 대조만 하면 된다 — 하루 작업.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `python3 scripts/harness-doctor.py <소우주>` 가 읽기 전용으로 네 종류를 보고한다: **변조**(매니페스트 sha256 ≠ 현재), **누락**(항목 경로 없음), **lock 어긋남**(설치된 rules 가 lock 의 프리셋 conf `RULES+=()` 선언에 없음 — 재설치 때 제거될 것), **갱신 대기**(factory_commit ≠ 공장 HEAD, 건수). 매니페스트 밖 `.claude/{skills,agents,rules}` 항목은 **사용자 자산**으로 따로 센다(오류 아님). 종료코드: 깨끗 0 · 발견 1 · 진단 불가(매니페스트 없음) 2. `--json` 은 같은 내용을 JSON 으로. — 검증: `tests/harness-doctor-test.sh` 진단 절(픽스처 설치 → 깨끗 → 변조·삭제·lock 편집·사용자 스킬 추가 각각 보고)
- [x] 목표 2 — `--repair` 는 기본이 **계획만**(무엇을 덮어쓰고 무엇을 되살리고 무엇이 제거될지) 이고, `--yes` 가 있어야 `project-claude.sh <소우주> $(lock)` 로 재설치한다. `.hermes/` 는 어떤 경우에도 건드리지 않는다. — 검증: 테스트 복구 절(계획만일 때 파일 불변 → `--yes` 후 변조·누락 0, `.hermes/skills/` 파일 그대로)
- [x] 목표 3 — `--factory-self` 가 공장 쪽 폐로를 본다: `scripts/hermes*.py` 중 `presets/workflow/hermes.conf` 복사 목록에 없는 파일, `assets/hooks/*.sh` 중 어느 프리셋에도 등록되지 않은 훅. — 검증: 테스트 공장 절(가짜 공장 폴더에 미등록 스크립트 1개 → 보고, 실제 공장 → 0)
- [x] 목표 4 — `update-all.sh` 가 각 소우주 재설치 **전에** doctor 의 한 줄 요약을 찍고, lock 어긋남(재설치로 사라질 항목)이 있으면 경고한다. 진단 실패는 재설치를 막지 않는다. — 검증: `grep -n harness-doctor update-all.sh` + 테스트에서 update-all 을 픽스처 등록부로 돌려 경고 줄 확인
- [x] 목표 5 — 실 소우주 3곳(ai-create·wonil·terminal-shipping)에 doctor 를 돌린 결과를 §7 에 남긴다. — 검증: §7 표

## 3. 비목표 (Out of Scope)

- skills·agents 의 lock 어긋남 — 프리셋 conf 를 파싱해야 하고 공통 스킬(프리셋 무관)이 섞여 오탐이 난다. rules 만 정확히 잰다(이름 = 프리셋 이름).
- 항목 단위 선택 복구 — 복구는 설치기 재실행 한 길만. 두 번째 복사 로직을 만들지 않는다.
- 우주 대시보드 열(factory_commit 일치) 연결 — 다음 계획.
- 소우주에 doctor 를 복사 배포하는 것 — 공장 도구(update-all 과 같은 자리)다.

## 4. 영향 영역

- 코드: `update-all.sh`(재설치 전 doctor 한 줄), `.deprc`(tier 등재), `tests/run-all.sh`(등록)
- **신규 파일 목록**:
  - `scripts/harness-doctor.py` — 매니페스트 대조 진단 + 복구 계획/실행 + 공장 자기 점검. 표준 모듈만(tier 0). 공개 심볼 ≤7
  - `tests/harness-doctor-test.sh` — 픽스처 설치(HARNESS_REGISTER=0) 위에서 진단·복구·공장 점검·update-all 경고 실측
- 룰: R-iface(≤7) · R-cx(11) · R-size · R-declare(이 §4) · R-dep(tier 0)
- 데이터: 없음(읽기 전용; 복구는 설치기가 쓴다)

## 5. 단계 (Steps)

### Step 1. 진단(목표 1) + 테스트 RED→GREEN [Impl]
### Step 2. 복구 계획/실행(목표 2) + 공장 자기 점검(목표 3) [Impl]
### Step 3. update-all 배선(목표 4) + 실 소우주 3곳 실측(목표 5) [Review]

## 6. 의사결정 로그

- 2026-09-20: 복구는 설치기 재실행으로만 — 근거: 설치는 변환(모드·링크·생성 파일)이 섞여 있어 두 번째 복사 로직은 곧 어긋난다.
- 2026-09-20: 매니페스트 밖 항목은 "사용자 자산" 으로 보고만 — 근거: installers.sh 의 계약("목록에 없는 실디렉터리는 사용자 자산 — 건드리지 않음")과 같다.
- 2026-09-20: lock 어긋남은 rules 만 — 근거: §3.

## 7. 발견·예외

- **lock 어긋남은 "rules 이름 = 프리셋 이름" 이 아니다.** node→typescript, svelte/react/vue→web, flutter→dart, _common→common. 첫 판은 ai-create 에 typescript·web 을 오탐했다. 프리셋 conf 의 `RULES+=(…)` 를 읽어 기대 집합을 만들자 3곳 모두 0.
- **이 컴퓨터의 공장 clone 에는 pre-commit 게이트가 없었다.** `.git/hooks` 가 7월 1일 샘플뿐이고 매니페스트(git 에 커밋됨)는 다른 컴퓨터의 자기 설치 기록이었다. 오늘 이 컴퓨터에서 만든 커밋 5개는 게이트 18종을 거치지 않았다. doctor 가 "누락 12(githook 전부)" 로 잡았고, 자기 설치(`project-claude.sh . harness hermes mcp skill-dev adhd`)로 복구 → 깨끗 0/0/0, 갱신 대기 0/87. 이 계획의 커밋부터 게이트가 실제로 돈다.
- **소우주 3곳의 "불일치" 는 전부 옛 공장판 보존이다** (ai-create 5 · wonil 3 · terminal-shipping 4 — pre-commit 13종 판, history-reindex 옛 판 등). 공존 설치가 옛 판을 하류 수정으로 오인해 손대지 않는다. 설치기 결함 → backlog `coexist-old-factory-detection`. 그 전까지 doctor 표기는 "불일치(하류 수정 또는 옛 판 보존)".
- 실측 표(목표 5, 2026-09-20 자기 설치 뒤 공장 HEAD 기준):

| 대상 | 불일치 | 누락 | lock 어긋남 | 갱신 대기 | 사용자 자산 |
|---|---|---|---|---|---|
| ai-create | 5 (훅·githook 옛 판) | 0 | 0 | 5/198 | 0 |
| wonil | 3 (훅 옛 판) | 0 | 0 | 3/186 | 0 |
| terminal-shipping | 4 (githook·훅 옛 판) | 0 | 0 | 4/200 | 9 |
| 공장(자기 설치 전 → 후) | 16 → 0 | 12 → 0 | 0 | 84/84 → 0/87 | 2 → 1 |

- 공장 자기 점검(`--factory-self`): 스크립트 86 · 훅 51 — 복사 목록 누락 0 · 미등록 훅 0.
- 시험 잡음: GNU grep 이 UTF-8 로케일에서 `제거된다.*rules/adhd` 를 못 맞춘다(C 로케일·ugrep 은 맞춤). 단언은 `-F` 고정 문자열로.
- `git mv` 는 작업 트리 수정을 스테이지하지 않는다 — agent-hire-form 완료 커밋(fc426c2)에 §8 회고가 빠졌다. 이번 커밋에 함께 넣는다. 규칙: mv 뒤 반드시 `git add <새 경로>`.

## 8. 회고 (완료 시 작성)

- 잘된 것: 매니페스트가 이미 sha256 을 갖고 있어 진단은 대조뿐이었고, 첫 실행에서 진짜 결함 둘(공장 clone 게이트 부재, 공존 설치의 옛 판 보존)을 찾았다. 복구를 설치기 재실행 한 길로 묶어 두 번째 복사 로직을 안 만들었다.
- 잘못된 것: lock 판정을 "rules 이름 = 프리셋 이름" 으로 가정하고 짰다가 실 소우주에서 오탐 — 실측을 먼저 보고 규칙을 정했어야 했다. 게이트가 없는 clone 에서 하루 종일 커밋했다 — 세션 시작 훅이 `.git/hooks/pre-commit` 부재를 알렸어야 한다.
- 다음 룰 후보: (1) 세션 시작 훅에 `harness-doctor.py . --brief` 한 줄 — 공장·소우주 모두 "누락 > 0" 이면 경고. (2) 공존 설치 옛 판 판정 수정(backlog). (3) `git mv` 뒤 `git add` — 훅으로 잡기 어렵고 R-plan 이 completed 이동을 볼 때 §8 빈칸이면 경고(R-retro 가 이미 있다 — 왜 안 울렸는지 확인).
