# 2026-10-20-ui-prototype-skill — 문서에서 눌러 보는 디자인 시안을 만드는 스킬

> 출처 작업: 하류 Nbbang-Run (2026-10-20). 계획 `docs/exec-plans/active/2026-10-20-prototype-core-loop.md`,
> 산출 `docs/prototypes/core-loop/` (9파일) + `docs/prototypes/core-loop.html` (단일 파일), 아티팩트 1건.
> 사용자 평가 (2026-10-20): "이거 너무 맘에 든다. 이거 스킬로 만들자. 이거 시안 만드는거."
> 사용자 요구 (2026-10-20): 설계·기획서나 계획서가 있으면(없으면 보강해서) 그 문서에 따라 **왼쪽 메뉴**(화면 목록)와 **오른쪽 화면**(앱·웹 등 틀)을 만들고, 문서에 따른 기능과 단계를 눌러 볼 수 있게.

---

## 0. 다음 세션 시작점

**진행: Step 1~7 구현 완료 (2026-10-20, 사용자 "쭉 한번에 진행하자"). 남은 것은 커밋과 Step 8 전파 — 둘 다 사람이 정한다.**

| 단계 | 상태 |
| --- | --- |
| Step 0 계획 문서 | 완료 — planner-lite 리뷰 17건 반영 (§8) |
| Step 1 시작 틀 **재설계** (틀 4종) | 완료 — 4폭 × 2테마 × 틀 5 × 장면 3 = 120조합 페이지 넘침 0 |
| Step 2 명세표 규약·검사 스크립트 | 완료 — `spec_table.py` 분리, 실패 9종 + 알림 2종 |
| Step 3 빌드 스크립트 | 완료 — `artifact_strip.py` 분리, 하류 실제 시안 2개(59·15장면) 빌드 통과 |
| Step 4 시험 (node·python만) | 완료 — `ui-prototype-build-test.sh` 40/40, 빨강(36 실패) 먼저 확인 |
| Step 5 SKILL.md·참고 문서 | 완료 — SKILL.md 117줄 + references 5 + spec-table 양식 |
| Step 6 스킬 평가 (skill-creator) | 완료 — 통과율 100% vs 17%, 발동 정확도는 §7 참고 |
| Step 7 프리셋 등록·문서 수치·전체 시험 | 완료 — harness.conf 등록, 수치 7종·140개, 전체 시험 결과는 §2 G8 |
| Step 8 전파 | 사람 승인 후 |

## 1. 동기 (Why)

- Nbbang-Run에서 화면 흐름 문서(51화면)를 끝낸 뒤 "핵심 고리"만 먼저 눌러 보는 디자인 시안으로 만들었다. 13화면(상태별 16장면), 의존성 없는 HTML/CSS/JS 9파일.
- 사용자가 결과를 보고 바로 스킬로 만들자고 했다. 같은 일이 다른 프로젝트에서도 반복된다 (기획서 → PRD → 화면 흐름 → **시안**). 시안은 **앱 코드보다 먼저** 만드는 물건이다.
- 지금은 이 과정이 한 세션의 대화 속에만 있다. 실제로 부딪혀 고친 함정(§7)이 다음 프로젝트에서 또 반복될 것이다.
- 기존 스킬로는 비지 않는다:
  - `impeccable` — 디자인 원칙·craft 흐름은 있지만 "눌러 보는 시안 묶음"의 파일 구조·화면 등록·검증·단일 파일 출력이 없다.
  - `frontend-design` — 화면 하나를 잘 만드는 지침. 여러 화면을 흐름으로 잇는 틀이 없다.
  - `webapp-testing` — 이미 있는 앱을 시험한다. 시안을 만들지 않는다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 — 스킬이 §5-2의 흐름(① 선행 조건 → ①-b 명세표 → ② 질문 → ③ 브리프 → ④ 만들기 → ⑤ 기계 검사 → ⑥ 시각 점검 → ⑦ 출력 → ⑧ 수정·이어 붙이기)을 순서대로 시키고, 관문(명세표·브리프 확정)마다 멈춘다
      `grep -cE '^## ' assets/skills/ui-prototype/SKILL.md` → 10 (9단계 모두 절, + 참고 문서). 평가 B·C 가 관문에서 실제로 멈춤
- [x] G2 — 시작 틀의 예시 시안을 node로 불러 장면 3개가 등록되고 각 장면의 render()가 오류 없이 HTML을 낸다 (브라우저 없이)
      `bash tests/ui-prototype-build-test.sh` → 40/40
- [x] G2b — (Playwright 있을 때) 틀 4종이 장면별로 적용되고, 폭 1280·768·375·360 × 라이트·다크에서 **페이지** 가로 넘침 0. `file://` 로 열어도 뜬다
      시작 틀 120조합(4폭 × 2테마 × 틀 5 × 장면 3) 페이지 넘침 0, 축소 데스크톱 틀 실제 click 이동 확인. **`file://` 직접 열기는 Playwright 가 막아 못 함** — 모듈·fetch 0 검사(시험에 포함)로 갈음
- [x] G3 — `build_single.py` 가 시안 폴더를 단일 HTML(문서 뼈대 포함)과 아티팩트용 파일로 만든다. 로컬 CSS·JS 참조 0, 허용 목록(Google Fonts) 밖 외부 참조 0, 아티팩트용은 첫 글자가 `<title>` 이고 `<html`·`<head`·`<body`·`</body>` 없음
      `bash tests/ui-prototype-build-test.sh` → 통과 + 빌드 결과를 브라우저로 열어 장면 3·15 확인
- [x] G3b — `check_spec.py` 가 망가뜨린 입력 네 가지를 각각 잡는다: (a) 1차 명세표 장면 ≠ 등록 장면 (b) 명세표에 없는 `data-go` 대상 (c) 범위 안 요구 ID 누락 (d) 허용 밖 글자가 든 화면 번호. 그리고 (e) `index.html` 에 로드 태그가 빠진 화면 파일
      `bash tests/ui-prototype-build-test.sh` → (a)~(e) + (f) 틀 불일치 + (g) 명세 행동이 화면에 없음 + 알림(실패 아님) 모두 통과
- [x] G3c — skill-creator 평가에서 입력 수준 B·C 프롬프트에 스킬이 명세표(가정 번호 포함)를 먼저 내고 확정받은 뒤 그린다
      B: 수준 B 판정 + 23장면 명세표 + 가정 P1~P7, 파일 0 으로 멈춤. C: 수준 C 판정 + 보강 질문 3 + 디자인 질문 3, 파일 0
- [x] G4 — 시작 틀·스크립트 파일마다 400줄 이하, 한 파일 한 책임 (R-size, R-struct)
      최대 125줄(check_spec.py)·117줄(registry.js). check-structure 경고 0, complexity 0
- [x] G5 — skill-creator 평가: 시험 프롬프트 3개(수준 A·B·C)에서 스킬 있음이 없음보다 낫다
      `aggregate_benchmark` → 통과율 100% vs 17% (+83%p), 시간 309.7초 vs 308.5초, 토큰 146,825 vs 132,717
- [x] G6 — 발동 정확도: 발동해야 할 질의 10 · 비슷하지만 발동하면 안 될 질의 10, 시험 세트 정답률 기록
      run_loop 5회, 최고 시험 세트 4/8 질의 (1회차 = 원래 description 그대로 유지). 정밀도 100%(엉뚱한 발동 0), 재현율 낮음 — §7
- [x] G7 — `harness` 프리셋에 등록, 프리셋 무결성 시험 통과
      `bash tests/preset-integrity-test.sh` → conf 30개 참조 104개 유효
- [x] G8 — 공장 전체 시험 통과, 고아 시험 0 (새 시험을 `run-all.sh` 목록에 넣음)
      전체 1회: 등록 140 · 고아 0, 실패 2 → ① `harness-hooks-smoke` 의 생성 CLAUDE.md 101줄(이번 변경 원인 — 아래 §8) 고친 뒤 통과(100줄)
      ② `hermes-keys-test` 체크섬 단언 1건 — 단독 3회 재실행 48/48 통과, 이번 변경과 무관한 흔들림(4비트 체크섬을 우연히 통과하는 오타)
- [ ] G9 — (Step 8) 전파: 등록 소우주 전부에 `.claude/skills/ui-prototype/` 이 깔리고, 소우주마다 설치 영수증 경로만 커밋·푸시
      `bash update-all.sh` 뒤 소우주마다 `test -f .claude/skills/ui-prototype/scripts/check_spec.py` + `git status` 깨끗
      `bash tests/run-all.sh --check-orphans && bash tests/run-all.sh`

## 2-bis. 착수 전 확인한 사실 (2026-10-20)

| 확인한 것 | 결과 |
| --------- | ---- |
| 스킬 위치 규약 | `assets/skills/<이름>/SKILL.md` (+ `reference/`·`scripts/` 등) — 예: `impeccable`, `webapp-testing` |
| 등록할 프리셋 | `presets/workflow/harness.conf` 에 `SKILLS+=(...)` 목록 있음 (harness-boundary-check · run-to-the-end 등 6개) |
| impeccable 등록처 | `presets/framework/svelte.conf` 에만 → react·vue·프론트엔드 없는 프로젝트엔 없음 (§5-6 폴백 필요) |
| 같은 이름 스킬 | `assets/skills/` 에 `ui-prototype` 없음 |
| 시험 등록 규약 | `tests/run-all.sh` 는 목록에 적힌 시험만 돌리고, `tests/*-test.sh` 가 목록에 없으면 고아로 실패 (`--check-orphans`) |
| 하류 원본 | Nbbang-Run `docs/prototypes/core-loop/` — index.html 43줄, tokens.css 120, components.css 205, shell.css 85, registry.js 94, parts.js 100, content.js 43, screens-participant.js 249, screens-runner.js 195 — 합계 1,134줄 (`wc -l`, 커밋 전) |
| 하류 구조의 한계 (리뷰 확인) | `shell.css` 의 `.device` 가 390×844 고정, `registry.js` 는 `#device` 하나에 innerHTML 교체, `register()` 에 틀 칸 없음, `.shell` 최대 폭 1120px → 1280·1440 틀 불가. **옮기기가 아니라 재설계 필요** |
| 하류 검증 결과 | 장면 16 · 문법 오류 0 · 금지어 0 · 가로 넘침 0(14화면) · 클릭 경로 2개 끝까지 통과 · 1280(라이트·다크)/375(라이트) 시각 확인 |
| 하류 프리셋 | Nbbang-Run `presets.lock` 에 svelte 있음 |
| 하류 2·3차 (착수 시 재확인) | `core-loop` → `customer-app`(51화면 59장면) 으로 이름이 바뀌었고 `admin-web`(14화면 15장면)이 생김. 관리자 시안은 고객 앱의 토큰·등록부를 `../customer-app/...` 상대 경로로 재사용하고 `.device.browser` 로 웹 틀을 얹음. `check-links.js`(30줄)가 `collect_scenes.js` 역할을 이미 함 — index.html 의 로드 순서를 읽어 vm 으로 실행 |
| 하류 2·3차 회고 | ① 들어오는 버튼 없는 장면을 늦게 발견 → 검사 기본 출력에 넣자는 제안 ② 폭 1280/768/375/360 × 라이트·다크로 넘침 0 ③ 화면 목록 묶음 순서가 등록 순서에 묶임 ④ 요소 스크린숏이 장면을 바꾸는 함정 재발 ⑤ 정해지지 않은 숫자는 "N" ⑥ 금지어 검사 목록이 원문과 달라 기계 검사가 놓침 |
| 설치 범위 | 등록 프로젝트 12곳 전부 `presets.lock` 에 `harness` 있음 → `harness.conf` 등록 = 설치·전파 시 자동 설치 (사용자 요구 "설치하거나 전파하면 자동으로 깔리는 기본기능", 2026-10-20) |

## 3. 비목표 (Out of Scope)

- 실제 앱 구현(Svelte·React 코드 생성). 이 스킬은 **시안**만 만든다.
- 제품 전체의 화면 흐름 문서(하류 51화면 같은)를 다 쓰는 일. **단, 시안 범위의 "시안 명세표"는 이 스킬이 문서에서 만들고, 문서가 부족하면 보강한다** (§5-4).
- 깊은 디자인 맥락 만들기 — `impeccable teach` 가 있으면 그쪽. 없으면 최소 질문 3개로 대신한다 (§5-6).
- Figma 등 외부 디자인 도구 연동.
- 공장 시험 묶음에서 브라우저 검사 (Playwright 보장 없음 — G2b는 스킬 실행 중 검사).

## 4. 영향 영역

- **신규 파일 목록 (파일별 책임 1줄)**:
  - `assets/skills/ui-prototype/SKILL.md` — §5-2 흐름과 각 단계의 판단 기준 (언제 묻고, 무엇을 확정받고, 무엇을 검사하나)
  - `assets/skills/ui-prototype/references/spec-from-docs.md` — 문서 → 시안 명세표: 수준 판정(A·A+B·B·C), 핵심 고리 찾기, 화면 쪼개기, 근거·가정 표기, 보강 질문 3개
  - `assets/skills/ui-prototype/references/structure.md` — 시안 폴더 구조, 각 파일 책임, 화면 등록 규약, 틀 지정·전환 규칙
  - `assets/skills/ui-prototype/references/content-rules.md` — 표시 내용 규칙: 문서에 있는 예시만, 출처 주석, "예시" 표기, 숫자를 명세 예시와 맞추기
  - `assets/skills/ui-prototype/references/verification.md` — 기계 검사 명령, 브라우저 절차(전 장면 넘침·틀별 폭×테마 스크린숏·클릭 경로)
  - `assets/skills/ui-prototype/references/pitfalls.md` — 실측 함정과 해결 (§7)
  - `assets/skills/ui-prototype/assets/spec-table.md` — 시안 명세표 빈 양식 + 기계 판독 규약 (§5-4)
  - `assets/skills/ui-prototype/assets/template/index.html` — 셸 마크업, 스크립트 로드 순서
  - `assets/skills/ui-prototype/assets/template/styles/tokens.css` — 토큰 뼈대: 색 역할 자리·글자 5단계·4pt 간격·라이트/다크 3블록
  - `assets/skills/ui-prototype/assets/template/styles/components.css` — 공통 부품: 버튼 위계·시트·탭 바·입력·알약·사진/지도 자리
  - `assets/skills/ui-prototype/assets/template/styles/shell.css` — 셸: 왼쪽 화면 목록 + 오른쪽 무대(폭 제한 없음), 좁은 화면 배치, 틀 전환 도구
  - `assets/skills/ui-prototype/assets/template/styles/frames.css` — 틀 4종(`phone`·`tablet`·`browser`·`desktop`) 크기·테두리·좁은 화면 규칙 (`.device[data-frame]`)
  - `assets/skills/ui-prototype/assets/template/scripts/config.js` — `NB.config`: 시안 이름·기본 틀·모바일 폭 기준 (값 하나로 JS·CSS가 같은 기준을 씀)
  - `assets/skills/ui-prototype/assets/template/scripts/shell/registry.js` — (공통 장치, 시안마다 손대지 않음) 화면 등록·이동·화면 목록·테마 전환
  - `assets/skills/ui-prototype/assets/template/scripts/shell/frame.js` — (공통 장치) 장면별 틀 적용·틀 전환 덮어쓰기·태블릿 가로세로·좁은 화면 판정·축소 맞춤 (착수 시 registry.js 에서 분리 — 한 파일 한 책임)
  - `assets/skills/ui-prototype/assets/template/scripts/parts.js` — 공통 부품 HTML 함수 뼈대
  - `assets/skills/ui-prototype/assets/template/scripts/content.js` — 표시 내용 자리 + 필수 키 목록(`note`)
  - `assets/skills/ui-prototype/assets/template/scripts/screens-example.js` — 예시 장면 3개: phone 목록 → phone 상세(시트 1개) → browser 1개 (틀 섞임)
  - `assets/skills/ui-prototype/assets/template/spec.md` — 예시 시안의 명세표 (3장면)
  - `assets/skills/ui-prototype/scripts/collect_scenes.js` — node로 `index.html` 의 로드 순서(`../` 공유 파일 포함)대로 시안 스크립트를 실행해 각 장면 render() → `{id, frame, group, gos[]}` + 로드 안 된 화면 파일 JSON 출력
  - `assets/skills/ui-prototype/scripts/spec_table.py` — 명세표(`<!-- ui-prototype:spec v1 -->` 아래 첫 표)와 요구 목록 줄을 읽어 행 목록으로 (착수 시 check_spec.py 에서 분리 — 읽기와 대조는 다른 책임)
  - `assets/skills/ui-prototype/scripts/check_spec.py` — 명세표 ↔ `collect_scenes.js` 결과 대조 (G3b 다섯 검사 + 틀 불일치·명세 행동이 화면에 없음 = 실패) + 들어오는 버튼 없는 장면·아직 등록 안 된 2차 대상(알림, 실패 아님)
  - `assets/skills/ui-prototype/scripts/build_single.py` — 시안 폴더 → 단일 HTML + 아티팩트용 파일 (HTML 파서 기반, `../` 공유 파일도 펼침)
  - `assets/skills/ui-prototype/scripts/artifact_strip.py` — 단일 HTML → 아티팩트용 본문(문서 뼈대 제거·`<title>` 맨 앞, 스크립트·스타일·주석 안은 보호) (착수 시 build_single.py 에서 분리)
  - `assets/skills/ui-prototype/evals/evals.json` — skill-creator 시험 프롬프트 3개 (수준 A·B·C)
  - `assets/skills/ui-prototype/evals/trigger-evals.json` — 발동 정확도 질의 20개
  - `tests/ui-prototype-build-test.sh` — node·python만: 예시 시안 등록·render, build 출력 규약, check_spec 망가뜨린 입력 다섯 가지 (망가뜨린 입력은 시작 틀 복사본을 시험 안에서 고쳐 만든다 — 별도 픽스처 폴더를 두면 틀이 바뀔 때 픽스처만 낡는다)
- 수정: `presets/workflow/harness.conf` (`SKILLS+=(ui-prototype)`), `tests/run-all.sh` (목록에 새 시험), README·CLAUDE.md 수치 블록(스킬 수)
- 룰: R-size(400), R-struct, R-declare(이 §4 선언), 스킬 개발 규칙(skill-creator 필수)
- 데이터: 없음
- 외부 의존: node (`collect_scenes.js`·`node --check` — 공장 시험이 이미 node 사용), python3, Google Fonts(선택), Playwright MCP(선택, G2b)

## 5. 스킬 설계

### 5-1. 이름과 발동 설명 (초안 — Step 6에서 다듬음)

- 이름: `ui-prototype`
- description 초안:
  > 기획서·PRD·화면 흐름 문서(없으면 짧게 보강)에서 눌러 보는 디자인 시안을 만든다 — 왼쪽 화면 목록 + 오른쪽 화면(휴대폰 앱·웹·태블릿·관리자 데스크톱 틀), 화면 안 버튼으로 다음 단계로 이동, 라이트·다크, 단일 HTML과 아티팩트로 출력. 사용자가 "시안 만들어", "와이어프레임", "화면 흐름을 눌러 볼 수 있게", "프로토타입", "목업", "기획서로 화면 보여 줘" 처럼 **여러 화면을 이어서 보는 결과물**을 원하면, 앱 코드가 아직 없어도 이 스킬을 쓴다. 이미 만든 시안을 고치거나 2차 화면을 이어 붙일 때도 쓴다. 화면 하나만 꾸미거나 실제 앱 코드를 짜는 일에는 쓰지 않는다.

### 5-2. SKILL.md 흐름

| 단계 | 하는 일 | 관문 | 하류에서의 근거 |
|---|---|---|---|
| ① 선행 조건 | (a) `docs/prototypes/<이름>/` 이 이미 있으면 **이어 붙이기 모드** → ⑧로 (b) 디자인 맥락 확인 — 없으면 §5-6 (c) 가진 문서의 수준 판정 (§5-4) — 판정을 한 줄로 보여 줌 | 판정 확인 | `.impeccable.md` 작성 후 시작 |
| ①-b 시안 명세표 | 문서에서 메뉴·화면·버튼 연결·근거를 `spec.md` 로 만든다. 수준 C면 보강 질문 3개 → 짧은 브리프 먼저. 문서에 없어 정한 것은 가정 번호(P1…)로 모음 | **명세표 확정** | 화면 흐름 문서 → 13화면 16장면 선정 |
| ② 질문 | 최대 3개, 명세표·문서에 답이 있으면 생략: 범위(핵심 고리부터 / 전체) · 완성도(디자인 입힌 시안 / 흑백 뼈대) · 틀(앱 / 웹 / 태블릿 / 관리자 / 섞임). 추천안을 첫 선택지로 | — | 51화면 → 13화면, 사용자가 추천안 선택 |
| ③ 브리프 | 실행 계획서에 시안 이름(slug)·화면 범위·시각 방향·글꼴 근거·파일 목록(§4 형식)·검증 명령 | **브리프 확정** | `2026-10-20-prototype-core-loop.md` §5 |
| ④ 만들기 | 시작 틀을 `docs/prototypes/<이름>/` 로 복사 → 토큰을 맥락에서 채움 → 공통 부품 → 역할별 화면 파일. 화면은 명세표 행을 그대로 따른다. 표시 내용은 문서 예시만 | — | 9파일, 화면 파일은 역할별 |
| ⑤ 기계 검사 | `node --check` · `check_spec.py`(장면 수·끊긴 버튼·요구 누락·번호 글자·로드 태그) · 금지어 grep · 줄 수 · 금지 CSS 패턴 | 전부 통과 | 금지어 검사가 내 문구 "마진" 적발 |
| ⑥ 시각 점검 | (Playwright 있을 때) 로컬 서버 → 전 장면 페이지 넘침 → 틀별 폭(1280·375)×테마 스크린숏 → 명세표의 고리를 실제 click()으로 끝까지 → 고친 뒤 다시. 없으면 사용자에게 확인 요청 | 고친 뒤 재확인 | 결함 6건 발견·수정 (§7) |
| ⑦ 출력·보고 | `build_single.py` → `docs/prototypes/<이름>.html` + 아티팩트(도구 있을 때만). 보고는 "확인한 것 / 못 한 것 / 내가 정한 것(가정)" | — | 아티팩트 + `core-loop.html` |
| ⑧ 수정·이어 붙이기 | 피드백을 화면 번호로 받아 나눈다 — **기능·흐름 변경**: `spec.md` 먼저 고침 → 화면 → ⑤⑥ / **보기만 변경**: CSS·부품만 → ⑥. 2차 추가: 명세표의 2차 행을 1차로 올리고 화면 파일 추가 → ⑤⑥⑦. 단일 HTML은 덮어쓰고 아티팩트는 같은 경로로 다시 게시(같은 주소 유지) | 바뀐 명세표 확인 | 사용자가 아티팩트에서 장면을 고치고 두 번 로컬로 반영 |

**원칙: 명세표가 원본이고 화면 파일이 따라간다.** 기능·흐름을 바꾸는 요청은 반드시 명세표부터 고친다 — 그래야 `check_spec.py` 가 다음 수정에서도 어긋남을 잡는다.

### 5-3. 시안이 지키는 규약 (시작 틀에 박음)

- **위치·이름**: `docs/prototypes/<이름>/`(원본: `index.html`·`spec.md`·`styles/`·`scripts/`) + `docs/prototypes/<이름>.html`(단일 파일). `<이름>` 은 영문 소문자·숫자·`-` (예: `core-loop`, `admin-v1`), ③에서 확정. 한 저장소에 여러 시안이 폴더별로 공존한다. 아티팩트 제목은 `<제품> <이름> 시안`
- **`file://` 로 열려야 한다** → ES 모듈·fetch 금지, 일반 `<script src>` 만. 로드 순서: config → content → shell/frame → shell/registry → parts → screens-* → `NB.start()`. 화면 파일을 추가하면 `index.html` 로드 태그도 추가 (`check_spec.py` 가 누락 검사)
- **화면 등록**: `NB.register({ id, group, name, state?, caption?, frame?, render(), mount?(root) })`. 화면 안 이동은 `data-go="ID"`. 상태별 장면은 같은 화면 번호에 접미사(EB-01a·b·c)
- **화면 번호 글자**: `^[A-Z]{1,4}-[0-9]{2}[a-z]?$` (예: `SD-01`, `EB-01a`). 주소 `#ID` 로 바로 열기 — 아티팩트 해시 허용 글자 안에 든다. 문서 번호가 이 규칙에 안 맞으면(한글·공백) 명세표에서 새 번호를 붙이고 원래 번호는 근거 칸에 남긴다
- **장면 사이 상태**: 핵심 값은 `NB.state` 로 이어 흐름이 말이 되게 (예: 결제 후 홈에 진행 중 칩)
- **디자인 원칙**: `.impeccable.md` 를 따른다. 금지: 색 띠 테두리, 그라데이션 글자, 카드 안 카드
- **`content.js` 필수 키**: `note`(화면 목록 아래 "표시 내용 출처" 안내). 나머지는 시안마다 자유

### 5-4. 문서에서 메뉴와 화면 만들기 — "시안 명세표"

**가운데 산출물 = `docs/prototypes/<이름>/spec.md`.** 왼쪽 메뉴와 오른쪽 화면이 둘 다 이 표 하나에서 나온다. 표를 확정받은 뒤에 그린다.

**기계 판독 규약** (`assets/spec-table.md`, `check_spec.py` 가 이대로 읽음):

```markdown
<!-- ui-prototype:spec v1 -->
| 범위 | 그룹 | 번호 | 이름 | 상태 | 틀 | 보여 주는 것 | 행동 | 근거 |
|---|---|---|---|---|---|---|---|---|
| 1차 | 참여자 | SD-01 | 사다드림 홈 | - | phone | 엔빵 목록(1인 합계·달성률·남은 시간) | 목록 항목→EB-01a; 엔빵 열기→RN-01 | PRD SADA-01, COMMON-03 |
| 1차 | 참여자 | EB-01a | 엔빵 상세 | 모집중 | phone | 세 칸 금액, 픽업 지도 | 참여하기→EB-02 | PRD COMMON-04; 가정 P1 |
| 2차 | 관리자 | AD-01 | 오늘 할 일 | - | desktop | 분쟁·검수 큐 수 | - | PRD ADMIN-05 |
```

- 표는 주석 표지 `<!-- ui-prototype:spec v1 -->` 바로 아래 첫 표. 칸 순서·이름 고정.
- `범위`: `1차` 는 시안에 반드시 등록, `2차` 는 등록 안 해도 됨(등록하면 검사 대상).
- `번호`: §5-3 글자 규칙. 같은 번호 중복 금지.
- `틀`: `phone`·`tablet`·`browser`·`desktop` 중 하나.
- `행동`: `라벨→번호` 를 `;` 로 구분. 행동이 없으면 `-`. 시트·같은 화면 안 변화는 같은 번호를 다시 가리켜도 됨.
- `근거`: 요구 ID(`[A-Z]+-[0-9]+`)·문서 위치·`가정 P<n>` 를 `,` 또는 `;` 로 나열.
- 범위 안 요구 ID 목록은 명세표 아래 `<!-- ui-prototype:requires ... -->` 한 줄로 적는다 (예: `SADA-01 COMMON-03 COMMON-04`). `check_spec.py` 가 이것과 근거 칸을 대조.

**입력 수준 판정** (판정 결과를 한 줄로 보여 주고 확정받는다):

| 수준 | 조건 | 스킬이 하는 일 |
|---|---|---|
| A | 범위 후보 화면 모두가 문서에 번호·행동(다음 화면)까지 있음 | 범위만 고르고 문서를 명세표로 옮김. 하류 엔빵런이 이 경우 |
| A+B | 화면 흐름 문서가 일부 화면만 있음, 또는 문서끼리 충돌·낡음(관련 기획서가 더 나중에 바뀜) | 있는 화면은 옮기고, 없는 화면은 B 방식으로 만들어 `가정` 표시. 충돌은 어느 문서를 따랐는지 근거 칸에 적고 목록으로 확인받음 |
| B | 기획서·PRD·계획서만 (화면 정의 없음) | ① 역할 → 그룹 ② **핵심 고리** 찾기: 사용자가 가치를 얻는 한 바퀴(돈·예약·주문 같은 주고받음이 끝나는 경로) ③ 고리를 화면 단위로 쪼갬 ④ 요구·규칙을 화면에 매핑해 근거 칸 채움 ⑤ 문서에 없어 정한 것은 `가정 P<n>` |
| C | 한두 줄 아이디어뿐 | **보강**: 질문 3개 — 누가 쓰나(역할) · 무엇을 끝내면 성공인가(한 바퀴) · 돈이나 약속이 오가나(위험한 화면) → `docs/design-docs/prototype-brief.md` 를 짧게 쓰고 확정 → 수준 B |

**보강 규칙**:

- 문서에 없는 화면·버튼·규칙은 근거 칸에 `가정 P<n>` 을 붙이고 명세표 아래 목록으로 모아 확정받는다 (하류의 PRD 가정 A1~A48, 화면 흐름 가정 F1~F8과 같은 방식).
- 화면에 들어갈 값은 문서에 있는 예시만. 없으면 자리 표시 + "예시" 표기.
- 핵심 고리부터 그린다. 나머지는 `2차` 행으로 남긴다 (하류: 51화면 중 13화면).

### 5-5. 화면 틀 — 앱·웹·태블릿·데스크톱

시안의 모양은 언제나 **왼쪽 화면 목록 + 오른쪽 화면**이다. 오른쪽 틀만 제품에 맞게 바뀐다.

| 틀 | 쓰는 곳 | 크기(기준) | 좁은 화면(≤ 모바일 폭 기준)에서 |
|---|---|---|---|
| `phone` | 휴대폰 앱 (하류 엔빵런) | 390×844, 둥근 테두리 | 틀 없이 전체 화면 + 상단 띠의 [화면 목록] |
| `tablet` | 태블릿 앱·키오스크 | 820×1180, 가로·세로 전환 버튼 | 화면 폭에 맞게 `transform: scale()` 축소 |
| `browser` | 웹 서비스·랜딩·웹앱 | 1280×800, 주소창 모양 띠(가짜 주소) | 틀 없이 전체 화면 (반응형 화면이면 그대로 좁아짐) |
| `desktop` | 관리자 웹·업무 도구 | 1440×900, 창 테두리만 | 화면 폭에 맞게 `transform: scale()` 축소 (가로 스크롤 쓰지 않음 → 페이지 넘침 0 유지) |

- 구현: 오른쪽 무대에 `<div class="device" data-frame="phone">` 하나. `NB.go()` 가 장면의 `frame`(없으면 `NB.config.frame`)을 `data-frame` 에 넣고, 크기·테두리는 `frames.css` 가 맡는다. 셸은 폭 제한을 두지 않고 무대가 남은 폭을 쓴다.
- 장면마다 틀이 다를 수 있다 (예: 고객 앱 `phone` + 관리자 `desktop`). 화면 목록은 그룹별로 묶고 항목에 틀 표시를 작게 붙인다.
- **틀 전환 도구**(셸 상단): 장면 지정 틀이 기본. 사용자가 전환하면 **그 세션 동안 모든 장면에 덮어쓰기**, [장면 기본으로]로 해제. 반응형 웹 시안을 같은 장면으로 폭만 바꿔 볼 때 쓴다.
- 축소(`scale`)된 틀 안에서도 클릭이 그대로 동작해야 한다 — 축소는 바깥 상자에만 걸고 안쪽 크기는 그대로.

### 5-6. 디자인 맥락이 없을 때

| 상황 | 처리 |
|---|---|
| `.impeccable.md` 있음 | 그대로 따른다 |
| 없음 + `impeccable` 스킬 있음 | `impeccable teach` 로 보내고 끝나면 ①로 돌아온다 |
| 없음 + `impeccable` 없음 | 질문 3개 — 제품 느낌 세 단어 · 라이트/다크/둘 다 · 피할 것(닮으면 안 되는 앱) → `.impeccable.md` 에 `## Design Context` 를 짧게 써서 확정받는다 (나중에 impeccable 이 깔리면 그대로 이어 씀) |

## 6. 단계 (Steps)

### Step 1. 시작 틀 재설계 [Plan/Impl/Review]
- 입력: 하류 `docs/prototypes/core-loop/` (구조·부품·함정 해결만 가져오고, 엔빵런 화면·번호표 은유·세 칸 금액·PAY-04 숫자는 제거)
- 산출: `assets/template/` (index.html, styles 4, scripts 5, spec.md)
- 바뀌는 구조: `.device[data-frame]` + `frames.css`, `config.js`, `register()` 의 `frame`, 셸 폭 제한 제거, 틀 전환 도구, 모바일 폭 기준을 `config.js` 하나로
- 검증: 예시 시안을 로컬 서버와 `file://` 로 열어 phone·browser 두 틀의 장면 3개가 뜨는지, 틀 전환 도구로 tablet·desktop 도 뜨는지 눈으로 확인 + Step 4 시험

### Step 2. 명세표 규약·검사 스크립트 [Impl]
- 산출: `assets/spec-table.md`, `scripts/collect_scenes.js`, `scripts/check_spec.py`
- `collect_scenes.js`: `vm` 으로 `window = {}` 위에 config → content → registry → parts → screens-* 를 차례로 실행, `NB.start` 는 부르지 않음, 장면마다 render() 결과에서 `data-go="…"` 수집 (render 안의 동적 값도 실제 실행 결과로 잡힘)
- 검증: Step 4 시험의 망가뜨린 입력 다섯 가지

### Step 3. 빌드 스크립트 [Impl]
- `build_single.py`: `html.parser` 로 태그를 읽어 **상대 경로** `<link rel="stylesheet">`·`<script src>` 만 내용으로 바꿈. 외부 링크는 허용 목록(`fonts.googleapis.com`·`fonts.gstatic.com`)만 남기고 그 밖이면 실패. 인라인 JS 안의 `</script` 는 `<\/script` 로 바꿈. 참조 파일이 없으면 실패
- 아티팩트용: `<!doctype>`·`<html …>`·`</html>`·`<head>`·`</head>`·`<body …>`·`</body>`·`<meta charset>`·`<meta name="viewport">` 를 지우고, `<title>` 을 맨 앞으로. `<meta name="claude:viewport-fit-sides">`·폰트 링크·`<style>`·본문은 남김
- 검증: Step 4 시험

### Step 4. 시험 먼저 [Impl]
- `tests/ui-prototype-build-test.sh` (node·python만, 브라우저 없음): 예시 시안 장면 3·render 오류 0 / `node --check` / build 출력 규약(G3) / check_spec 망가뜨린 입력 (a)~(e)
- 먼저 망가뜨린 입력에서 **실패하는 것**을 확인(빨강) → 통과(초록)
- `tests/run-all.sh` 목록에 추가 → `--check-orphans` 통과

### Step 5. SKILL.md·참고 문서 [Impl]
- skill-creator 작성 지침: 명령형, "왜"를 설명, MUST 남발 금지, 본문 500줄 이하, 참고 문서는 언제 읽을지 적고 연결
- 검증: §5-2 단계가 모두 `## ` 절로 있는지, 참고 문서 링크가 실제 파일을 가리키는지

### Step 6. 스킬 평가 [Review]
- skill-creator 흐름: 시험 프롬프트 3개 × 스킬 있음/없음 → 검사 + 사람 검토(평가 뷰어) → 고침
  - 수준 A: "화면 흐름 문서(docs/design-docs/screen-flow) 있는데 핵심 고리만 눌러 보는 시안 만들어 줘"
  - 수준 B: "이 사업기획서랑 PRD로 웹 서비스 시안 만들어 줘, 관리자 화면도 같이" (틀 섞임)
  - 수준 C: "동네 반찬 공유 앱 아이디어 하나 있는데 시안부터 보고 싶어" (보강 질문 → 브리프 → 명세표)
- 발동 정확도 20질의 → `run_loop` 로 description 다듬기. 비슷하지만 발동하면 안 될 예: "버튼 하나 디자인 다듬어 줘", "Svelte로 로그인 화면 구현해", "발표 자료 만들어 줘"
- 검증: G3c·G5·G6 기록

### Step 7. 프리셋 등록·수치·전체 시험 [단순]
- `presets/workflow/harness.conf` 의 `SKILLS+=()` 에 추가, README·CLAUDE.md 스킬 수 갱신 (doc-counts)
- 검증: `bash tests/preset-integrity-test.sh`, `bash tests/run-all.sh` (배경 실행 + Monitor, 실패 줄만)

### Step 8. 전파 [사람 승인 후]
- `update-all.sh` 는 사람이 정한다. Nbbang-Run 은 2026-10-20 에 시안을 `docs/prototypes/core-loop/` 로 이미 옮겼다 — 이 계획의 출력 규약과 같으므로 설치 후 그대로 이어 쓴다

## 7. 발견·예외 — 하류에서 실측한 함정 (→ `references/pitfalls.md`)

| 함정 | 증상 | 해결 |
|---|---|---|
| `file://` 에서 ES 모듈·fetch 차단 | 탐색기 더블클릭 시 빈 화면 | 일반 script 태그만, 전역 `window.NB` 에 등록 |
| 아이콘 svg 크기 미지정 | 버튼 안 svg 가 화면을 덮을 만큼 커짐 | 부품 CSS 에서 svg 마다 width/height 지정 |
| 입력칸 기본 최소 폭 | 좁은 화면에서 가로 스크롤 | `.input{width:100%;min-width:0}` + 그리드 자식 `min-width:0` |
| 로컬 파일에 `[hidden]` 규칙 없음 | `display:grid` 가 `hidden` 을 덮어 목록이 안 닫힘 (아티팩트는 게시 뼈대가 규칙을 넣어 줘서 안 보임) | 셸 CSS 첫 줄에 `[hidden]{display:none!important}` |
| 같은 페이지에서 해시만 바꿔 이동 | Playwright 가 새로 읽지 않아 옛 화면을 찍음 | 주소에 `?v=N` 을 바꿔 붙이거나 `page.evaluate(() => NB.go(id))` |
| 요소 스크린숏 직후 화면이 바뀜 | 찍힌 장면이 요청과 다름 | 전환은 evaluate 로, 전환 직후 해시·제목을 돌려받아 확인한 뒤 찍기 |
| `pkill -f "http.server"` 를 다른 명령과 한 줄에 | 자기 셸까지 죽어(144) 뒤 명령 미실행 | 서버는 `run_in_background` 로, 끄기는 `ps … | grep '[h]ttp.server'` 로 PID 골라 kill |
| Playwright 산출물 | 저장소 루트에 `.playwright-mcp/` 생김 | 점검 끝에 지우고 `git status` 로 확인 |
| 스크린숏 저장 위치 | 작업 디렉터리 밖 경로 거부 | `.playwright-mcp/` 아래로 저장 |
| 한국어 줄바꿈 | "마감"이 "마 감"으로 끊김 | 앱 루트에 `word-break: keep-all` |
| 금지어 | 설명 문구에 금지어가 섞임 | 프로젝트 금지어를 grep 으로 매번 검사 (하류에서 실제 적발) |
| 상태 알약이 줄 폭으로 늘어남 | 그리드 셀 안 inline-flex 가 늘어남 | `justify-self:start` |
| 고정 크기 틀·셸 최대 폭 | 웹·데스크톱 틀이 안 들어감 (리뷰 확인) | `.device[data-frame]` + `frames.css`, 셸 폭 제한 제거 |
| 요소 스크린숏 (2차에서 재발) | 요소를 찍는 순간 장면이 바뀜 | 창 전체 스크린숏으로 찍는다 |
| 화면 목록 묶음 순서 (3차) | 묶음 순서가 파일 등록 순서를 따라 엉뚱하게 나옴 | `NB.config.groups` 로 순서를 적는다 (없으면 등록 순서) |
| 들어오는 버튼 없는 장면 (2차) | 1차부터 비어 있던 버튼을 마지막에야 발견 | `check_spec.py` 가 매번 목록으로 보여 준다. 상태·권한 장면처럼 목록 진입이 맞으면 명세표 근거에 적는다 |
| 정해지지 않은 숫자 (2차) | 지어낸 숫자가 결정처럼 보임 | "N" 으로 표시하고 미결 목록에 잇는다 |
| 금지어 목록이 원문과 다름 (3차) | 기계 검사가 "판매" 단독을 놓침 | 금지어는 프로젝트 원문(법무·PRD)에서 낱말 그대로 옮겨 검사한다 |
| 크기 없는 아이콘 svg (스킬 평가에서 재현) | 평가 A 시안의 카드 안 아이콘이 279px 로 커져 앱 화면 안쪽이 가로로 넘침 (페이지 넘침 검사로는 안 보임) | `NB.icon()` 이 `.icon`(기본 1.25em, flex:none)을 붙임 + 전역 `svg{max-width:100%}`. 검증 절차에 "틀 안 넘침" 측정 추가. 수정 뒤 평가 시안 88조합 넘침 0 |
| 발동 정확도 측정 (Step 6) | 재현율 학습 6~17%·시험 0~17%, 정밀도 100% | 이 컴퓨터의 전역 superpowers 가 "창작 작업 전 brainstorming 먼저" 를 세션마다 강제해 첫 스킬 호출을 선점한다. run_loop 는 첫 호출만 보므로 실제보다 낮게 잰다. 고친 description 4개가 원본을 넘지 못해 원본 유지. 실제 소우주에서는 헤르메스 세션 시작 훅의 관련 스킬 주입이 보완한다 |

## 8. 의사결정 로그

- 2026-10-20: 스킬 이름 `ui-prototype` — 근거: "시안·와이어프레임·프로토타입" 을 모두 덮는 기능 이름. 화면 하나 꾸미기(frontend-design)와 구분
- 2026-10-20: 시작 틀을 스킬에 넣는다 — 근거: skill-creator 지침 "여러 실행이 같은 도우미를 새로 쓰면 스킬에 묶어라". 셸·등록기는 프로젝트와 무관하게 같다
- 2026-10-20: 이번 세션은 계획 문서만, 스킬 파일은 승인 후 — 근거: 공통 스킬 자동 수정 금지 원칙
- 2026-10-20: 문서 → "시안 명세표" → 메뉴·화면, 입력 수준 판정과 보강(질문 3개 + 가정 번호) — 근거: 사용자 "설계기획서나 계획서가 있을 경우(없다면 보강할 수 있게) 메뉴·화면, 그 문서에 따른 기능과 스텝"
- 2026-10-20: 오른쪽 틀 4종(phone·tablet·browser·desktop), 장면별 지정·섞기 — 근거: 사용자 "웹이나 앱이나 등등이 될 수 있도록"
- 2026-10-20 (planner-lite 리뷰 17건 반영, 사용자 승인):
  - Step 1을 "옮기기"에서 **재설계**로 — 하류 셸이 고정 크기 틀 하나뿐
  - 명세표 **기계 판독 규약** 확정 (주석 표지·칸 순서·`라벨→번호;`·요구 목록 줄)
  - 버튼 연결은 **node로 render()를 실행해** 수집 (JS 문자열 정적 검색으로는 동적 값을 못 잡음)
  - **⑧ 수정·이어 붙이기** 단계와 "명세표가 원본" 원칙
  - 등록처를 프론트엔드 프리셋 3개에서 **`harness` 프리셋**으로 — 시안은 앱 코드 이전(기획 단계)에 만드는 물건
  - 디자인 맥락 **폴백**(impeccable 없을 때 질문 3개)
  - 수준 판정에 **A+B 혼합**(일부·낡음·충돌), 판정 결과 확인 관문
  - 출력 규약 `docs/prototypes/<이름>/` + `<이름>.html`
  - 빌드는 **HTML 파서** + 허용 목록(Google Fonts) + `</script` 이스케이프, 아티팩트용 제거 태그 열거
  - 시험은 node·python만, 브라우저 검사(G2b)는 스킬 실행 중으로 분리
  - 틀 전환은 세션 덮어쓰기, 좁은 화면의 desktop·tablet 은 가로 스크롤 대신 축소
  - 화면 번호 글자 규칙, 아티팩트 없는 환경은 단일 HTML까지만 필수
  - 리뷰 16번(예시 장면 수 불일치)은 사실과 달라 반영하지 않음 — "3개 = phone 2 + browser 1" 로 일치

- 2026-10-20: 하류 출처 경로를 `docs/prototypes/core-loop/` · 계획서 `2026-10-20-prototype-core-loop.md` 로 갱신 — 근거: 하류가 "와이어프레임"이 아니라 고충실도 프로토타입이라 이름을 바꾸고 이 계획의 출력 규약에 맞춰 옮김

- 2026-10-20 (착수, 사용자 "쭉 한번에 진행하자" — Step 1~7 승인):
  - 하류 2·3차 회고를 반영한다: 들어오는 버튼 없는 장면은 **알림**으로(실패 아님 — 하류도 상태·권한 장면 7개를 목록 진입으로 두었다), 확인 폭 4개, `NB.config.groups`, `../` 공유 파일 펼침
  - `collect_scenes.js` 는 고정 순서 대신 `index.html` 의 로드 순서를 읽는다 — 하류 `check-links.js` 와 같은 방식이고, 공유 파일(`../`)이 있는 시안도 그대로 돈다
  - 등록처는 `harness` 그대로 — 등록 12곳 전부가 harness 를 써서 "전파하면 자동 설치" 요구를 이미 만족한다. 전역(`_common.conf`)에 두면 공장 저장소 밖 머신에도 깔리지만 시험·명세표 규약이 프로젝트 docs 구조를 전제한다
  - 시작 틀의 공통 장치(`frame.js`·`registry.js`)를 `scripts/shell/` 로 — R-struct 경고(폴더당 5개 초과)를 계기로, 시안마다 손대지 않는 파일과 고치는 파일을 폴더로 가름
  - 평가는 하류 Nbbang-Run 의 실제 기획 문서 사본으로 — 지어낸 입력 문서를 쓰지 않는다. 하류 `docs/prototypes/` 는 답이 새지 않게 복사하지 않음. 평가 작업 폴더는 스킬 폴더 밖(전파 때 같이 깔리지 않게)
  - 발동 측정은 빈 `.claude/` 만 있는 격리 폴더에서 — 공장에서 돌리면 `claude -p` 수백 번이 공장의 헤르메스 훅을 깨워 학습 기록을 오염시킨다
  - description 은 run_loop 결과가 원본을 넘지 못해 바꾸지 않음
  - 생성 CLAUDE.md 가 101줄이 된 것(프리셋 스킬마다 목차 한 줄)을 한도 상향 대신 harness 안내 절의 이어진 두 문장을 한 줄로 합쳐 100줄로 — 100줄은 "목차" 원칙의 강제 장치. **이제 여유 0줄**: harness 에 스킬을 하나 더 넣으면 다시 넘는다

## 9. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
