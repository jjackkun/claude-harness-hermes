# 2026-10-21-planning-skill-chain — 기획 문서 사슬: 아이디어 점검 → PRD → 시안 → 계획 → 의도 대조

> 출처: 감사 `docs/audits/2026-10-21-pm-skill-repos-review.md` (PM 스킬 저장소 4곳 검토).
> 사용자 요구 (2026-10-21): "기획, 설계, PRD 등을 많이 만들어 … 자연어로 후보들이 기존 스킬들과 맞물려서 시너지 내게 설치해서 작업하게 할 수 있나?"
> 사용자 승인 (2026-10-21): 공통 폴더를 `docs/product-specs/` 로 — "공통 폴더가 되게 하는게 낫겠어. 승인할게".

---

## 0. 다음 세션 시작점

**진행: G1~G10 완료 (G8 은 근거로 닫고 건너뜀, §7). 남은 것: G11 전파(지시 시).**

실측 요약: 사슬 시험 44/44 · ui-prototype 40/40 · 프리셋 무결성 107 참조 · 전체 시험 145 중 143 → 실패 2(문서 수치·생성 CLAUDE.md 103줄, 둘 다 이번 변경) 고친 뒤 해당 시험 재실행 통과 · `update-all-roundtrip` 은 다른 세션과 겹친 흔들림(단독 35/35)

| 단계 | 목표 | 상태 |
| --- | --- | --- |
| Step 0 계획 문서 | — | 완료 — planner-lite 11건 · architect-lite 10건 대조 반영 (§9) |
| Step 1 시험 골격 + run-all 등록 | G1 (빨강) | 완료 — 빨강 통과 5 · 실패 38 확인, run-all 등록 141개 고아 0 |
| Step 2 계약 + 공통 폴더 안내 | G1 · G2 | 완료 — `contract.md`(contract-version 1), `product-specs/README.md` |
| Step 3 prd-writer (+ 계약 검사기) | G3 | 완료 — 평가 100% vs 50%, 발동 오발동 0 · 재현 3/10 |
| Step 4 idea-check | G4 | 완료 — 평가 100% vs 42%, 발동 오발동 0 · 재현 4/10 |
| Step 5 intended-vs-implemented | G5 | 완료 — 평가 100% vs 70%, 발동 오발동 0 · 재현 5/10 |
| Step 6 기존 자산 잇기 | G6 · G7 | 완료 — 사슬 평가: 수준 B 판정, 근거·requires 에 FR 16회. ui-prototype 시험 40/40, devil-advocate 62줄 |
| Step 7 사슬 배정 측정 (사람이 터미널에서) | G8 | 건너뜀 (사용자 결정, §7) |
| Step 8 출처·README·전체 시험 | G9 · G10 | 완료 — README·수치 동기화, 생성 CLAUDE.md 99줄(줄 합치기 + product-specs 목차 한 줄), 전체 시험 1회 |
| Step 9 전파 (사용자 지시가 있을 때만) | G11 | 대기 |

## 1. 동기 (Why)

- 사용자는 기획·설계·PRD 문서를 자주 만들고, 2026-10-20 에 그 문서에서 시안을 만드는 `ui-prototype` 까지 넣었다.
- 그런데 **시안 앞뒤가 비어 있다.**
  - 앞: "만들 가치가 있나" 를 따지는 단계와 PRD 를 쓰는 단계가 없다. `ui-prototype` 은 문서가 모자라면 질문 셋으로 메우는 것이 전부다.
  - 뒤: 구현이 기획 의도대로 됐는지 문서와 코드를 대조하는 단계가 없다.
- 기획 문서를 두는 자리가 프로젝트마다 다르다 (§2-bis). 그래서 다음 스킬이 "어느 문서가 최신 기획서인가" 를 매번 추측한다.
- 외부 저장소 4곳의 스킬은 통설치하면 우리 스킬과 발동을 다투고, 일부는 훅·자동 업데이트·외부 전송을 함께 깐다 (감사 문서). 필요한 절차만 골라 우리 흐름에 맞게 고쳐야 한다.

## 2. 목표 (What — 검증 가능한 형태)

합격 숫자의 근거: 통과율 80% 는 전역 시험 규칙(`rules/common/testing.md` 최소 80%), 발동 기준은 직전 실측(§2-bis 마지막 두 줄).

- [x] G1 — 사슬 정적 시험 `tests/planning-chain-test.sh` 가 **스킬이 없을 때 빨강**이고, 아래를 모두 검사한다
      (a) 세 스킬 frontmatter `name`·`description` (b) 계약 버전 줄이 계약·안내 README·세 스킬에서 같은 값 (c) 금지 문자열 0 — `grep -rciE 'ycombinator|\.gstack|supabase|codex exec|\bcurl\b|\bwget\b' --exclude=NOTICE.md` 합계 0
      (d) NOTICE.md 마다 라이선스 이름(`MIT`·`Apache-2.0`)과 `## 바꾼 점` 절 (e) 세 스킬 SKILL.md 와 ui-prototype SKILL.md 에 `^다음:` 줄 (f) `check_prd.py` 가 좋은 픽스처 통과·망가뜨린 픽스처 4종 실패
      (g) 임시 git 저장소에 설치 → `docs/product-specs/README.md` 생김, README 를 고친 뒤 재설치 → 내용 그대로
      검증: Step 1 에서 빨강 확인(실패 수 기록) → Step 8 에서 `bash tests/planning-chain-test.sh` 전부 통과
- [x] G2 — **계약 정본은 한 곳**: `assets/skills/prd-writer/references/contract.md` (설치 때마다 갱신되는 스킬 폴더에 둔다 — 프로젝트 README 는 덮지 않으므로 정본이 될 수 없다). 계약이 정하는 것:
      폴더·파일 이름, `<이름>` 글자 규칙(`^[a-z0-9]+(-[a-z0-9]+)*$`, ui-prototype `structure.md:26` 과 같음), 이름 정하는 시점·충돌 시 묻기, 문서 찾기 순서(product-specs → 옛 위치), 여러 기획 중 고르기, brief.md 필수 칸, prd.md 머리(`status`·`updated`·`contract-version`)·필수 절·요구 표 열(ID·요구·검증·우선순위·상태), FR ID 규칙(`^FR-[0-9]+$`, 재사용 금지, 삭제는 `폐기`), FR ID 없는 문서를 받았을 때의 처리
      다른 파일은 이 계약을 **가리키기만** 한다. 프로젝트용 `docs/product-specs/README.md` 는 사람이 읽는 안내 + `contract-version: 1`
      검증: G1 (b)·(f). `grep -c 'FR-' ` 정의가 contract.md 밖 SKILL.md 에 규칙으로 다시 적혀 있지 않음(리뷰 확인)
- [x] G3 — `prd-writer` 스킬: brief.md 가 있으면 읽고(판정이 `보류` 면 먼저 알림), 없으면 질문 최대 3개. 지어내지 않고 「가정·열린 질문」 칸으로 보낸다. 산출 `docs/product-specs/<이름>/prd.md` 를 `check_prd.py` 로 검사하고 통과해야 끝낸다
      검증: skill-creator 평가 3건(brief 있음·없음·한 줄 아이디어) — 단언: 산출 경로 일치, `check_prd.py` 통과, brief 에 없는 숫자는 「가정」 에만 있음. **스킬 있음 통과율 ≥ 80% 이고 없음보다 높다**
      발동: `trigger-evals.json` 20개(발동 10 · 비슷하지만 안 함 10) **엉뚱한 발동 0**, 재현율 기록
- [x] G4 — `idea-check` 스킬: 6문항 → 전제 도전 → 대안 2~3개 → 판정(`만든다`·`좁힌다`·`보류`) → `docs/product-specs/<이름>/brief.md`
      검증: 평가 2건 — 단언: brief.md 경로, 판정 칸이 셋 중 하나, 대안 2개 이상. 통과율 ≥ 80% 이고 없음보다 높다. 발동 20개 엉뚱한 발동 0
- [x] G5 — `intended-vs-implemented` 스킬: 의도 문서(prd.md·계획서 §2·설계 문서)를 계약의 찾기 순서로 고르고, 주장마다 코드 강제 지점을 찾아 `docs/audits/YYYY-MM-DD-<이름>-intent-check.md` 에 적는다. "적혀만 있고 강제 안 됨" 도 결함
      검증: 평가 2건(픽스처는 평가 프롬프트 안에서 만든 작은 저장소 — 의도와 다르게 고친 함수 1개) — 단언: 문서 인용 1개 이상, `[^ ]+:[0-9]+` 위치 1개 이상, 일부러 넣은 어긋남을 찾음. 통과율 ≥ 80%. 발동 20개 엉뚱한 발동 0
- [x] G6 — 사슬이 실제로 이어진다: G3 평가 산출 prd.md 를 그대로 ui-prototype 에 주면 입력 수준 `B` 또는 `A+B` 판정, 명세표 근거 칸에 `FR-[0-9]+` 가 나오고 `ui-prototype:requires` 에 FR ID 가 들어간다
      검증: 평가 1건 + `check_spec.py` 통과
- [x] G7 — 기존 자산 잇기
      - `ui-prototype/references/spec-from-docs.md` 문서 찾기를 계약으로 대체(계약 경로를 가리킴). 옛 위치에만 PRD 가 있는 경우도 찾는다
      - `devil-advocate` 에 레드팀 절차("이러면 무너진다" → 영향×가능성×시험 비용 → 가장 싼 시험·중단 기준)
      - `docs-templates/docs/exec-plans/template.md` §2 에 "PRD 의 FR ID 를 적는다" 한 줄 (규칙 정의는 계약을 가리킴)
      검증: `wc -l assets/agents/devil-advocate.md` ≤ 80 (지금 48줄 + 절차 ≤ 32줄), G1 (e), ui-prototype 기존 시험 `bash tests/ui-prototype-build-test.sh` 40/40 유지
- [x] G8 — **건너뜀(2026-10-21 사용자 결정 "G8 건너뛰어")** — 사슬 배정 측정 (harness-eval, **사람이 세션 밖 터미널에서**): 자연어 12개를 `tests/agent-evals-chain/` 시나리오로 (`tests/agent-evals/` 는 시험이 7개로 단언하므로 따로 둠)
      스킬 시나리오 8개(점검·PRD·시안·대조 × 2): `require_tool` = 기대 스킬(세션 안 어디든 — brainstorming 이 먼저 불려도 인정), `forbid_tool` = 다른 사슬 스킬
      오발동 시나리오 4개(계획 2·공격 2): `forbid_tool` = 사슬 스킬 넷 (devil-advocate 는 Agent 도구라 harness-eval 허용 도구 밖 — 호출 여부는 못 잼)
      합격: **오발동 시나리오 4/4 통과**, 스킬 시나리오 pass@3 ≥ 6/8 (원래 9/12 와 같은 75%). brainstorming 이 첫 호출인 비율은 기록만
      미달 시: description 을 고쳐 최대 3회 재측정 → 그래도 미달이면 수치와 함께 사용자에게 보고하고 §6 에 남긴다 (공장이 전역 brainstorming 을 고칠 수 없다)
      검증: `python3 scripts/harness-eval.py --scen-dir tests/agent-evals-chain --strictness neutral --k 3` 결과 `.harness/evals/<stamp>.json`
- [x] G9 — 출처·라이선스: MIT 차용분(gstack·phuryn)은 저작권 줄, Apache-2.0 차용분(product-on-purpose 실행 계약 칸)은 출처·라이선스·바꾼 점. CC BY-NC-SA(deanpeters) 차용 0. NOTICE 는 스킬마다 둔다(설치 단위가 스킬 폴더라서)
      검증: G1 (d), `grep -rli deanpeters assets/skills` → 없음
- [x] G10 — 등록·전체 시험: 스킬마다 완성 직후 `harness.conf` `SKILLS+=` 에 근거 주석과 함께 등록하고 `bash tests/preset-integrity-test.sh` 통과. 마지막에 전체 1회
      검증: `bash tests/run-all.sh --check-orphans && bash tests/run-all.sh`, README 스킬 설명 절 갱신(readme-sync-before-commit)
- [ ] G11 — (Step 9, 사용자 지시가 있을 때만) 전파: 등록 소우주 전부에 스킬 셋과 `docs/product-specs/README.md`(없을 때만) 가 깔린다. 커밋·푸시는 기억된 예외 규칙을 따른다
      검증: `bash update-all.sh` 성공 수, 소우주마다 `ls .claude/skills/{idea-check,prd-writer,intended-vs-implemented}`

## 2-bis. 착수 전 확인한 사실 (2026-10-21)

| 확인한 것 | 결과 |
| --------- | ---- |
| 기획 문서 위치 (소우주 실측) | `docs/product-specs/`: drh-cloth-shop·rim-kanban / `docs/product/prd-*.md`: terminal-shipping / `docs/prd/`·`docs/design-docs/prd-*.md`: zeroday-frontend / `docs/planning/`: teulankkae — 다섯 갈래 |
| 이미 product-specs 가 있는 소우주 | rim-kanban 은 `docs/product-specs/README.md` 있음 → 비덮어쓰기라 새 안내가 안 들어감. 그래서 계약 정본을 스킬 폴더에 둠 (G2) |
| 공장 템플릿의 `product-specs` | `assets/docs-templates/ARCHITECTURE.md.tmpl:51` 에 이름만 있고 템플릿 폴더엔 없음 |
| 템플릿 설치 방식 | `lib/harness_installers.sh:406~` — `docs-templates` 를 복사하되 **기존 파일은 덮지 않음**. `harness.conf:156` `HARNESS_DOCS_TEMPLATES=1` |
| ui-prototype 문서 찾기 | `references/spec-from-docs.md:19` — product-specs 언급 0 |
| ui-prototype 이름·요구 ID 규약 | 이름 영문 소문자·숫자·`-` (`structure.md:26`). 근거 칸 요구 ID `[A-Z]+-[0-9]+` (`spec-table.md:37`) → `FR-1` 맞음 |
| 프리셋 무결성 시험 | `tests/preset-integrity-test.sh:33` — `SKILLS` 항목이 assets 에 없으면 실패 → 폴더 먼저, 등록은 완성 직후 |
| 고아 시험 | `tests/run-all.sh` 는 목록에 없는 `tests/*-test.sh` 를 실패로 봄 → 새 시험은 만든 그 단계에서 등록 |
| harness 프리셋 스킬 | `harness.conf:26` — 7개 (… pre-commit-measure, ui-prototype) |
| devil-advocate | `assets/agents/devil-advocate.md` 48줄, `harness.conf:47` |
| 전역 brainstorming 발동 문구 | superpowers 7.0.0 — "You MUST use this before any creative work …". 공장이 고칠 수 없음 |
| 직전 발동 실측 (ui-prototype, 2026-10-20) | run_loop 재현율 0~17%, 정밀도 100%. 원인: brainstorming 이 첫 스킬 호출을 선점하고 run_loop 는 첫 호출만 봄 (완료 계획서 289행) |
| harness-eval 채점 | 세션 안 모든 툴콜에 `require_tool`·`forbid_tool` 정규식, 결정론. 세션 안에서는 summon-guard 가 `claude -p` 를 막아 **사람이 터미널에서** 돌림. 모델 haiku |
| 같은 이름 스킬 | `assets/skills/` 에 idea-check·prd-writer·intended-vs-implemented 없음 |
| 원본 크기·라이선스 | gstack openclaw office-hours 373줄, 런타임 참조 0, YC 권유 360~364줄 (MIT) / phuryn create-prd 97줄, intended-vs-implemented 42줄, strategy-red-team 72줄 (MIT) / product-on-purpose deliver-prd 108줄 + TEMPLATE 286줄 (Apache-2.0) |

## 3. 비목표 (Out of Scope)

- 소우주에 이미 있는 기획 문서를 `docs/product-specs/` 로 **옮기는 일**. 옛 위치는 읽기만 한다.
- 이미 있는 소우주 `docs/product-specs/README.md` 를 덮어쓰는 일.
- 외부 저장소를 플러그인·setup 으로 설치하는 일 (감사 문서 판정).
- 전략·시장·마케팅 틀, 팀 의식, 우선순위 점수 스킬 (감사 문서 「들이지 않는 것」).
- 사슬을 자동으로 이어 돌리는 오케스트레이터. 각 스킬은 다음 단계를 **안내만** 한다.
- 전역 superpowers 플러그인 수정.

## 4. 영향 영역

- **신규 파일 목록 (파일별 책임 1줄)**:
  - `tests/planning-chain-test.sh` — 사슬 정적 시험 G1 (a)~(g)
  - `tests/fixtures/planning-chain/prd-good.md` — 계약을 지킨 prd.md (check_prd 통과 기준)
  - `assets/skills/prd-writer/references/contract.md` — **사슬 계약 정본** (G2 의 모든 항목)
  - `assets/skills/prd-writer/SKILL.md` — PRD 흐름: 기획 고르기 → brief 읽기 → 빈 곳 질문(최대 3) → 초안 → 가정·열린 질문 분리 → 요구 표 → check_prd 통과
  - `assets/skills/prd-writer/references/prd-template.md` — prd.md 빈 양식만 (필수 칸 정의는 contract.md)
  - `assets/skills/prd-writer/scripts/check_prd.py` — prd.md 가 계약을 지키는지 검사: 머리 3줄, 필수 절, 요구 표 열, FR ID 형식·중복, 검증 칸 빈칸
  - `assets/skills/prd-writer/NOTICE.md` — 출처(phuryn MIT, product-on-purpose Apache-2.0)·바꾼 점
  - `assets/skills/prd-writer/evals/evals.json` — 평가 3건
  - `assets/skills/prd-writer/evals/trigger-evals.json` — 발동 20개
  - `assets/skills/idea-check/SKILL.md` — 만들지 말지: 기획 이름 정하기 → 단계 판정 → 6문항 → 전제 도전 → 대안 → 판정 → brief.md
  - `assets/skills/idea-check/references/questions.md` — 6문항 각각의 의도·밀어붙이는 예·좋은 답/나쁜 답 신호
  - `assets/skills/idea-check/references/brief-template.md` — brief.md 빈 양식만 (필수 칸 정의는 contract.md)
  - `assets/skills/idea-check/NOTICE.md` — 출처(garrytan/gstack MIT)·바꾼 점
  - `assets/skills/idea-check/evals/evals.json` — 평가 2건
  - `assets/skills/idea-check/evals/trigger-evals.json` — 발동 20개
  - `assets/skills/intended-vs-implemented/SKILL.md` — 의도 대조: 의도 문서 고르기 → 주장 뽑기 → 강제 지점 찾기 → 어긋남 분류 → 감사 문서
  - `assets/skills/intended-vs-implemented/NOTICE.md` — 출처(phuryn MIT)·바꾼 점
  - `assets/skills/intended-vs-implemented/evals/evals.json` — 평가 2건
  - `assets/skills/intended-vs-implemented/evals/trigger-evals.json` — 발동 20개
  - `assets/docs-templates/docs/product-specs/README.md` — 프로젝트용 안내: 폴더 하나 = 기획 하나, 사슬 지도, `contract-version: 1`, 정본은 스킬 계약이라는 안내
  - `tests/agent-evals/chain-*.json` — 사슬 배정 시나리오 12개 (G8)
- **수정**:
  - `assets/skills/ui-prototype/references/spec-from-docs.md` — 문서 찾기를 계약 참조로
  - `assets/skills/ui-prototype/SKILL.md` — 끝에 `다음:` 한 줄
  - `assets/agents/devil-advocate.md` — 레드팀 절차
  - `assets/docs-templates/docs/exec-plans/template.md` — §2 에 FR ID 한 줄
  - `presets/workflow/harness.conf` — `SKILLS+=` 셋 (스킬마다 완성 직후, 근거 주석)
  - `tests/run-all.sh` — Step 1 에서 새 시험 등록
  - `README.md` — 스킬 설명 절
- 룰: R-size(400), R-struct, R-declare(이 §4), 스킬 개발 규칙(skill-creator 필수), R-privacy(문서에 이메일 0)
- 데이터: 없음
- 외부 의존: python3 (check_prd.py — 표준 라이브러리만)

## 5. 설계

### 5-1. 자연어 → 스킬 → 문서 사슬

| 단계 | 사용자가 하는 말 (예) | 스킬 | 읽는 것 | 남기는 것 |
|---|---|---|---|---|
| ① 점검 | "이거 만들 가치 있나", "아이디어 검증하자", "누가 쓸지 따져 보자" | idea-check | 없음 | `docs/product-specs/<이름>/brief.md` |
| ② PRD | "기획서 써 줘", "PRD 만들자", "요구사항 정리하자" | prd-writer | brief.md | `docs/product-specs/<이름>/prd.md` |
| ③ 시안 | "시안 만들어", "와이어프레임" | ui-prototype (기존) | prd.md | `docs/prototypes/<이름>/` |
| ④ 계획 | "구현 계획 세우자" | exec-plan 양식·writing-plans (기존) | prd.md 의 FR·검증 칸 | `docs/exec-plans/active/…` §2 |
| ⑤ 대조 | "기획대로 됐는지 확인해", "PRD 랑 코드 맞춰 봐" | intended-vs-implemented | prd.md + 코드 | `docs/audits/…-intent-check.md` |
| (공격) | "이 계획 어디서 무너질까" | devil-advocate 에이전트 (기존, 보강) | 계획서·PRD | 대화 보고 |

- 어느 단계에서 시작해도 된다. 앞 문서가 없으면 각 스킬이 질문으로 메운다.
- "기획서 써 줘" 를 아이디어 단계에서 말해도 prd-writer 로 간다 (idea-check 를 강제로 거치지 않음). 단, brief.md 판정이 `보류` 면 먼저 알린다.
- 각 스킬은 끝에 `다음: "○○" 라고 하시면 ○○ 를 합니다` 한 줄만 쓴다.

### 5-2. 계약에서 고르는 규칙 (contract.md 요지)

- **기획 고르기**: 사용자가 이름을 댔으면 그 폴더. 안 댔고 `docs/product-specs/` 아래 폴더가 하나면 그것. 둘 이상이면 목록을 보이고 묻는다 — 수정 시각으로 추측하지 않는다.
- **이름 정하기**: 처음 만드는 스킬(idea-check 또는 prd-writer)이 제안하고 확인받는다. 한글 제목은 영문으로 바꿔 제안. 이미 있는 폴더면 "이어 쓸지 / 새 이름인지" 묻는다.
- **찾기 순서**: `docs/product-specs/<이름>/` → 옛 위치(`docs/product/`·`docs/prd/`·`docs/planning/`·`docs/design-docs/prd-*`). 둘 다 있으면 product-specs 를 따르고 그 사실을 보고한다.
- **갱신**: prd.md 는 제자리에서 고치고 git 이력이 버전이다. 머리의 `updated` 를 바꾼다. FR 번호는 재사용하지 않고, 지운 요구는 상태 `폐기` 로 남긴다 (계획서 §2 의 FR 참조가 깨지지 않게).
- **FR 없는 문서**: 하류 스킬은 절 제목·줄 번호로 인용하고 "FR ID 없음" 을 보고한다.

### 5-3. 발동 경계 (description 에 서로 맞물리게 적음)

각 description 은 5-1 의 한국어 말 예시로 시작한다.

| 스킬 | 쓴다 | 쓰지 않는다 (→ 맡는 쪽) |
|---|---|---|
| idea-check | 만들지 말지·누가 겪는 문제인지·더 좁힐지 | 만들기로 한 것의 설계·기능 구상 (→ brainstorming), 문서 작성 (→ prd-writer) |
| prd-writer | PRD·기획서·요구사항 문서를 쓰거나 고침 | 화면 시안 (→ ui-prototype), 구현 단계 계획 (→ exec-plan·writing-plans) |
| intended-vs-implemented | 문서의 의도 ↔ 코드 대조 | 코드 품질 리뷰 (→ code-reviewer), 버그 원인 찾기 (→ systematic-debugging) |

### 5-4. 원본에서 바꾸는 것

- idea-check (gstack openclaw판): YC 권유 삭제, 저장 위치 `memory/` → `docs/product-specs/<이름>/brief.md`, 한국어·존댓말, 단계 판정은 1인 개발 기준.
- prd-writer (phuryn create-prd + product-on-purpose 실행 계약 칸): 저장 위치 `PRD-<name>.md` → `docs/product-specs/<이름>/prd.md`, 한국어, 요구 표에 검증 칸 필수, 뉴스레터 링크·다른 스킬 이름 참조 삭제.
- intended-vs-implemented (phuryn): 결과를 대화가 아니라 `docs/audits/` 문서로, 계획서 §2 목표도 의도 문서로 인정.

## 5-bis. 단계 (Steps)

### Step 1. 시험 골격 + 등록 [Impl — 빨강 먼저]
- 산출: `tests/planning-chain-test.sh`, `tests/fixtures/planning-chain/prd-good.md`, `tests/run-all.sh` 등록
- 검증: 시험 실행 → **실패**(스킬 없음) 수를 §7 에 기록. `bash tests/run-all.sh --check-orphans` 통과

### Step 2. 계약 + 공통 폴더 안내 [Plan/Impl]
- 산출: `prd-writer/references/contract.md`, `docs-templates/docs/product-specs/README.md`
- 검증: G1 (b)·(g) 통과

### Step 3. prd-writer [Plan/Impl/Review — skill-creator]
- 산출: SKILL.md·prd-template·check_prd.py·NOTICE·evals
- 검증: G1 (f), G3 평가·발동 → `harness.conf` 등록 → `preset-integrity-test` 통과

### Step 4. idea-check [Plan/Impl/Review — skill-creator]
- 산출: SKILL.md·questions·brief-template·NOTICE·evals
- 검증: G4 평가·발동 → 등록 → `preset-integrity-test` 통과

### Step 5. intended-vs-implemented [Plan/Impl/Review — skill-creator]
- 산출: SKILL.md·NOTICE·evals
- 검증: G5 평가·발동 → 등록 → `preset-integrity-test` 통과

### Step 6. 기존 자산 잇기 [단순]
- 검증: G7, 그다음 G6 평가 1건

### Step 7. 사슬 배정 측정 [사람이 터미널에서]
- 산출: `tests/agent-evals/chain-*.json` 12개 (내가 씀). 실행은 사용자가 **세션 밖 터미널에서** `python3 scripts/harness-eval.py --only <사슬 시나리오> --k 3` (세션 안은 summon-guard 가 `claude -p` 를 막음)
- 검증: G8

### Step 8. 출처·README·전체 시험 [단순]
- 검증: G9·G10, `bash tests/planning-chain-test.sh` 전부 통과

### Step 9. 전파 [사용자 지시가 있을 때만]
- 검증: G11

**완료 조건**: G1~G10 체크 → §8 회고 → `completed/` 로 이동. G11 은 지시가 있을 때 같은 문서에 이어 적는다.
**되돌리기**: `harness.conf` 에서 `SKILLS+=` 셋을 빼고 스킬 폴더 셋을 지운 뒤 재전파. 소우주에 깔린 `docs/product-specs/README.md` 는 사용자 문서가 될 수 있어 자동으로 지우지 않는다.

## 6. 의사결정 로그

- 2026-10-21: 공통 폴더 `docs/product-specs/` — 근거: 공장 템플릿에 이미 이름이 있고 두 소우주가 이미 씀. 사용자 승인
- 2026-10-21: 스킬 이름 `idea-check` (원본 `office-hours` 대신) — 근거: 자연어로 부를 때 하는 일이 이름에 드러나야 함. 출처는 NOTICE.md
- 2026-10-21: PRD 바탕은 phuryn `create-prd`(97줄), product-on-purpose 에서는 실행 계약 칸만 — 근거: 짧고 지어내지 않는 방식이 사용자 규칙(추측 금지)과 맞음. 286줄 템플릿은 토큰 비용이 큼
- 2026-10-21: strategy-red-team 은 새 스킬이 아니라 devil-advocate 보강 — 근거: 같은 역할(반대편)이 둘이면 발동이 갈림
- 2026-10-21: 계약 정본을 `prd-writer/references/contract.md` 에 — 근거: docs-templates 는 덮지 않아 프로젝트 README 는 갱신이 안 됨(rim-kanban 실측), 스킬 폴더는 설치마다 갱신됨. idea-check·intended-vs-implemented·ui-prototype 이 이 파일을 가리키므로 세 스킬은 함께 설치된다(같은 프리셋)
- 2026-10-21: 계약 검사를 `check_prd.py` 로 기계화 — 근거: "검증 칸이 비어 있지 않음" 을 사람이 읽고 판정하면 하류(ui-prototype·의도 대조)가 깨진 문서를 받는다. ui-prototype 이 `check_spec.py` 로 같은 문제를 푼 선례
- 2026-10-21: 사슬 배정 합격선 "오발동 0 · 기대 스킬 pass@3 ≥ 9/12" — 근거: run_loop 는 첫 호출만 봐서 재현율 0~17% 로 나왔음(직전 실측). harness-eval 은 세션 전체를 보므로 brainstorming 선점과 무관하게 잴 수 있음. 9/12 = 단계마다 2개 중 적어도 1개 반 — 측정 후 §7 에 실제 분포를 남기고 필요하면 이 결정을 고친다
- 2026-10-21: 평가 통과율 합격선 80% — 근거: 전역 시험 규칙의 최소 커버리지 80%

## 7. 발견·예외

- **Step 1 빨강 (2026-10-21)**: 스킬 없을 때 `planning-chain-test.sh` 통과 5 · 실패 38. 통과 5 는 대상 파일이 없어 저절로 참인 단언(크기·금지 문자열) — 스킬이 생긴 뒤 실제로 잰다.
- **평가 결과 (skill-creator, iteration-1, 결과 화면 `…/tmp/eval/<스킬>-workspace/iteration-1/review.html`)**
  | 스킬 | 있음 | 없음 | 차이 | 차이를 낸 곳 |
  |---|---|---|---|---|
  | prd-writer (3건) | 100% | 50% | +50%p | 한 줄 아이디어에 질문으로 멈춤(4/4 대 0/4 — 없음은 12주 일정·iOS 를 지어 씀), 계약 형식(없음은 REQ-n·자리 다름) |
  | idea-check (2건) | 100% | 42% | +58%p | 목적 질문 하나(없음은 셋을 묶음), 판정 세 값·대안·현실 과제 |
  | intended-vs-implemented (2건) | 100% | 70% | +30%p | 감사 문서·판정 다섯 갈래·양쪽 인용. **단 없음 쪽이 경계 입력을 직접 돌려 마커 블록 데이터 손실을 찾았고 있음 쪽은 놓침** → SKILL.md ③ 에 "경계 입력으로 직접 돌려 본다" 추가 (재평가는 안 함) |
  - prd-writer eval 1(brief 이어받기)은 없음도 5/6 — 변별력 낮음. 다음 반복에서 brief 에 함정(보류 판정·없는 숫자)을 넣어 다시 만든다.
  - intended-vs-implemented eval 2 의 단언 "G3 일치" 는 **내 기대가 틀렸다** — `-eq 1` 산술 비교라 `01` 도 통과. 스킬의 `어긋남` 판정이 맞다. 단언을 고쳐 채점했다.
- **평가가 공장 결함을 찾음 → 백로그 `docs/exec-plans/backlog/marker-block-sync-data-loss.md`**
  - `harness_sync_marker_block` 은 END 마커가 없으면 BEGIN 뒤 사용자 내용을 지운다 (코드 확인).
  - `[[ ${VAR:-0} -eq 1 ]]` 산술 비교가 변수 값 안의 `$(…)` 를 실행한다 (**재현**: `a[$(touch PWNED)]` → PWNED 생성). `lib/*.sh` 에 같은 모양 19곳. 보안 — 이 계획 범위 밖이라 고치지 않고 보고.
  - docs-templates 설치는 `*.md`·`*.tmpl` 만 복사 → `.gitkeep` 이 소우주에 안 간다.
- **평가가 우리 검사기 결함을 찾음 → 고침**: `check_prd.py` 가 요구사항 절의 모든 `|` 줄을 읽어 둘째 표까지 섞었다. 시험 먼저(빨강 확인) → `first_table` 로 첫 표만.
- **발동 정확도 (skill-creator `run_eval`, 문장 20 × 2회, 모델 claude-opus-5-5, description 고치지 않음)**
  | 스킬 | 오발동 (안 함 10) | 재현율 (함 10) |
  |---|---|---|
  | prd-writer | 0 | 3/10 |
  | idea-check | 0 | 4/10 — 처음엔 오발동 1로 나왔으나 그 문장("누구를 위한 건지 날카롭게 캐물어 줘")은 **내 정답 표시가 틀림** (idea-check 가 맡을 말). `true` 로 고침 |
  | intended-vs-implemented | 0 | 5/10 |
  - 재현율이 낮은 원인은 직전 ui-prototype 과 같다고 본다 — 전역 brainstorming 이 첫 호출을 선점하고 run_eval 은 첫 호출만 본다. 세션 전체를 보는 G8(harness-eval)이 실제 값이다. 정밀도 100% 라 description 반복 개선(run_loop)은 돌리지 않음.
- **사슬 연결 (G6)**: prd-writer 산출 eta-tracking PRD 를 그대로 ui-prototype 에 → 수준 B 판정, 명세표에 FR 16회, `ui-prototype:requires FR-1 … FR-10`. `check_spec.py` 는 종료 1(18건) — 전부 "화면 미작성"(장면 미등록·견본 장면 남음)이고 표 해석·요구 누락·틀 실패 0. 명세표 단계까지만 시킨 평가라 계획의 "check_spec 통과" 는 화면 단계로 미룬다.
- **G8 1차 실행 (2026-10-21 09:50, 사용자 터미널, `.harness/evals/2026-10-21_095034.json`) — 무효**: 36회 중 22회가 `rc=1` "You've hit your session limit · resets 1:30pm" (구독 사용량 한도). 표의 pass@k 4/12 는 실행 실패를 불통과로 센 값이라 판정에 쓰지 않는다. 한도는 이 계획의 평가(실행 23개 + run_eval 120회)가 크게 썼을 가능성이 높다 — 다음부터 대량 평가 전에 호출 수를 먼저 알린다.
  - 유효 14회: chain-01 idea 2/3 · chain-02 idea 3/3 · chain-03 prd 0/3 · chain-04 prd 3/3 · chain-05 proto 2/2(유효분). **brainstorming 선점 0회 · 사슬 스킬 오발동 0회.**
  - chain-03 0/3 은 시나리오 결함 — 프롬프트가 말한 `docs/product/problem-statement.md` 가 픽스처에 없어 모델이 파일부터 찾았다. 문제를 프롬프트 안에 적도록 고침.
- **G8 건너뜀 (2026-10-21, 사용자 결정)**: 재측정 36회(haiku)는 cost-guard 가 막으려는 "비싼 평가" 에 해당하고, 걱정한 위험(사슬 스킬 오발동)은 이미 두 측정에서 0 — run_eval 안 함 문장 60회 오발동 0 · G8 1차 유효 14회 오발동 0 · brainstorming 선점 0. 잃는 것: 시안·대조·공격 시나리오(06~12)의 발동 수치 없음 — 실사용에서 안 불리면 그때 description 을 고친다. 더 싼 판(빈칸 7개 × 1회 = 7회)도 제시했으나 건너뛰기로 정함.
  - 남은 측정: 한도 초기화 뒤 `--only chain-03-prd,chain-05-proto,…,chain-12-attack` 로 측정 안 된 것만 다시.
- R-agent 훅이 평가 실행 dispatch 에 fullstack-developer 를 권했으나 따르지 않음 — 평가 실행은 일부러 성향 없는 general-purpose 여야 한다.
- `tests/harness-eval-test.sh` 가 `tests/agent-evals/` 를 7개로 단언 → 사슬 시나리오는 `tests/agent-evals-chain/` 에.
- `harness-eval --trigger` 는 `evals/trigger-eval.json`(단수)을 읽고, skill-creator·ui-prototype 은 `trigger-evals.json`(복수). 새 스킬은 skill-creator 관례(복수)를 따름.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:

## 9. 리뷰 반영 (2026-10-21)

planner-lite 11건 · architect-lite 10건. 받아들임 20, 손볼 것 없음 1.

| 출처 | 지적 | 처리 |
|---|---|---|
| P1 HIGH | 시험을 Step 6 에 처음 씀 | Step 1 을 시험 골격·빨강 확인으로 |
| P2 HIGH | 평가가 끝에 몰림·기준 모호 | 스킬마다 작성→평가→등록 한 단위(Step 3~5), 통과율 ≥ 80% |
| P3 HIGH | brainstorming 선점 합격선 없음 | G8 합격선·미달 시 대응. 단 제안된 11/12 는 직전 실측상 맞출 수 없어 측정 방식을 harness-eval(세션 전체) 로 바꾸고 9/12 |
| P4 MED | G3·G5 사람 판정 | `check_prd.py` + 평가 단언 정규식 |
| P5 MED | grep 이식성·NOTICE 오탐 | `grep -rciE … --exclude=NOTICE.md`, 단어 경계 |
| P6 MED | Apache 요건 기계 검증 없음 | G1 (d) |
| P7 MED | 고아 검사 때문에 등록 지연 불가 | Step 1 에서 등록 |
| P8 MED | 프리셋 등록 시점 | 스킬마다 완성 직후 등록 + 무결성 시험 |
| P9 LOW | Step 2~4 한 절 | 분리 |
| P10 LOW | 완료 조건·되돌리기 없음 | 5-bis 끝에 추가 |
| P11 LOW | `다음:` 줄 검증 없음 | G1 (e) |
| A1 HIGH | 계약이 흩어짐 | 정본 contract.md 하나, 나머지는 가리킴 (G2) |
| A2 HIGH | 비덮어쓰기로 계약 어긋남 | 정본을 스킬 폴더로, README 는 안내 + 버전 줄 |
| A3 HIGH | `<이름>` 규칙 없음 | ui-prototype 과 같은 정규식, 정하는 시점·충돌 묻기 |
| A4 HIGH | PRD 여럿·갱신·FR 안정성 | 5-2 고르기·갱신·FR 재사용 금지 |
| A5 MED | 옛 위치 호환 | 찾기 순서를 계약에 한 번, 둘 다 있으면 product-specs + 보고 |
| A6 MED | FR 없는 문서·requires 형식 | **형식은 손볼 것 없음** — `FR-1` 이 `spec-table.md:37` 의 `[A-Z]+-[0-9]+` 에 맞음. 폴백만 계약에 추가 |
| A7 MED | 경계가 문구 하나에 의존 | description 을 한국어 말 예시로 시작 + G8 실측 |
| A8 MED | 아이디어 단계 "기획서 써 줘" | 5-1 규칙 한 줄 |
| A9 LOW | 템플릿이 계약 겸함·NOTICE 중복 | 템플릿은 양식만, NOTICE 는 스킬마다 두는 이유 G9 |
| A10 LOW | 되돌리기·계약 시험 | 5-bis 되돌리기, G1 (f) |
