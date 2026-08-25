# 하네스 문서 갱신 축 — 생성은 강제하되 갱신은 놓치던 구멍 메우기

> 작성일: 2026-08-13
> 목적: 계획 문서가 코드를 따라오게 만드는 감지 축을 신설하고, 죽어 있던 수거 장치를 되살린다.

## 1. 동기 (Why)

하네스는 문서를 **만들게** 하는 장치는 갖췄지만 **갱신하게** 하는 장치가 없다.
아래는 전부 코드에서 확인한 사실이다.

### 1-1. R-plan 은 순환 의존이라 대부분 발동하지 않는다

`assets/hooks/pre-commit.sh:197,204` 의 발동 조건은 두 가지다.

```bash
done < <(filter_files "^${ACTIVE_DIR}/[^/]+\.md$")     # 스테이징된 계획서만
if [[ "$total" -gt 0 && "$total" -eq "$done_count" ]]  # 체크박스 전부 [x]
```

첫 조건이 치명적이다. 계획서를 갱신해 스테이징해야만 검사 대상이 된다 —
"문서를 갱신하지 않는 행동"을 잡으려는 장치가 "갱신했음"을 전제한다.

둘째 조건도 같다. 체크박스 표기는 자발적 행위이고 이를 강제하는 장치가 없다.

이 한계는 `pre-commit.sh:188` 주석에 자백돼 있다.

> 트레이드오프: 아무도 손대지 않은 방치 계획서는 못 잡는다 — 그건 주기 점검(문서 가드닝)의 몫.

2026-07-23 에 워킹트리 공유 시 상호 차단을 피하려 좁힌 결과다. 결정 자체는 타당하다.
문제는 위임받은 쪽이 그 몫을 못 하고 있다는 것이다.

### 1-2. 위임받은 doc-gardening 의 해당 검사는 죽은 코드다

`assets/cron-templates/github-actions/weekly-doc-gardening.yml:49`:

```bash
if grep -qiE '^(status|상태):\s*(done|완료)' "$plan"; then
```

`assets/docs-templates/docs/exec-plans/template.md` 에는 `status:` / `상태:` 필드가 **없다**.
템플릿은 체크박스 기반인데 가드닝은 존재하지 않는 필드를 찾는다.
R-plan 이 포기한 영역을 아무도 보고 있지 않다.

### 1-3. 회고는 아무도 검증하지 않는다

`completed/` 를 검사하는 코드가 없다. §8 이 빈 채로 옮겨도 통과한다.
완료 처리의 실질은 **파일 경로 이동**이고, 회고는 선택 사항이다.

### 1-4. 이 저장소에서는 계획 축 전체가 no-op 이다

두 가지 이유가 겹쳐 있다.

첫째, 코드 판정 필터에 `.sh` 가 없다 (`pre-commit.sh:38`).

```bash
CHECKABLE=$(filter_files '\.(py|js|jsx|ts|tsx|svelte|vue)$')
```

이 저장소의 주력 산출물은 훅 셸 스크립트와 마크다운인데 둘 다 코드로 세지 않는다.

둘째, `pre-commit.sh:208` 이 `-d "$ACTIVE_DIR"` 를 요구하는데
이 저장소에는 `docs/exec-plans/active/` 디렉터리가 **아예 없다**
(`docs/exec-plans/` 에는 `template.md` 하나뿐).
따라서 `.sh` 를 필터에 넣어도 여기서는 여전히 아무것도 돌지 않는다.

### 1-5. 세션 중 갱신을 유도하는 장치가 없다

`claude-userpromptsubmit-reminders.sh:21-35` 는 파일 경로만 나열한다.
본문도, 미완료 단계도, 방치 기간도 주입하지 않는다.

### 1-6. 체크박스 판정에 두 개의 버그가 있다

`pre-commit.sh:193-194`:

```bash
total=$(grep -cE '^\s*-\s*\[' "$plan")       # 총계
done_count=$(grep -cE '^\s*-\s*\[x\]' "$plan")  # 완료
```

**(a) 대소문자.** 완료는 소문자 `[x]` 만 센다. `[X]` 로 체크하면 총계에는 잡히고
완료수에는 안 잡혀 영원히 미완료로 남는다.

**(b) 총계 과다 계수.** `^\s*-\s*\[` 는 체크박스뿐 아니라 **마크다운 링크로 시작하는
불릿**도 센다. 2026-08-13 실측:

```
- [testing.md](testing.md) - 커버리지
- [ ] 목표1
- [x] 목표2
→ 현행 total 3, done 1
```

링크 불릿이 섞인 계획서는 분모가 부풀어 영원히 미완료로 판정된다.

### 1-7. 경고 등급 위반은 사용자에게 보이지 않는다

`pre-commit.sh:219-224`:

```bash
if (( FAIL )); then
  ...
  for v in "${VIOLATIONS[@]}"; do echo "$v"; done
```

`VIOLATIONS` 는 `FAIL=1` 일 때만 출력된다. R-plan-missing(`:207-217`)은 배열에 넣기만
하고 `FAIL` 을 세우지 않으므로, **단독 발생 시 아무 출력 없이 exit 0** 이다.
다른 위반이 동시에 터질 때만 우연히 보인다. 2026-08-13 임시 저장소 실행으로 확인했다.

즉 이 저장소에는 "경고" 라는 등급이 이름만 있고 전달 경로가 없다.

### 축별 현황

| 축 | 강제 장치 | 상태 |
|---|---|---|
| 문서 생성 | R-plan-missing | **무음** (§1-7) |
| 세션 시작 인지 | UserPromptSubmit 경로 나열 | 약함 — 내용 미주입 |
| 진행 중 갱신 | 없음 | **부재** |
| 완료 감지 | R-plan | 순환 의존 + 계수 버그 |
| 방치 계획 수거 | weekly-doc-gardening | **죽은 코드** |
| 회고 품질 | 없음 | **부재** |

## 2. 문제 정의

계획 문서가 코드보다 뒤처져도 아무 신호가 나지 않는다. 계획서는 착수 시점의 스냅샷으로
굳고, 세션 연속성의 원천이라는 본래 역할을 잃는다.

## 3. 설계 결정

### 3.0 지배 원칙

**(a) 판정 규칙은 한 벌만 둔다.** §1-2 의 원인은 판정 로직이 두 벌로 갈라진 것이다.
pre-commit 은 체크박스를 세고 가드닝은 없는 필드를 grep 한다. 아무도 몰랐다.
검사를 더 얹는 이상 이 원칙 없이는 같은 사고가 더 큰 규모로 재발한다.

**(b) 경고로 시작한다.** 새 검사는 전부 경고 등급이다. 차단 승격은 `docs/audits/` 에
오탐 데이터를 쌓은 뒤에 별도 결정으로 한다. 근거는 §3.4-A 참조 — 차단으로 시작하면
2026-07-23 사고를 되살리고 기존 회귀 테스트를 깬다.

**(c) 경고는 반드시 보여야 한다.** §1-7 을 먼저 고치지 않으면 이 설계 전체가 무음이다.

**(d) 실패는 보이는 방향으로 넘어진다.** 판정 불가·모듈 부재·인터프리터 부재는 조용히
통과시키지 않고 그 사실 자체를 출력한다. §1-2 가 오래 방치된 이유가 조용한 실패다.

### 3.1 자동화 강도 — 제안만, 파일은 에이전트가 쓴다

훅은 감지하고 유도할 뿐 문서를 대신 쓰지 않는다.

근거 두 가지. 첫째, `claude-sessionstart-lifecycle-lint.sh:9` 에 명시된 기존 원칙
D4 "겁 많은 자동" — 자동은 dry-run 만. 둘째, 회고를 기계가 생성하면 내용 없는 형식만
남아 §1-3 과 같은 실패가 자동화된 형태로 재발한다.

### 3.2 감지 신호 — 커밋 구성 대조

"코드 파일은 스테이징됐는데 `active/` 계획서는 안 됐다" 를 본다.
§1-1 의 순환 의존을 정확히 뒤집는 신호다.

### 3.3 판정 모듈의 계약

**파일**: `assets/hooks/plan_state.py`
**단일 책임**: 계획서 마크다운의 상태를 판정한다.

역할 경계: **파이썬은 마크다운만 알고, bash 는 git 과 파일시스템을 안다.**
파일 열거는 전부 bash 몫이다. 이 경계 덕분에 모듈은 git 없이 단위 테스트가 가능하다.

#### 서브커맨드

```
plan_state.py is-complete <path>        0=완료  1=미완료  2=판정불가
plan_state.py retro-empty  <path>       0=비었음 1=채워짐  2=판정불가
plan_state.py pending <path> [--max N]  0=성공  2=판정불가, 미완료 항목을 줄 단위 출력
```

`list-complete <dir>` 는 **두지 않는다.** 디렉터리 스캔은 파일시스템 책임이고,
그것을 모듈에 넣으면 `template.md` 제외 규칙이 python 과 bash 두 곳에 생겨
§3.0-(a) 를 계약 안에서 스스로 깬다. 가드닝은 `find` 로 열거하고 파일당 `is-complete` 를 부른다.

#### 종료코드 규율

**모든 서브커맨드는 최상위 `try/except` 로 감싸 예외를 stderr 에 출력하고 exit 2 로 매핑한다.**

이 규율이 없으면 파이썬의 기본 예외 종료코드 1 이 계약을 오염시킨다.
`retro-empty` 에서 1 은 "채워짐(통과)" 이므로, 크래시가 곧 조용한 통과가 된다 —
막으려던 §1-3 이 그대로 일어난다. `is-complete` 는 반대로 1 이 "미완료" 라
같은 크래시가 반대 방향으로 샌다. 이 비대칭을 규율로 없앤다.

#### stdin 을 읽지 않는다

`claude-userpromptsubmit-reminders.sh:23-25` 는 `while read ... done < <(find ...)`
루프 안에서 이 모듈을 부른다. 모듈이 stdin 을 읽으면 find 출력을 삼켜 루프가 깨진다.

#### 판정 규칙

**체크박스**: `^\s*-\s*\[( |x|X)\]\s` 를 항목으로, `[x]`·`[X]` 를 완료로 센다.
완료 = `총계 > 0 이고 총계 == 완료수`.

이 교체는 §1-6 의 **두 버그를 동시에** 고친다. 대소문자와 링크 불릿 오계수 양쪽이다.
그런데 후자는 **분모를 줄이므로** 지금까지 링크 불릿 때문에 미완료로 판정되던 계획서가
완료로 뒤집힌다. R-plan 은 기존 차단 등급이므로 갱신 직후 새 차단이 발생할 수 있다.

**대응**: R-plan 은 이번 변경에서 **경고로 강등하지 않는다**(기존 등급 유지)되,
차단 메시지에 계수 규칙이 바뀌었다는 한 줄을 넣는다. 사용자가 "왜 갑자기" 를 묻지 않게 한다.

**§8 회고**: `^##\s*8[.)]` 로 헤딩을 찾고, 없으면 `^##.*회고` 로 폴백한다.
섹션 범위는 헤딩 다음 줄부터 다음 `^## ` 또는 파일 끝.
"비었음" 은 템플릿 라벨의 콜론 뒤가 전부 공백이고 라벨 외 실질 텍스트가 없을 때로 한정한다.
하나라도 채우면 통과 — 기계가 판단할 수 있는 것은 "쓰지 않았음" 까지다.

**라벨 문자열의 주인**: 라벨(`잘된 것` / `잘못된 것` / `다음 룰 후보`)은
`template.md` 와 모듈 양쪽에 존재한다. 단일 소스로 묶을 방법이 없으므로
(템플릿은 사용자가 편집하는 문서다) **모듈 상단에 라벨 상수를 두고,
`template.md` 변경 시 동반 수정이 필요하다는 주석을 양쪽에 남긴다.**
`tests/plan-state-test.sh` 가 실제 `template.md` 를 입력으로 써서 어긋남을 잡는다.

**template.md 는 모든 판정에서 제외**한다. 호출부(bash)가 경로로 걸러내고,
모듈도 방어적으로 파일명을 확인한다 — 이건 §3.0-(a) 의 예외가 아니라 이중 안전장치다.

#### 파일 크기

`list-complete` 제거로 예상 120 줄 안팎. 전역 100 줄 기준을 넘지만 분할하지 않는다.
배포 단위가 파일 자체이고(설치기가 두 곳에 복사), 쪼개면 복사본이 네 개로 늘어
동기화 실패 지점이 생긴다. 상한 200 줄, 초과 시 설계 재검토.

### 3.4 pre-commit

#### A. 경고 등급으로 시작하는 이유

`tests/harness-hooks-smoke.sh:265-269` 에 이미 이런 회귀 테스트가 있다.

```bash
# 근거: zeroday-frontend docs/audits/2026-07-23-r-plan-hook-scope.md
# (a) fixture 를 스테이징하지 않으면 → 통과해야 한다
echo "x = 1" > small3.py
git add small3.py
assert "미스테이징 완료계획서는 커밋을 막지 않음" "0" "$?"
```

이 fixture 는 **계획서 1 개, 미스테이징, 코드 스테이징** 이다.
"계획서가 있는데 코드만 커밋" 을 차단하는 설계와 정확히 충돌한다.

더 중요한 것은 이 테스트가 지키는 사실이다. 워킹트리 공유 시 상호 차단이 **가장 잘
일어나는 조건이 계획서 1 개** 다. "1 개일 때만 차단하면 안전하다" 는 논리는 뒤집혀 있다 —
저장소가 한산할 때 차단하고 붐빌 때 놓는 규칙이 된다.

따라서 새 검사는 경고로 시작한다. 에이전트는 훅 출력을 읽으므로, §1-7 만 고치면
경고로도 의도한 유도 효과의 대부분을 얻는다.

**차단 승격 경로**: `docs/audits/` 에 오탐 사례를 축적하고, 오탐이 실질적으로
없다고 판단되면 별도 결정으로 승격한다. 이번 범위가 아니다.

#### B. 경고 전달 경로 신설 (§1-7 수정)

`WARNINGS` 배열을 신설하고 `FAIL` 과 무관하게 항상 출력한다.

```bash
if (( ${#WARNINGS[@]} )); then
  echo ""
  echo "── 하네스 경고 (차단 아님) ──"
  for w in "${WARNINGS[@]}"; do echo "$w"; done
fi
if (( FAIL )); then
  ... 기존 차단 출력 ...
fi
```

기존 R-plan-missing 을 `VIOLATIONS` 에서 `WARNINGS` 로 옮긴다.
이 한 가지만으로도 지금까지 무음이던 경고가 되살아난다.

**이것이 나머지 모든 변경의 선행 조건이다.** 이걸 안 고치면 새 검사 전부가 무음이다.

#### C. 신규 변수 WORK_FILES

```bash
# 계획 축 전용. R-size 를 구동하는 CHECKABLE 과 분리한다 —
# 계획의 대상이 되는 "작업 코드"와 줄 수 검사의 대상은 같은 집합이 아니다.
WORK_FILES=$(filter_files '\.(py|js|jsx|ts|tsx|svelte|vue|sh|mjs|go|rs|java|rb|php)$' \
  | grep -vE "$HARNESS_MANAGED_RE" || true)
```

**`.sh` 추가가 이번 변경의 실질이다**(§1-4).

**하네스 생성물 제외가 필수다.** `install_harness_hooks`(`harness_installers.sh:41-49`)는
`scripts/hooks/*.sh` 를 매 설치마다 덮어쓰고, 이 경로는 git 추적 대상이다.
제외하지 않으면 `update-all.sh` 직후의 하네스 갱신 커밋 자체가 경고 대상이 된다.

같은 실패가 이미 발생한 적이 있다. `pre-commit.sh:42-48`:

> 맞추려 들면 재설치할 때마다 **자기 게이트에 자기가 걸려 커밋이 막힌다(실제로 3개 프로젝트에서 발생).**

```bash
HARNESS_MANAGED_RE='^scripts/(hooks|codex-hooks)/'
```

**확장자 목록의 범위**: 이 목록은 "계획을 세울 만한 작업 코드" 의 근사치이지 완전한
집합이 아니다. `.md` 는 의도적 제외다(문서 수정마다 계획서를 요구하면 오탈자 하나에도
걸려 우회가 상시화된다). yaml/json/tf/sql 등은 **이번 범위에서 다루지 않는다**(§4).
목록 확장은 오탐 데이터를 본 뒤의 별도 결정이다.

`CHECKABLE` 은 건드리지 않는다. `.sh` 를 넣으면 R-size 의 의미까지 바뀐다.

#### D. 검사 1 — R-plan (기존 차단 등급 유지, 판정만 위임)

범위는 그대로(스테이징된 `active/*.md`). 인라인 grep 두 줄을
`plan_state.py is-complete` 호출로 교체한다. §1-6 두 버그가 함께 사라진다.
계수 규칙 변경 안내를 메시지에 추가한다(§3.3).

#### E. 검사 2 — R-plan-stale (신규, 경고)

```
WORK_FILES 있음 && docs/exec-plans/active 존재
  ├─ 계획서 0개                    → [R-plan-missing] 경고 (기존, WARNINGS 로 이동)
  └─ 계획서 N개, 하나도 미스테이징 → [R-plan-stale] 경고 + 목록
```

경고 등급이므로 "1 개 / 여럿" 분기가 불필요하다 — 모호해도 알리기만 하면 되고,
차단이 없으니 상호 차단 위험도 없다. 설계가 크게 단순해진다.

**일부만 스테이징된 경우는 통과**시킨다. 어느 계획에 속한 커밋인지 훅은 알 수 없고,
경고를 남발하면 §1-7 을 고쳐 되살린 경고 채널이 다시 무시된다.

```
[R-plan-stale] 코드는 바뀌었는데 계획서가 따라오지 않음 (경고, 차단 아님)
  active/: docs/exec-plans/active/2026-08-13-foo.md
  → 진행분을 계획서에 반영하십시오 (§2 체크박스, §6 의사결정 로그, §7 발견).
     신규 계획서라면 git add 가 필요합니다.
  근거: docs/design-docs/core-beliefs.md#r-plan-stale
```

`HARNESS_PLAN_SKIP` 같은 탈출구는 **두지 않는다.** 경고 등급에는 탈출할 대상이 없다.
차단 승격 시점에 함께 설계한다.

#### F. 검사 3 — R-retro (신규, 경고)

`completed/` 로 **이동한** 계획서의 §8 이 비어 있으면 경고한다.

```bash
git diff --cached --name-only --diff-filter=RA -- docs/exec-plans/completed/
```

**`M`(수정)을 뺀 이유**: 넣으면 옛 계획서의 오타 수정도 걸린다. 그 사람은 자기가 하지도
않은 작업의 회고를 지어내야 한다. 이 검사의 근거는 "`completed/` 로 **옮기는** 행위가
완료 선언" 이므로 `R`(rename)과 `A`(신규 생성)로 한정하는 것이 근거와 정확히 일치한다.

**`filter_files` 를 쓸 수 없다.** `pre-commit.sh:19` 의 `STAGED` 는 `--diff-filter=ACM`
인데 `git mv` 는 `R100` 으로 분류돼 이 필터에 잡히지 않는다. 2026-08-13 실측:
ACM 은 빈 출력, `--name-status` 는 `R100`, `ACMR` 은 목적지 경로 출력.
`STAGED` 자체에 `R` 을 추가하지 않는 이유는 다른 모든 검사의 범위가 함께 바뀌기 때문이다.

```
[R-retro] 회고 없이 완료 처리됨 (경고, 차단 아님)
  docs/exec-plans/completed/2026-08-13-foo.md
  → §8 세 항목(잘된 것 / 잘못된 것 / 다음 룰 후보) 중 최소 하나를 채우십시오.
  근거: docs/design-docs/core-beliefs.md#r-retro
```

#### G. 종료코드 처리 표

세 값을 만들었으므로 호출부별 처리를 명시한다. **exit 2 는 조용히 통과시키지 않는다.**

| 호출부 | exit 0 | exit 1 | exit 2 |
|---|---|---|---|
| R-plan (`is-complete`) | 차단 | 통과 | **경고**: 판정불가 |
| R-retro (`retro-empty`) | 경고 | 통과 | **경고**: 판정불가 |
| UserPromptSubmit (`pending`) | 출력 | — | 경로만 출력 + 사유 1줄 |
| 가드닝 (`is-complete`) | 리포트 | 통과 | 리포트에 판정불가 기록 |
| 가드닝 (`retro-empty`) | 리포트 | 통과 | 리포트에 판정불가 기록 |

#### H. 모듈 부재 시

`[[ -f ]] && command -v python3` 로 가드하되, **두 원인을 구분해** 경고한다.

```
[R-plan] 계획 축 검사 3개를 건너뜀 — plan_state.py 없음 (재설치 필요)
[R-plan] 계획 축 검사 3개를 건너뜀 — python3 없음 (인터프리터 설치 필요)
```

원인을 뭉뚱그리면 사용자가 재설치를 반복해도 해결되지 않는 삽질을 한다.

### 3.5 UserPromptSubmit — 미완료 단계 주입

Active Plans 블록을 경로 나열에서 미완료 항목 출력으로 바꾼다.

```
--- [Active Plans] ---
docs/exec-plans/active/2026-08-13-doc-update-axis.md
  [ ] plan_state.py 판정 모듈 — 검증: tests/plan-state-test.sh
  [ ] WARNINGS 출력로 신설 — 검증: 단독 경고가 실제로 출력되는가
  [ ] 가드닝 status 필드 제거 — 검증: 완료 계획이 리포트에 뜨는가
```

**실패 시 동작**: 이 훅의 출력은 매 턴 컨텍스트에 주입되므로 트레이스백이 새면
모델 입력이 오염된다. 그렇다고 기존 hermes 블록처럼 `2>/dev/null || true`(`:76`)로
전부 삼키면 §3.0-(d) 를 어긴다. **stderr 는 버리되, 실패 시 경로와 사유 한 줄을
stdout 에 남긴다.**

```
docs/exec-plans/active/2026-08-13-foo.md  (미완료 항목 추출 실패 — 파일을 직접 확인하십시오)
```

**경로 참조**: 이 훅은 `cd` 가 실패해도 `|| true` 로 진행한다(`:14`).
상대 경로 대신 기존 hermes 블록 패턴(`:57`)처럼 `$(dirname "$0")` 기반으로 해석한다.
`tests/harness-hooks-smoke.sh:171-178` 이 CWD 미설정 케이스를 이미 회귀 고정하고 있다.

**상한**: 계획서당 미완료 3 개, 본문 표시는 계획서 3 개까지, 초과분은 경로만.
근거는 이 출력이 매 턴 프롬프트에 붙어 비용이 턴 수에 비례한다는 점이다.
템플릿 §2 는 목표 2 개로 시작해 실무상 3~7 개로 늘어나는데, 앞의 3 개면 현재 전선을
보여주기 충분하고 그 이상은 파일을 열게 하는 편이 옳다.

**기본값의 주인은 모듈 한 곳**이다. 숫자 리터럴은 `plan_state.py` 에만 두고,
bash 는 `HARNESS_PLAN_PENDING_MAX` 가 설정된 경우에만 `--max` 를 전달한다.

**프로세스 기동 비용**: 이 훅은 이미 python3 를 3 회 기동한다(`:62,70,73`).
계획서당 1 회가 더 붙어 최대 3 회 증가한다. 상한 3 이 이 비용의 근거이기도 하다.

Backlog 블록은 그대로 둔다 — 미착수 항목에 미완료 단계를 보여줄 의미가 없다.

### 3.6 weekly-doc-gardening 수리

죽은 `status:` grep(`:49`)을 걷어내고 두 가지를 본다.

```
find docs/exec-plans/active -name '*.md' ! -name 'template.md' → is-complete
  → [plan-graduation] 완료 상태인데 active/ 에 남아 있음
find docs/exec-plans/completed -name '*.md' → retro-empty
  → [plan-noretro] 회고 없이 completed/ 에 들어가 있음
```

두 번째가 새로 생긴다. R-retro 는 앞으로의 이동만 잡으므로, 이미 회고 없이 옮겨진
과거 계획서는 가드닝이 수거해야 한다.

**스캔 범위를 좁힌다.** 현재는 `find docs/exec-plans`(`:52`)로 `completed/` 와
`backlog/` 까지 훑어 정상 완료된 계획서마저 후보로 잡을 구조였다.

**목적지 문구를 통일한다.** 가드닝은 `docs/audits/` 로 옮기라 하고(`:50`),
R-plan 과 CLAUDE.md 규칙은 `completed/` 라 한다(`pre-commit.sh:200`,
`presets/workflow/harness.conf:131,137`). `completed/` 로 맞춘다.

**기존 부채**: `[plan-noretro]` 는 매주 `completed/` 전량을 나열한다. 목록이 길면
그 자체가 부채 신호다. 상태를 저장해 "새로 생긴 것만" 보고하는 방식은 쓰지 않는다 —
상태 파일이 또 하나의 동기화 지점이 되고, 일괄 백필은 사람의 결정 사항이다.

**모듈 부재 시 리포트에 기록**한다. 조용히 건너뛰지 않는 것이 중요하다 —
이 검사가 죽어 있었는데 아무도 몰랐던 이유가 정확히 그것이다.

**도그푸딩 불가 주의**: 이 저장소에는 `scripts/hooks/` 도 `weekly-doc-gardening.yml` 도
없다(`.github/workflows/` 에 `ci.yml` 하나뿐). 이 수리는 다운스트림에서만 관측 가능하므로
§3.9 의 yml 실행 테스트가 유일한 검증 수단이다.

### 3.7 배포 — 버전 마커 도입

현재 설치기의 덮어쓰기 정책은 자산마다 다르다.

| 자산 | 현행 정책 | 근거 |
|---|---|---|
| `.git/hooks/pre-commit` | 무조건 덮어씀 | `harness_installers.sh:67` |
| `scripts/hooks/*.sh` | 무조건 덮어씀 | `:46` |
| `weekly-doc-gardening.yml` | 기존 보존 | `:190-195` |
| `core-beliefs.md` | 기존 보존 | `:129-131` |

그대로 두면 **경고하는 세 검사는 즉시 전 프로젝트에 배포되고, 그것을 보완할 수거
장치와 링크 대상은 영원히 배포되지 않는다.** 설계의 안전 논리가 배포 단계에서 무너진다.

#### (a) 워크플로 — 내용 해시 마커

템플릿 첫머리에 마커를 넣는다.

```yaml
# harness-template-sha: <설치 시 계산된 템플릿 본문 해시>
```

설치기 판정:

| dest 상태 | 동작 |
|---|---|
| 없음 | 신규 배치 |
| 마커 있음 + dest 본문 해시 == dest 마커 | 사용자 미수정 → **덮어씀** |
| 마커 있음 + 해시 불일치 | 사용자 수정 → 보존 + 경고 |
| 마커 없음 (구버전) | 보존 + "수동 갱신 필요" 경고 |

`uninstall_gc_workflows`(`uninstall_helpers.sh:213`)의 `cmp -s` 정신과 같되,
템플릿이 개정돼도 판정이 유지된다는 점이 다르다.

#### (b) core-beliefs — 마커 블록

이미 저장소에 두 선례가 있다. `install_harness_gitignore`(`harness_installers.sh:225-226`)의
"마커 사이만 교체, 마커 밖 사용자 항목은 보존" 방식과, 마크다운에 직접 적용된
`assets/docs-templates/CLAUDE.md.tmpl` 의 `<!--===DS:BEGIN===-->` / `<!--===DS:END===-->` 블록이다.
후자를 따른다 — 대상이 마크다운이므로 HTML 주석이 맞다.

```markdown
<!--===HARNESS-RULES:BEGIN===-->
(하네스가 강제하는 룰의 앵커. 재설치 시 이 블록만 덮어쓴다.)
<!--===HARNESS-RULES:END===-->
```

블록 안쪽만 갱신하고 프로젝트 고유 룰(R1~Rn)은 손대지 않는다. 블록이 없으면 파일 끝에 추가한다.

#### (c) plan_state.py 배치와 회수

- `.git/hooks/plan_state.py` — pre-commit 이 `$(dirname "$0")` 로 참조
  (`check-secrets.py` 와 동일 패턴, `pre-commit.sh:169-171`)
- `scripts/hooks/plan_state.py` — UserPromptSubmit 훅과 CI 체크아웃이 참조

**`hook_inventory.sh:31` 확장이 필수다.** 현재 `*.sh` 와 `*.json` 만 스캔하므로
`.py` 는 목록에 들어가지 않고, `_cleanup_stale_hooks`(`harness_installers.sh:21-27`)가
순회하지 못해 harness 프리셋이 빠진 프로젝트에 **영구히 남는다**.
`hook_inventory.sh:11-14` 주석이 정확히 이 함정을 경고하고 있다.
이 확장은 `lib/generate_settings_json.py:154` 와 `uninstall_settings_hooks` 에도
영향을 주므로 구현 시 함께 확인한다.

**`cp` 실패를 확인한다.** `lib/harness_installers.sh` 에는 `set -e` 가 없고 각 `cp`(`:46,67,74,82,93`)의
성공 여부를 보지 않아, 실패해도 `log_info "hook → ..."` 가 그대로 찍힌다.
새로 추가하는 두 복사는 실패 시 `log_warn` 을 낸다.

**CI 첫 실행 노이즈**: 설치기는 파일을 만들 뿐 커밋하지 않으므로, 신규 설치 직후
첫 주간 실행은 "plan_state.py 없음" 을 리포트한다. 워크플로 배치 로그에
"`scripts/hooks/plan_state.py` 를 커밋해야 주간 점검이 동작합니다" 안내를 추가한다.

### 3.8 룰 앵커

이 저장소의 `docs/design-docs/core-beliefs.md` 에는 `{#r-size}`(`:15`), `{#r-fmt}`(`:28`),
`{#r-lint}`(`:32`), `{#r-test}`(`:36`), `{#r-plan}`(`:51`), `{#r-plan-missing}`(`:58`)이
**전부 존재한다.** dead link 는 빈 템플릿을 받은 설치 프로젝트에서만 발생한다.
§3.7-(b) 의 마커 블록이 이 절반을 해소한다.

추가할 앵커: `{#r-plan-stale}`, `{#r-retro}` — 이 저장소와 템플릿 블록 양쪽.

### 3.9 배포 경로 검증 (setup.sh / update-all.sh)

2026-08-13 실측으로 확인한 전파 경로와, 이 설계가 추가로 정해야 할 것들이다.

#### 확인된 전파 경로

`setup.sh` 는 대화형 프리셋 선택 UI 이고 실제 설치는 `project-claude.sh` 가 한다.
선택 결과는 `.claude/presets.lock` 에 기록된다. `update-all.sh` 는
`.installed-projects` 레지스트리(현재 11 개 등록)를 순회하며 각 프로젝트의 lock 을 읽어
같은 프리셋으로 `project-claude.sh` 를 재실행한다(`update-all.sh:126-129`).

`scripts/hooks/*` 와 `.git/hooks/pre-commit` 은 무조건 덮어쓰므로(`harness_installers.sh:46,67`),
§3.4·§3.5 변경은 `update-all.sh` 한 번으로 전 프로젝트에 도달한다.
§3.6·§3.8 은 도달하지 않는다 — 그래서 §3.7 의 마커가 필요하다.

#### 배포 메커니즘 확정

`plan_state.py` 는 **`presets/workflow/harness.conf:55` 의 `HARNESS_HOOK_SOURCES` 에 등록한다.**

`scripts/hooks/` 로의 복사는 `install_harness_hooks`(`harness_installers.sh:34-48`)가
이 배열만 처리하므로 다른 경로가 없다. 별도 `cp` 를 짜면 `_cleanup_stale_hooks`(`:14-28`)의
관리 대상에서 빠져 프리셋 제거 시 회수되지 않는다.

이 배열은 **파일 복사만** 담당하고 훅 등록은 별도 배열(`USER_PROMPT_SUBMIT_HOOKS`,
`PRE_TOOL_USE_HOOKS` 등)이 하므로, `.py` 를 넣어도 실행 훅으로 오등록되지 않는다.

`.git/hooks/plan_state.py` 는 `install_harness_pre_commit` 안에서 복사한다
(`HARNESS_PRE_COMMIT` 게이트). 두 플래그 모두 `harness.conf` 단독으로 켜지므로
(다른 프리셋은 `HARNESS_HOOK_SOURCES` 에만 항목을 추가한다) 반쪽 설치는 발생하지 않는다.

#### hook_inventory `.py` 확장의 부작용

`harness_hook_inventory`(`hook_inventory.sh:31`)에 `*.py` 를 추가하면
`assets/hooks/check-secrets.py` 도 인벤토리에 들어간다. 이 파일은
`HARNESS_HOOK_SOURCES` 에 없으므로 `_cleanup_stale_hooks` 가
`scripts/hooks/check-secrets.py` 삭제를 시도한다.

실제로 그 경로에는 파일이 없어(`.git/hooks/` 로 간다) `[[ -f ]]` 가드에 걸려 무해하지만,
**회귀 테스트로 고정한다** — 인벤토리 확장이 기존 자산을 지우지 않음을 단언한다.

#### presets.lock 부재 프로젝트

`update-all.sh:117-124` 는 lock 이 없거나 비면 프로젝트를 통째로 스킵한다.

```
⚠ presets.lock 없음 또는 빈 파일 — 스킵
```

이런 프로젝트에는 이 설계의 어떤 변경도 도달하지 않는다. 사용자가 `setup.sh` 를 다시
돌려야 한다. **이 설계에서 해결하지 않는다**(§4) — 계획 축에 국한된 문제가 아니라
레지스트리 전반의 성질이다. 다만 릴리스 노트에 명시한다.

### 3.9-bis 도그푸딩 — 이 저장소는 자기 자신에 설치되어 있지 않다

`.installed-projects` 에 `claude-harness-hermes` 가 **없고** `.claude/presets.lock` 도 없다
(`.claude/` 에는 `settings.json`, `settings.local.json`, `skills/` 뿐).

따라서 이 저장소에는 pre-commit 도, `scripts/hooks/` 도, 가드닝 워크플로도 없다.
`docs/exec-plans/active/` 를 만드는 것만으로는 검증 경로가 생기지 않는다 —
훅 자체가 설치돼 있지 않기 때문이다.

**선택지는 둘이다.**

- **(A) 자기 설치.** 이 저장소에 harness 프리셋을 설치한다. 계획 축이 실제로 동작하는지
  일상 작업에서 관측되고, §3.6 가드닝도 다운스트림 대기 없이 검증된다.
  대신 이 저장소의 커밋 흐름 전체가 pre-commit 4 단 검사 아래로 들어간다.
- **(B) 임시 프로젝트 검증만.** 현행 유지. §3.10 테스트가 유일한 안전망이 된다.

용어를 정확히 해 둔다. 기존 테스트는 "모의" 가 아니다. `harness-hooks-smoke.sh:49`,
`windows-smoke.sh:49,100`, `uninstall-roundtrip-test.sh:47` 은 전부 임시 프로젝트에
**진짜 설치기**(`project-claude.sh <path> harness`)를 돌린다. 가짜인 것은 프로젝트 내용뿐이고
설치기·훅·git 은 실물이다. (B) 가 포기하는 것은 "실물 설치" 가 아니라
**"이 저장소의 일상 작업에서 관측하는 것"** 이다.

**결정: (B).** 저장소 운영 방식을 바꾸지 않는다.

> **2026-08-25 결정 변경 — (A) 자기 설치로 전환.** 사용자 승인으로 이 저장소에
> harness 프리셋을 설치했다. 계기는 2026-08-24~25 에 게이트 7개(`R-iface`·`R-cx`·`R-cov`·
> `R-mut`·`R-dep`·`R-pipe`·`R-acc`)를 추가하면서, **그 게이트들이 정작 이 저장소의
> 커밋에는 걸리지 않는다**는 사실이 계속 걸렸기 때문이다.
>
> 전환은 **즉시 결함 세 건을 드러냈다** — (B) 아래에서는 아무도 몰랐을 것들이다.
>
> | 결함 | 내용 |
> |---|---|
> | `complexity.py` 가 `R-cx` 위반 | `_main()` 복잡도 15 > 한도 11. **자기가 강제하는 룰을 자기가 어겼다** |
> | `depcheck.py` 가 `R-cx` 위반 | `_check()` 23, `collect_imports()` 18 |
> | 하네스 룰 블록이 앵커를 중복 선언 | 대상 문서가 이미 정식 섹션을 가지면 `{#r-test}` 가 두 번 선언돼 `근거:` 링크가 모호해진다 |
>
> 앞의 둘은 리팩터링으로 고쳤고(15→10, 23·18→8·10 이하), 셋째는 설치기가
> **이미 있는 앵커면 선언 대신 링크**하도록 고쳤다(`tests/harness-hooks-smoke.sh` 1d-bis 가 고정).
>
> 500줄 초과 파일 2개(`assets/skills/continuous-learning-v2/scripts/`)는 외부 도입분이며
> 2026-07-01 이후 수정된 적이 없다. `R-size` 는 스테이징된 파일만 보므로 건드리지 않는 한
> 막지 않는다 — 예외를 만들지 않고 그대로 둔다.
>
> §3.10 테스트는 더 이상 "유일한 안전망" 이 아니다. 다만 여전히 필요하다:
> 자기 설치는 **이 저장소의** 커밋만 검증하고, 설치기가 다른 프로젝트에서 하는 일은
> 임시 프로젝트 테스트만이 확인한다.

따라서 §3.10 의 테스트가 **유일한 안전망**이다. 두 가지가 따라온다.

1. `tests/harness-hooks-smoke.sh` 케이스는 "있으면 좋은 것" 이 아니라 이 설계의 유일한
   검증 수단이다. 경고 문자열 단언을 빠뜨리면 §1-7 을 실제로 고쳤는지 알 방법이 없다.
2. §3.6 가드닝 수리는 이 저장소에서 관측되지 않는다. yml 스크립트 본문을 추출해
   픽스처 저장소에서 실행하는 테스트가 없으면, §1-2 와 똑같이 "고쳤다고 믿지만 죽어 있는"
   상태가 재발한다. 이 테스트는 선택 사항이 아니다.

### 3.10 테스트

#### `tests/plan-state-test.sh` (신규, TDD)

| 케이스 | 기대 |
|---|---|
| 체크박스 전부 `[x]` | is-complete 0 |
| 대문자 `[X]` 혼용 | is-complete 0 (§1-6a 회귀) |
| 링크 불릿 `- [x.md](x.md)` 섞임 | 총계에서 제외 (§1-6b 회귀) |
| 체크박스 0 개 | is-complete 1 |
| §8 라벨만, 콜론 뒤 공백 | retro-empty 0 |
| §8 세 항목 중 하나만 채움 | retro-empty 1 |
| §8 헤딩 없음 | retro-empty 0 |
| 실제 `template.md` 입력 | 라벨 상수가 템플릿과 일치 (어긋남 감지) |
| 깨진 인코딩 / 비정상 마크다운 | **exit 2** (1 로 새지 않음) |
| 존재하지 않는 경로 | **exit 2** |
| 미완료 5 개, `--max 3` | 3 줄 출력 |
| stdin 에 데이터를 주고 실행 | 소비하지 않음 |

#### `tests/harness-hooks-smoke.sh` (케이스 추가)

기존 관례대로 **exit code 뿐 아니라 메시지 문자열을 `grep -q` 로 단언**한다.
이 스위트가 존재하는 이유가 "조용한 skip 을 잡는 것" 이므로(`:4-8`), 경고 케이스에
문자열 단언이 없으면 §1-7 을 고쳤는지 확인할 수 없다.

| 케이스 | 기대 |
|---|---|
| 경고만 발생 (다른 위반 없음) | exit 0 **+ 경고 문자열 출력** (§1-7 회귀) |
| 계획서 있음 + 미스테이징 + 코드 | exit 0 + `[R-plan-stale]` 출력 |
| 계획서 2 개 중 1 개만 스테이징 | exit 0 + 경고 없음 |
| `git mv` 로 회고 빈 계획 이동 | exit 0 + `[R-retro]` 출력 (rename 회귀) |
| `completed/` 파일 내용만 수정 | 경고 없음 (`M` 제외 회귀) |
| `scripts/hooks/*.sh` 만 수정 | 경고 없음 (자기 게이트 회귀, `:347-364` 패턴) |
| plan_state.py 부재 | exit 0 + "plan_state.py 없음" 출력 |
| python3 부재 (PATH 조작) | exit 0 + "python3 없음" 출력 |
| 기존 케이스 13(a) | **변경 없이 통과** |

#### `tests/update-all-roundtrip-test.sh` (신규)

**§3.7 버전 마커 판정을 검증하는 유일한 수단이다.**

현재 `setup.sh` 와 `update-all.sh` 를 도는 테스트는 **하나도 없다**(2026-08-13 확인).
기존 4 개 테스트는 전부 `project-claude.sh` 를 직접 호출한다. 그런데 마커 판정
("마커 있고 해시 일치 → 덮어씀, 불일치 → 보존")은 **재실행 경로에서만 발동한다** —
신규 설치에서는 파일이 없어 무조건 배치되므로 판정 자체가 일어나지 않는다.
즉 §3.7 의 배포 안전 논리 전체가 현재 무검증 구간에 놓여 있다.

`setup.sh` 는 대상에서 뺀다. `read -rp`(`:199,350`)와 카테고리 선택 UI 때문에 stdin
주입이 필요하고 UI 문구 변경에 취약하다. 그리고 `setup.sh` 고유 리스크는 `presets.lock`
기록뿐인데, 그 경로는 아래 테스트가 lock 을 읽어 쓰면서 간접 검증된다.
`update-all.sh` 는 완전 비대화(`--target` 플래그뿐)라 자동화 비용이 낮다.

| 시나리오 | 기대 |
|---|---|
| 사용자 미수정 워크플로 + 템플릿 개정 | **덮어써짐** |
| 사용자 수정 워크플로 + 템플릿 개정 | **보존 + 경고 출력** |
| 마커 없는 구버전 워크플로 | 보존 + "수동 갱신 필요" 경고 |
| core-beliefs 마커 블록 밖에 사용자 룰 존재 | 블록 안만 갱신, 사용자 룰 보존 |
| `presets.lock` 삭제 | 스킵 + 스킵 사유 출력 (`update-all.sh:117-124`) |
| 레지스트리 경로가 사라진 경우 | 스킵 + stale 처리 |

**격리 요구**: 템플릿 개정을 흉내 내려면 `assets/` 를 변조해야 한다. 저장소를 오염시키지
않도록 원본을 백업하고 `trap` 으로 복원한다. 레지스트리 원복은 기존 테스트 패턴
(`harness-hooks-smoke.sh:22-30`)을 그대로 따른다.

#### 가드닝 yml (신규 검증)

§1-2 가 오래 방치된 파일이므로 자동 검증이 필요하다. yml 의 `Detect drift` 스크립트
본문을 추출해 픽스처 저장소에서 실행하고, `[plan-graduation]` 과 `[plan-noretro]` 가
실제로 리포트에 찍히는지 단언한다.

### 3.11 인수 검증 — 단계적 전파

자동 테스트는 **적어 둔 케이스만** 잡는다. 실제 전파는 **적지 못한 케이스**를 잡는다.
둘은 대체재가 아니라 순서다. §1-2 의 죽은 가드닝이 그 증거다 — 최초에 누가 전파해
확인했더라도, 그 뒤 템플릿이 바뀌며 어긋난 것을 잡을 회귀 그물이 없었다.

**전파 순서**

1. `bash tests/run-all.sh` 통과
2. **실제 프로젝트 1 개에 수동 전파** — `project-claude.sh <경로> harness` 실행 후 육안 확인
3. 이상 없으면 `update-all.sh` 로 나머지 전파

**2 단계 확인 항목**

- [ ] `scripts/hooks/plan_state.py` 와 `.git/hooks/plan_state.py` 가 둘 다 배치됐는가
- [ ] 코드를 고쳐 커밋했을 때 `[R-plan-stale]` 경고가 **실제로 출력**되는가 (§1-7 회귀)
- [ ] 다른 위반이 없는 상태에서 경고 단독으로 보이는가
- [ ] `scripts/hooks/*.sh` 만 바뀐 재설치 직후 커밋에 경고가 뜨지 않는가 (§3.4-C 회귀)
- [ ] UserPromptSubmit 에 미완료 항목이 주입되는가, 매 턴 출력량이 감당 가능한가
- [ ] 기존 워크플로가 있던 프로젝트에서 마커 판정이 의도대로 동작했는가 (§3.7)
- [ ] `.git/hooks/pre-commit` 실행 시간이 체감상 늘지 않았는가 (python 기동 추가분)

**전파 위험도**: 새 검사가 전부 경고 등급이므로(§3.0-b) 최악의 경우가 "불필요한 메시지"
다. 초안의 차단 설계였다면 잘못된 전파가 11 개 프로젝트의 커밋을 막았을 것이다.
경고로 강등한 결정이 전파 검증의 안전 여유도 함께 만들었다.

## 4. 비목표 — 지금 하지 않는 것

- **차단.** 새 검사 셋 다 경고다. 승격은 오탐 데이터를 본 뒤 별도 결정.
- **회고 품질 판정.** 기계는 "쓰지 않았음" 까지만 본다.
- **문서 자동 생성·자동 이동.** §3.1.
- **`.md` 를 작업 코드로 취급.**
- **yaml/json/tf/sql 등 확장자 목록 확장.** §3.4-C.
- **`CHECKABLE` / R-size 범위 변경.**
- **기존 `completed/` 회고 일괄 백필.** 가드닝이 목록을 낼 뿐, 처리는 사람이 결정.
- **헤르메스 SQLite 연동.**
- **시간 기반 stale 판정.** 임계값의 근거를 세울 수 없다.
- **`presets.lock` 부재 프로젝트 구제.** 레지스트리 전반의 성질이지 계획 축의 문제가
  아니다. 릴리스 노트에 명시만 한다(§3.9).
- ~~**이 저장소의 자기 설치 결정.**~~ — **2026-08-25 승인·완료.** (A) 로 전환했다(§3.9-bis).

## 5. 기존 자산과의 관계

| 자산 | 변경 |
|---|---|
| `assets/hooks/pre-commit.sh` | WARNINGS 출력로 신설, R-plan 위임, R-plan-stale·R-retro 신설, WORK_FILES 신설 |
| `assets/hooks/plan_state.py` | 신규 |
| `assets/hooks/claude-userpromptsubmit-reminders.sh` | Active Plans 블록 개편 |
| `assets/cron-templates/*/weekly-doc-gardening.*` | status grep 제거, 두 검사로 교체, 마커 추가 |
| `assets/docs-templates/docs/design-docs/core-beliefs.md.tmpl` | 하네스 룰 마커 블록 추가 |
| `lib/harness_installers.sh` | plan_state.py 이중 배치, 워크플로 해시 마커 판정, core-beliefs 마커 블록 |
| `presets/workflow/harness.conf` | `HARNESS_HOOK_SOURCES` 에 `plan_state.py` 등록 |
| `lib/hook_inventory.sh` | `.py` 스캔 추가 (기존 `.py` 자산 오삭제 회귀 테스트 동반) |
| `lib/uninstall_helpers.sh` | 대응 제거 |
| `docs/design-docs/core-beliefs.md` | R-plan-stale·R-retro 추가 |
| `docs/exec-plans/active/` | 신규 (도그푸딩) |
| `tests/plan-state-test.sh` | 신규 |
| `tests/update-all-roundtrip-test.sh` | 신규 (§3.7 마커 판정 검증) |
| `tests/harness-hooks-smoke.sh` | 케이스 추가 |
| `tests/run-all.sh` | 신규 테스트 2 개 등록 |

`assets/codex/hooks/codex-userpromptsubmit-reminders.sh:9` 도 동일한 Active Plans 블록을
갖는다. Codex 쪽 동기화 여부는 구현 시 확인한다.

## 6. 개정 이력

- 2026-08-13 (초안): 최초 작성.
- 2026-08-13 (개정 1): architect·silent-failure-hunter 리뷰 반영.
  - 새 검사를 **차단에서 경고로 강등**. 근거: `harness-hooks-smoke.sh:265-269` 회귀
    테스트와 정면 충돌하며, "계획서 1 개일 때만 차단" 논리가 2026-07-23 상호 차단
    사고 조건과 일치함.
  - §1-7(경고 무음) 발견 추가. WARNINGS 출력로를 선행 조건으로 신설.
  - §1-6b(링크 불릿 총계 과다) 발견 추가. 정규식 교체가 분모를 바꾼다는 사실 명시.
  - R-retro 를 `ACMR` → `RA` 로 축소. `M` 포함 시 레거시 오타 수정까지 차단됨.
  - 모든 서브커맨드에 예외 → exit 2 규율 명문화. exit 2 처리 표 추가.
  - `list-complete` 제거 — 디렉터리 스캔이 §3.0-(a) 를 계약 안에서 깨뜨림.
  - WORK_FILES 에 하네스 생성물 제외 추가. 미추가 시 자기 게이트에 걸림.
  - §3.7 배포 버전 마커 신설. 미도입 시 경고만 배포되고 수거 장치는 배포 안 됨.
  - `hook_inventory.sh` `.py` 확장 추가. 미추가 시 언인스톨에서 파일이 영구 잔존.
  - `HARNESS_PLAN_SKIP` 제거 — 경고 등급에는 탈출구가 불필요.
  - §3.8 사실 정정: 이 저장소의 룰 앵커는 전부 존재함. dead link 는 설치 프로젝트 한정.
  - §1-4 보완: `.sh` 누락 외에 `active/` 디렉터리 부재도 원인.
- 2026-08-13 (개정 2): setup.sh / update-all.sh 전파 경로 실측 검증.
  - §3.9 신설. `plan_state.py` 배포는 `HARNESS_HOOK_SOURCES` 등록으로 확정 —
    별도 `cp` 는 `_cleanup_stale_hooks` 관리 대상에서 빠져 회수 불가.
  - `hook_inventory.sh` `.py` 확장이 `check-secrets.py` 를 인벤토리에 넣는 부작용 발견.
    무해하나 회귀 테스트로 고정.
  - `presets.lock` 부재 프로젝트는 `update-all.sh:117-124` 에서 스킵됨을 확인. 비목표로 명시.
  - §3.9-bis 신설. **이 저장소는 자기 자신에 설치되어 있지 않다**(레지스트리·lock 부재).
    초안의 "active/ 를 만들면 도그푸딩" 전제가 성립하지 않음. 자기 설치 여부는 별도 승인 사항.
- 2026-08-13 (개정 3): 테스트 커버리지 공백 발견.
  - **`setup.sh` / `update-all.sh` 를 도는 테스트가 하나도 없음**을 확인. 기존 4 개는
    전부 `project-claude.sh` 직접 호출. §3.7 마커 판정은 재실행 경로에서만 발동하므로
    설계의 배포 안전 논리 전체가 무검증 구간에 있었음.
  - `tests/update-all-roundtrip-test.sh` 신설. `setup.sh` 는 대화형이라 제외하고
    `update-all.sh` 로 한정 — lock 을 읽어 쓰므로 `presets.lock` 경로도 간접 검증됨.
  - §3.9-bis 용어 정정: 기존 테스트는 "모의" 가 아니라 임시 프로젝트에 진짜 설치기를
    돌린다. (B) 가 포기하는 것은 실물 설치가 아니라 일상 작업에서의 관측이다.
- 2026-08-13 (개정 7): 전파 후 발견 — 가드닝 축이 어디서도 실행되지 않았다.
  - **CI 진입점 부재.** 9개 GitLab 프로젝트 전부에 `.gitlab-ci.yml` 이 **없다**.
    GitLab 은 `.gitlab/` 를 자동 발견하지 않으므로 include 없이는 job 이 존재만 한다.
    게다가 job 은 `rules: if $CI_PIPELINE_SOURCE == "schedule"` 라 웹 UI 스케줄 등록도
    필요하다 — 설치기가 끝까지 배선할 수 없는 구조다.
    GitHub 판은 `on: schedule` 자기 선언이라 파일만 놓으면 동작한다. 이 비대칭을
    설치기가 "배치" 라는 같은 말로 보고해 온 것이 문제였다.
  - **자동 생성은 하지 않는다.** `.gitlab-ci.yml` 이 없는 저장소에 스케줄 전용 job 만
    담은 파일을 만들면 평상시 push 마다 job 없는 빈 파이프라인이 생긴다.
  - **대신 두 가지.** (a) 설치기가 include 유무를 실제로 grep 해 미배선이면 `log_warn`
    으로 보고한다. (b) `claude-sessionstart-doc-gardening.sh` 신설 — CI 배선과 무관하게
    기본 7일 주기로 편차를 점검해 세션 컨텍스트에 주입한다.
  - **배치 조회 신설.** 파일마다 python 을 띄우면 completed/ 가 148개인 저장소에서
    2.64초다. 세션 시작 훅이 동기로 부를 수 없어 `list-complete` /
    `list-retro-empty` 를 추가했다 — **2.64초 → 0.06초(44배)**.
    경로 열거는 여전히 bash 몫이라 §3.3 의 역할 경계는 유지된다.
  - **파일 크기 상한 재검토.** 배치 모드로 `plan_state.py` 가 204줄이 되어 §3.3 의
    200줄 상한을 넘었다. 재검토 결과 분할하지 않는다 — 분할의 원래 반대 근거(배포
    단위가 파일이라 쪼개면 설치 복사본이 4개가 된다)가 그대로 유효하고, 책임도 여전히
    하나다. `cmd_is_complete` 를 `is_complete` 로 정리해 202줄. **상한을 220줄로 갱신**한다.
- 2026-08-13 (개정 6): 인수 검증(§3.11 2 단계) 결과 — `novel-bc` 에 실제 전파.
  - **GitLab 배포 경로 실물 확인.** 등록된 프로젝트 10 개 중 워크플로를 가진 곳은 전부
    GitLab 이었다(GitHub 0). 마커 없는 구버전을 보존하고 "수동 갱신 필요" 경고를 냈다 —
    §3.10 테스트가 GitHub 경로만 덮고 있었으므로 실물이 아니면 확인할 수 없는 항목이었다.
  - **계수 규칙 변경의 이행 위험은 실현되지 않았다.** §3.3 이 우려한 "링크 불릿 때문에
    미완료였던 계획서가 완료로 뒤집혀 새 차단 발생" 은 등록 프로젝트의 실제 계획서
    전수에서 **차이 0 건**이었다. 구/신 정규식 총계가 모두 일치한다.
  - **주입의 실효는 계획서 형식에 달려 있다.** 체크박스를 쓰는 계획서(zeroday-frontend,
    ai-create, rim-office)에서는 검증 방법까지 담긴 미완료 항목이 정상 주입된다.
    반면 산문·이모지로 쓴 계획서(`novel-bc`)에는 주입할 항목이 없어 경로만 나온다 —
    오류 없이 degrade 하지만 그 프로젝트에서는 "진행 중 갱신 유도" 축이 작동하지 않는다.
    템플릿을 따라 새로 쓰는 계획서는 해당하지 않는다.
  - 가드닝 드리프트 스크립트가 실제 부채를 하나 찾아냈다
    (`novel-bc` `completed/2026-08-04-daon-voice-pass.md` 회고 없음).
  - pre-commit 실행 시간 0.05 초 — python 기동 추가분이 체감되지 않는다.
- 2026-08-13 (개정 5): 구현 중 발견 3 건.
  - **조기 종료 결함.** `pre-commit.sh:20` 의 `[[ ${#STAGED[@]} -eq 0 ]] && exit 0` 때문에
    순수 `git mv` 커밋은 훅이 검사에 도달하기도 전에 종료했다. R-retro 로직은 맞았으나
    실행 기회가 없었다. 조기 종료 판정만 `git diff --cached --name-only`(필터 없음)로 바꾸고
    `STAGED` 자체는 유지했다 — 바꾸면 모든 검사의 범위가 함께 바뀐다.
  - **`set -e` + `pipefail` 함정.** 설치기의 마커 판정에서
    `x="$(grep ... | awk ...)"` 는 grep 이 아무것도 못 찾으면 pipefail 로 1 이 되어
    `project-claude.sh:23` 의 `set -e` 가 설치 전체를 중단시켰다. `|| true` 로 막았다.
    2026-04-14 `filter_files` 사고와 같은 계열이다.
  - **§3.6 편차 탐지를 공용 스크립트로 추출**(`assets/hooks/doc-gardening-drift.sh`).
    GitHub 판과 GitLab 판에 두 벌로 복제돼 있어 §1-2 와 같은 어긋남 위험이 있었고,
    추출로 CI 로직에 단위 테스트가 가능해졌다.
- 2026-08-13 (개정 4): §3.11 인수 검증 신설.
  - 자동 테스트가 기존의 "한 번 전파해서 확인" 관행을 **대체하지 않는다**. 테스트는
    적어 둔 케이스를, 전파는 적지 못한 케이스를 잡는다. 순서를 3 단계로 명시하고
    2 단계(단일 프로젝트 수동 전파)의 육안 확인 항목을 체크리스트로 고정.
