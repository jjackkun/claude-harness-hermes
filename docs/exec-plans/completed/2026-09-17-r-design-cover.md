# 2026-09-17-r-design-cover — 설계 확정 결정이 계획으로 옮겨졌는지 대조하는 게이트 승격

> 작성일: 2026-09-17
> 목적: 계획 `summon-soul-injection`·`design-coverage-gaps` §8 의 공통 룰 후보 `R-design-cover` 를 `core-beliefs.md` 룰 + 강제 장치로 올린다(`harness-promote-rule` 절차).
> 선행: 위 두 계획(설계 확정 16건이 계획으로 옮겨지지 않은 채 완료 처리된 경로를 실측).

## 1. 동기 (Why)

- 같은 결함이 하루에 16건: 설계 문서에 "(확정)"·"✅ 리뷰 확정" 으로 굳은 동작이 계획서 §2 목표에 옮겨지지 않아 코드가 없는 채 계획이 닫혔다(보안 1건 포함). 옮겨졌는지 보는 장치가 없었다.
- 실측(2026-09-17): 설계 문서 12개에 확정 표지 86건, 결정 ID(RV·G·V·K·T·C) 중 계획서 미인용 9개, `(확정)` 절 제목 42개 중 ID 가 있는 것 3개(합의 절 포함 ID 없는 절 58).

## 2. 목표 (What — 검증 가능한 형태)

> 검증 명령: `bash tests/design-cover-gate-test.sh` · `python3 assets/hooks/design_cover.py check`(실 저장소 rc 1) · `bash tests/run-all.sh`.

- [x] 목표 1 — 판정기 `assets/hooks/design_cover.py check`: (A) 설계 문서의 결정 ID 가 `docs/exec-plans/**` 어디에도 없으면 틈, (B) `(확정)`·`(합의)` 절 제목에 ID 가 없으면 틈. 기준선 `.design-cover-baseline` 에 있는 틈은 제외. 종료코드 0=새 틈·1=없음·2=설계 디렉터리 없음. 검증: `bash tests/design-cover-gate-test.sh` — 픽스처에서 (A) 1·(B) 1 검출, 기준선으로 억제, 인용 추가로 해소, 설계 디렉터리 없으면 rc 2.
- [x] 목표 2 — pre-commit `R-design-cover`(경고): 스테이징에 설계 문서나 계획서가 있을 때만 돌고, 새 틈을 한 줄씩 보이며, 설계 디렉터리가 없는 소우주에서는 조용히 skipped. 검증: `bash tests/design-cover-gate-test.sh` §3 — 게이트 이벤트 warn/pass/skipped 각 1.
- [x] 목표 3 — 기준선 파일 `.design-cover-baseline` 생성(실측 71건 = 미인용 ID 13 + ID 없는 확정/합의 절 58. 기준선 파일에 열거하고 계획서 본문에는 ID 를 적지 않는다 — 계획서에 적으면 판정기가 '인용됨' 으로 본다)으로 실 저장소 `check` 가 rc 1. 검증: `python3 assets/hooks/design_cover.py check; echo $?` → 1.
- [x] 목표 4 — `core-beliefs.md` 에 `## R-design-cover {#r-design-cover}` 절 + 감사 `docs/audits/2026-09-17-r-design-cover-promotion.md`. 검증: 앵커 존재, pre-commit 메시지의 근거 링크가 그 앵커.
- [x] 목표 5 — 등록: `.deprc` tier 0, `run-all.sh`, 문서 수치 동기(게이트 18종). 검증: `bash tests/preset-integrity-test.sh`, `python3 assets/hooks/doc_counts.py check README.md CLAUDE.md presets/workflow/harness.conf`.

## 3. 비목표 (Out of Scope)

- 기준선 71건 해소(별도 — backlog `design-gaps-tier2.md` 와 함께). 산문 확정 문장(ID·표지 없음) 탐지 — 이 룰은 "확정이면 ID 를 달라"(B) 로 앞으로의 문장을 (A) 가 보게 만드는 것까지다.

## 4. 영향 영역

- 신규: `assets/hooks/design_cover.py`(설계 결정 ID·확정 절 ↔ 계획서 인용 대조 판정만), `tests/design-cover-gate-test.sh`, `.design-cover-baseline`, `docs/audits/2026-09-17-r-design-cover-promotion.md`.
- 수정: `assets/hooks/pre-commit.sh`(게이트 블록 + `# GATE: R-design-cover warn`), `docs/design-docs/core-beliefs.md`, `.deprc`, `tests/run-all.sh`, README/CLAUDE/harness.conf(수치).
- 전파: pre-commit·판정기는 `assets/hooks` 자산 → 소우주에도 깔리지만 설계 디렉터리가 없어 skipped.

## 5. 단계 (Steps)

### Step 1. 판정기 + 테스트 + 기준선 [Impl] — 목표 1·3
### Step 2. 게이트 + 룰 + 감사 + 등록 [Impl] — 목표 2·4·5

## 6. 의사결정 로그

- 2026-09-17: **단위는 결정 ID, 보조로 확정 절 제목.** 근거: 줄 번호는 편집마다 어긋나고, 절 제목 문자열 대조는 실측 61건 중 16건 오탐(G6 위반). ID 는 설계 문서가 이미 쓰는 어휘라 정확하다(47개 중 43개 인용). 손해: ID 도 표지도 없는 산문은 못 본다 — (B) 가 그 틈을 앞으로 줄인다.
- 2026-09-17: **경고이지 차단 아님 + 기준선 라쳇.** 근거: 도입 시점 틈 71건을 한꺼번에 막으면 커밋이 서고, 알리면 G6. R-cx 의 `.cxbaseline` 과 같은 방식. 손해: 기준선 안의 틈은 스스로 사라지지 않는다 — backlog 로 관리.
- 2026-09-17: **공유 pre-commit 에 넣되 설계 디렉터리 없으면 무출력 skipped.** 근거: 게이트 위치를 둘로 나누면 소우주가 같은 문서 구조를 택했을 때 못 쓴다. 손해: 소우주 pre-commit 에 쓰이지 않는 블록 1개.

## 7. 발견·예외

- 2026-09-17: 기준선을 만든 직후 계획서 동기 절의 ID 열거를 지우자 4건이 "새 틈" 으로 떴다 — 판정기는 `docs/exec-plans/**` 어디의 ID 든 인용으로 본다. 계획서·감사에는 ID 를 열거하지 않고 기준선 파일에만 둔다(룰 문서에 명시).
- 2026-09-17: 전체 스위트 1회차에서 `hermes-pipeline-test`(--apply junk 삭제 · 정정 요약 진화)·`install-receipt-test`(hermes 사본 영수증) 가 빨갰으나 단독·2회차 모두 초록 — 이 변경과 무관한 플레이크. backlog `dream-test-clock-flake.md` 와 같은 부류로 기록만.

## 8. 회고 (완료 시 작성)

- 잘된 것:
  - 단위를 정하기 전에 셋(줄 번호·절 제목·결정 ID)을 실측해 오탐률로 골랐다 — 절 제목 대조는 16/61 오탐이라 게이트로 쓰면 G6 위반이었을 것.
  - 기준선 라쳇으로 도입 시점 부채(71건)를 잠그고 새 틈만 보게 해, 첫날부터 커밋을 막거나 시끄럽지 않다.
- 잘못된 것:
  - 기준선 생성 순서를 잘못 잡아(계획서에 ID 를 열거한 채 생성) 한 번 다시 만들었다 — "판정기가 무엇을 인용으로 세는가" 를 먼저 적었어야 했다.
  - 이 룰도 산문 확정은 못 본다 — (B) "확정이면 ID" 가 습관이 될 때까지는 사람이 본다.
- 다음 룰 후보: 없음(기준선 71건 해소는 backlog `design-gaps-tier2.md` 와 함께).
