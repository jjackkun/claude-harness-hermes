# 2026-09-14-adhd-output-rule — 행동 우선 답변 규칙(adhd 프리셋) 도입

## 1. 동기 (Why)

- 사용자는 짧게 묻는데 답변이 표·섹션으로 길어져, 지금 할 일이 묻히는 일이 이 저장소 대화에서 반복됐다(2026-09-14 세션).
- 외부 스킬 `ayghri/i-have-adhd`(MIT, ⭐44.5K)가 같은 문제를 "첫 줄=할 일 / 마지막=다음 행동 하나" 형식으로 다룬다.
  자체 평가(evals/RESULTS.md, 2026-08-02)에서 진행 상태 보고 +2.53, 오류 보고 +2.40 으로 개선 폭이 컸다.
- 원본 전체는 쓰지 않는다. 규칙 8(원인→해결 단정)이 유일하게 일관된 퇴행(partial-success −0.63)을 냈고,
  전역 CLAUDE.md 의 "불확실하면 추측 금지" 와 충돌한다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `adhd` 프리셋이 규칙 파일을 배포한다. 검증: `bash tests/preset-integrity-test.sh` PASS. (2026-09-14 실측: 28개 conf, 93개 참조 유효)
- [x] 목표 2 — 이 저장소·zeroday-frontend·terminal-shipping 3곳의 `presets.lock` 에 `adhd` 가 있고 `.claude/rules/adhd` 가 원본을 가리킨다. 검증: `readlink` 결과가 `assets/rules/adhd`. (2026-09-14 실측: 3곳 모두 일치)
- [x] 목표 3 — 세 프로젝트의 CLAUDE.md 룰셋 목차에 `adhd` 가 보인다. 검증: `grep "이 프로젝트 룰셋" CLAUDE.md`. (2026-09-14 실측: 3곳 모두 표시)

## 3. 비목표 (Out of Scope)

- 원본 SKILL.md 의 규칙 2·4·6·7·8·9 반영 (중복 또는 전역 규칙과 충돌).
- SessionStart 훅 방식의 압축 후 재주입 (C안). 규칙이 느슨해지는 것이 관측되면 별도 계획.
- 나머지 등록 프로젝트 전파 (`update-all.sh` 전체 실행하지 않음).

## 4. 영향 영역

- 코드: `README.md` 프리셋 목록 2곳.
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `assets/rules/adhd/adhd-output.md` — 답변 형식 규칙 4개와 켜기/끄기·우선순위를 에이전트에 지시한다.
  - `presets/workflow/adhd.conf` — adhd 규칙 세트를 프로젝트 설치 대상으로 선언한다.
- 룰: 없음(R 룰 아님, 답변 형식 규칙).
- 데이터: 없음.
- 외부 의존: 원본 MIT — 규칙 파일에 출처·저작권 표기.

## 5. 단계 (Steps)

### Step 1. 규칙 파일·프리셋 작성 [단순]

- 산출: 신규 파일 2개, README 갱신.
- 검증: `tests/preset-integrity-test.sh` PASS.

### Step 2. 3개 프로젝트 설치 [단순]

- 입력: 각 프로젝트 `presets.lock` 중 실존 프리셋만(update-all.sh `preset_exists` 와 같은 기준) + `adhd`.
- 산출: `project-claude.sh <경로> <프리셋...>` 실행.
- 검증: 목표 2·3.

## 6. 의사결정 로그

- 2026-09-14: 스킬이 아니라 규칙으로 배포 — 근거: 스킬은 호출 시에만 로드되어 자연어 대화에 자동 적용되지 않는다.
- 2026-09-14: 원본 10개 중 1·3·5·10번만 채택 — 근거: 나머지는 기존 전역 규칙과 중복이거나 추측을 유도한다.
- 2026-09-14: 1주 시험 없이 3곳 동시 설치 — 근거: 사용자 지시.

## 7. 발견·예외

- zeroday-frontend·terminal-shipping 의 `presets.lock` 끝에 프리셋이 아닌 이름(`typescript`, `web`)이 섞여 있다. 쓰는 코드는 찾지 못했다. 재설치 시 lock 은 실존 프리셋만으로 다시 쓰였고, 두 이름은 규칙 세트로서 룰셋 목차에 그대로 남았다(손실 없음).

## 8. 회고 (완료 시 작성)

- 잘된 것: 설치 전에 lock 을 `preset_exists` 기준으로 걸러 `project-claude.sh` 의 Unknown preset 실패를 피했다. 3곳 모두 symlink·목차로 실측 확인했다.
- 잘못된 것: 규칙이 실제 답변 형식을 바꾸는지는 새 세션에서만 관측 가능해 이번 세션에서 검증하지 못했다.
- 다음 룰 후보: 없음. 긴 대화·압축 뒤 규칙이 느슨해지는 것이 관측되면 SessionStart 재주입(C안)을 backlog 로 올린다.
