# 2026-09-15-decision-ledger — 「내가 대신 결정한 것」 보고 칸 이식

## 1. 동기 (Why)

- 에이전트가 사람에게 묻지 않고 내린 판단이 대화·루프 로그에 흩어져, 사람이 되돌릴 지점을 찾지 못한다.
- `obra/superpowers` 6.3.0 `skills/subagent-driven-development/SKILL.md:19-31, 473-480` 이 같은 문제를
  "묻지 말고 정하되 `결정 — 이유 — 틀렸을 때 비용` 으로 적고, 끝에 전부 모아 넘긴다"로 다룬다(2026-09-15 원문 확인).
- 이 저장소에는 해당 규칙이 없다. 헤드리스 hermes-loop 는 반복마다 `claude -p` 새 프로세스라서
  에이전트가 결정을 적어도 파서가 버리고(`ACTION/VERDICT/VERIFY/NEXT` 만 읽음) 보고서에도 나오지 않는다.
- 사용자 요구: 최초 설치·전파 시 기존·신규 프로젝트 **어느 대화에서든** 적용될 것.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 규칙이 harness 프리셋 규칙 세트로 배포된다. 검증: `readlink -e <프로젝트>/.claude/rules/harness/decision-ledger.md` 가 등록 프로젝트 12곳 모두에서 원본 경로를 낸다. (2026-09-15 실측: 12/12)
- [x] 목표 2 — 헤드리스 루프가 반복별 결정을 저장하고 누락과 "없음"을 구분한다. 검증: `bash tests/hermes-loop-test.sh` 의 결정 기록 절 PASS. (2026-09-15 실측: 전체 85/85)
- [x] 목표 3 — 대화형 `step --decision` 도 같은 저장소에 기록한다. 검증: 같은 테스트 절. (2026-09-15 실측)
- [x] 목표 4 — report.html 에 「내가 대신 결정한 것」 섹션이 반복 순서대로 나온다. 검증: 같은 테스트 절. (2026-09-15 실측)
- [ ] 목표 5 — 새 모듈이 설치 복사 목록에 있어 다른 프로젝트에서 import 가 실패하지 않는다. 검증: `update-all.sh` 후 `upbit-ai-trading/scripts/hermes_loop_decisions.py` 존재 + `python3 -c "import hermes_loop_decisions"` 성공.

## 3. 비목표 (Out of Scope)

- superpowers 플러그인 전역 설치 여부 변경 (사용자 환경 설정).
- Codex 대상(`project-codex.sh`) 반영.
- 전역 `~/.claude/rules/common` 깨진 링크 수리 (§7 발견으로만 기록).
- `update-all.sh` 자동 실행 — 전파 명령은 사용자 확인 후 실행한다.

## 4. 영향 영역

- 코드: `scripts/hermes_loop_prompt.py`, `scripts/hermes-loop.py`, `scripts/hermes_loop_report.py`,
  `presets/workflow/hermes.conf`, `assets/skills/hermes-loop/SKILL.md`, `tests/hermes-loop-test.sh`.
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `assets/rules/harness/decision-ledger.md` — 묻지 않고 내린 결정을 기록·보고하는 형식과 멈춰야 할 네 경우를 에이전트에 지시한다.
  - `scripts/hermes_loop_decisions.py` — 루프 결정 기록의 테이블 정의·보고 블록 파싱·저장·조회를 담당한다.
- 룰: 없음(R 룰 아님, 보고 형식 규칙).
- 데이터: 새 테이블 `loop_decisions` (`CREATE TABLE IF NOT EXISTS` — 기존 DB 무손실).
- 외부 의존: 없음. 원문 출처는 규칙 파일에 표기.

## 5. 단계 (Steps)

### Step 1. 규칙 파일 [단순]

- 산출: `decision-ledger.md`.
- 검증: 목표 1 (링크 폴더라 파일 추가만으로 12곳 반영).

### Step 2. 결정 모듈 + 루프 배선 [Plan/Impl/Review]

- 산출: 신규 모듈, 프롬프트 계약 `DECISION:` 줄, 드라이버·step 기록, 보고서 섹션, 복사 목록.
- 검증: 목표 2~4.

### Step 3. 전파 [단순]

- 산출: `bash update-all.sh` (사용자 승인 후).
- 검증: 목표 1·5.

## 6. 의사결정 로그

- 2026-09-15: 규칙을 새 프리셋이 아니라 harness 규칙 세트에 둔다 — 근거: 등록 12곳 모두 harness 사용, 규칙 폴더가 링크라 전파 즉시 반영. 틀렸을 때 손해: harness 없이 설치한 프로젝트는 규칙을 못 받는다.
- 2026-09-15: `DECISION:` 줄 누락을 파싱 실패로 처리하지 않고 "누락"으로 저장·표시한다 — 근거: 부기 필드 하나로 반복을 무진전 처리하면 루프가 3회 만에 멈춘다. 틀렸을 때 손해: 강제력이 경고 수준에 그친다.
- 2026-09-15: 테스트는 새 파일이 아니라 `hermes-loop-test.sh` 에 절을 추가한다 — 근거: 테스트 수치 문서(doc_counts) 변경 없이 같은 모의 claude 를 재사용한다.
- 2026-09-15: code-reviewer 지적(MEDIUM 1·LOW 2) 반영 — 파싱 실패 반복도 missing 기록 + 보고서가 `loop_steps` 와 대조해 결정 행 없는 반복을 누락 표시. 두 기록을 한 트랜잭션으로 묶지 않은 근거: 보고서 대조가 강제 종료 공백까지 덮고 코어 모듈(385줄) 변경을 피한다. 틀렸을 때 손해: DB 에는 공백이 남고 보고서에서만 보인다.
- 2026-09-15: `hermes_loop_prompt.py` 는 100줄을 넘어도 분리하지 않는다 — 근거: 프롬프트와 파서가 하나의 계약이라 한 파일(모듈 docstring). 결정 파싱은 신규 모듈로 빼 증가분을 최소화한다.

## 7. 발견·예외

- **전파 전 불일치 창**: SKILL.md 는 링크라 즉시 `--decision` 을 안내하지만, 스크립트는 복사본이라 `update-all.sh` 전까지
  8개 hermes 프로젝트(zeroday-frontend·novel-ab·novel-bc·ai-create·jjackkun_bot·upbit-ai-trading·terminal-shipping·kis-trading)의
  `hermes-loop.py` 가 `--decision` 을 모른다 → 대화형 `step` 인자 오류. 전파로 해소. 스킬(링크)과 스크립트(복사) 배포 방식이
  다른 한 계속 생기는 구조 — 다음 룰 후보.
- kis-trading 은 `presets.lock` 에 hermes 가 없는데 `scripts/hermes_loop.py` 가 남아 있다(과거 설치 잔존물 추정).
- 전역 `~/.claude/rules/common` 과 `~/.claude/skills/*` 가 사라진 `/tmp/tmp.e9xM75jdYw/harness/...` 를 가리킨다(2026-09-10 16:35 생성). `update-all-roundtrip-test.sh` 는 HOME 을 격리하므로 원인이 아니다. 원인 미확인 — backlog 후보.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
