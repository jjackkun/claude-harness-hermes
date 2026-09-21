# 2026-09-21-claude-config-scan — `.claude/` 설정의 위험 표면을 기계가 센다

> 출처: `docs/exec-plans/backlog/claude-config-security-scan.md` (ECC 결핍 #8, 사용자 "다 필요한 것들" 확정 2026-09-19)
> 설계 결정 인용: 없음 — 새 경고 게이트. P9(비밀의 경계는 값이다)와 대상이 다르다: 그쪽은 코드 속 값, 이쪽은 **설정이 허용한 권한**.

## 1. 동기 (Why)

`check-secrets.py` 는 코드 속 비밀만 본다. 우리가 12곳에 배포하는 `settings.json` 권한 allowlist·훅 명령·`.mcp.json`·
`CLAUDE.md` 는 아무도 훑지 않는다. `fewer-permission-prompts` 는 allowlist 를 **늘리는** 쪽 도구다.

## 2-bis. 착수 전 확인한 사실 (2026-09-21)

| 확인한 것 | 결과 |
|---|---|
| 12곳 allow 중 도구 전체를 여는 항목(`Bash`·`Bash(*)`·`*`) | **0건** — 이미 전부 범위가 있다 |
| 파괴적 명령을 인자 무관 허용(`Bash(<cmd>:*)`) | **169건** — curl 107 · chmod 23 · rm 14 · sudo 6 · docker 1 (대부분 `settings.local.json`) |
| 훅 command 중 저장소 밖 경로·`curl|sh` | 공장 36개 중 **0건** |
| `.mcp.json` | 12곳 중 **1곳**(ai-create) |
| 소박한 인젝션 정규식의 오탐 | 공장 `CLAUDE.md` 에서 `<!--…run…-->` 주석 1건 오탐 — 고전 문구(ignore previous 류)로 좁혀야 한다 |
| 소박한 "광역" 정규식의 오탐 | `Bash(ls:*)` 같은 정상 항목 25/29 를 광역으로 오판 — 범위 있는 `:*` 는 정상이다 |

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `assets/hooks/claude_config_scan.py` 가 네 갈래를 센다: `unscoped`(도구 전체) · `destructive`(파괴적 명령 인자 무관) ·
  `hook`(저장소 밖 경로·네트워크 파이프) · `injection`(고전 인젝션 문구). 모델 호출 0 — 검증: `bash tests/claude-config-scan-test.sh` (a)
- [x] 목표 2 — 오탐 둘을 내지 않는다: `Bash(ls:*)` 는 `destructive` 가 아니고, `<!--…run…-->` 는 `injection` 이 아니다
  — 검증: 같은 테스트 (b) 공장 자기 설정에서 `unscoped` 0 · `injection` 0
- [x] 목표 3 — 기준선 라쳇: `.claude-config-baseline` 에 있는 항목은 조용하고 **새 항목만** 보고. 기준선은 줄어들기만 한다
  — 검증: 같은 테스트 (c) 기준선에 넣으면 침묵 / 새 항목 추가하면 보고
- [x] 목표 4 — pre-commit `R-config` **경고** 게이트(차단 아님): `.claude/settings*.json`·`CLAUDE.md`·`.mcp.json` 이 스테이징됐을 때만 발화
  — 검증: `bash tests/harness-hooks-smoke.sh` 신규 절(새 위험 추가 시 경고 / 무관 파일만 있으면 침묵)
- [x] 목표 5 — 공장 자기 설정 실측을 기준선으로 고정하고 그 수를 계획서 §7 에 적는다 — 검증: `python3 assets/hooks/claude_config_scan.py --root . --baseline` 출력 줄 수
- [x] 목표 6 — 등록·전파 — 검증: `bash tests/run-all.sh --check-orphans` · 전체 스위트 · `bash tests/install-closure-test.sh`

## 3. 비목표 (Out of Scope)

- allowlist 를 자동으로 줄이는 것 — 무엇을 지울지는 사람이 정한다. 세는 것까지.
- `.mcp.json` 서버의 출처 검증(서명·레지스트리 조회) — 지금은 "원격 URL 이 있다" 는 표시만.
- 소우주의 `settings.local.json` 을 공장이 고치는 것 — 그 기계의 사람 설정이다.

## 4. 영향 영역

- 코드: `assets/hooks/pre-commit.sh`(R-config 경고 한 절)
- **신규 파일 목록**:
  - `assets/hooks/claude_config_scan.py` — `.claude/` 설정 네 갈래 위험을 세는 판정기(표준 모듈만, 모델 호출 0)
  - `.claude-config-baseline` — 도입 시점에 이미 있던 항목(줄어들기만 한다)
  - `tests/claude-config-scan-test.sh` — 네 갈래·오탐 둘·기준선 라쳇·게이트 발화
- 룰: 새 경고 규칙 `R-config`. `.deprc` tier 0(표준 모듈만)
- 설치: `harness.conf` 복사 목록(pre-commit 과 같은 자리) → 12곳 전파
- 데이터: 없음

## 5. 단계 (Steps)

### Step 1. 판정기 + 테스트(RED→GREEN) [단순]
### Step 2. 기준선 생성·게이트 배선 [단순]
### Step 3. 규칙 문서·등록·전체 스위트·전파 [단순]

## 6. 의사결정 로그

- 2026-09-21: `Bash(<cmd>:*)` 는 **파괴적 명령 목록에 있을 때만** 보고 — 근거: 범위 있는 `:*` 는 정상 형식이고(29건 중 25건), 전부
  경고하면 게이트가 소음이 된다.
- 2026-09-21: 기준선 라쳇을 둔다 — 근거: 169건을 한 번에 지울 수 없다. 새로 느는 것만 막으면 방향이 정해진다(R-cx·R-design-cover 와 같은 방식).
- 2026-09-21: 경고이지 차단이 아니다 — 근거: 권한 정책은 사람이 정한다. 차단하면 커밋이 막혀 우회가 상시화된다.

## 7. 발견·예외

- **착수 전 실측이 규칙을 두 번 고쳤다.** 처음 규칙은 12곳에서 169건을 "파괴적" 으로 셌다. 표본을 열어 보니
  **전부 `Bash(rm -f .claude/.review-dirty)` 같은 구체 명령**이었고 인자 무관(`rm:*`) 형식은 **0건**이었다.
  와일드카드가 있을 때만 세도록 좁히니 12곳 합계 **17건**(공장 1건: `unscoped:Artifact`)으로 내려갔다.
  같은 식으로 `Bash(ls:*)`(29건 중 25건)와 `<!--…run…-->` 주석 오탐도 §2-bis 에서 먼저 잡았다.
- 게이트가 픽스처에서 발화하지 않아 한 번 빨갰다 — 판정기를 `.git/hooks/` 에 설치하는 배선이 빠져 있었다
  (`design_cover.py` 와 같은 자리에 넣어 해소). **설치 배선까지 시험이 확인하지 않으면 판정기는 공장에서만 돈다.**
- 기준선 파일은 공장 1줄로 시작한다. 소우주는 기준선이 없어 첫 경고에서 사람이 만든다(R-cx 기준선과 같은 흐름).

## 8. 회고 (완료 시 작성)

- 잘된 것: 새 절 §2-bis(착수 전 확인한 사실)를 실제로 썼고, 그 실측이 규칙을 두 번 좁혔다. 어제였으면 169건짜리
  소음 게이트를 만들었을 것이다.
- 잘못된 것: 설치 배선을 빠뜨렸다 — 스모크가 잡았지만 처음부터 목표에 넣었어야 했다.
- 다음 룰 후보: "새 판정기는 `.git/hooks/` 설치 배선까지 같은 계획에서 끝낸다" — design_cover 때도 같은 누락이 있었다(2회).
