---
name: ui-prototype
description: 기획서·PRD·화면 흐름 문서에서 눌러 보는 디자인 시안을 만든다 — 왼쪽 화면 목록 + 오른쪽 화면(휴대폰 앱·웹·태블릿·관리자 데스크톱 틀), 화면 안 버튼으로 다음 단계 이동, 라이트·다크, 단일 HTML·아티팩트 출력. 문서가 없거나 한두 줄 아이디어뿐이면 질문 세 개로 보강해서 시작한다. 사용자가 "시안 만들어", "와이어프레임", "프로토타입", "목업", "화면 흐름을 눌러 볼 수 있게", "기획서로 화면 보여 줘", "클릭되는 화면", "UI 초안" 처럼 여러 화면을 이어서 보는 결과물을 원하면, 앱 코드가 아직 없어도 반드시 이 스킬을 쓴다. 이미 만든 시안(docs/prototypes/)을 고치거나 2차 화면을 이어 붙일 때도 쓴다. 화면 하나만 꾸미거나, 실제 앱 코드(Svelte·React)를 짜거나, 발표 자료를 만드는 일에는 쓰지 않는다. Use for clickable multi-screen prototypes, wireframes, or mockups built from planning docs.
---

# ui-prototype — 문서에서 눌러 보는 시안

기획 문서를 **앱 코드보다 먼저** 눈으로 확인하는 시안을 만든다. 결과물은 의존성 없는 HTML/CSS/JS 폴더 하나와 단일 HTML 한 장이다.
왼쪽에 화면 목록, 오른쪽에 화면 틀이 있고, 화면 안 버튼을 누르면 문서에 적힌 다음 단계로 넘어간다.

**원칙: 명세표가 원본이고 화면 파일이 따라간다.** 왼쪽 메뉴와 오른쪽 화면은 둘 다 `docs/prototypes/<이름>/spec.md` 한 장에서 나온다.
기능·흐름을 바꾸는 요청은 반드시 명세표부터 고친다 — 그래야 `check_spec.py` 가 다음 수정에서도 어긋남을 잡는다.

이 스킬 폴더(설치된 프로젝트에서는 `.claude/skills/ui-prototype/`)에 든 것:

- `assets/template/` — 시작 틀. 셸·틀 4종·화면 등록기·공통 부품, 견본 장면 3개
- `assets/spec-table.md` — 명세표 양식과 기계 판독 규약
- `scripts/check_spec.py` — 명세표 ↔ 등록 장면 대조 · `scripts/build_single.py` — 단일 HTML·아티팩트용 출력
- `references/` — 단계별 세부 (각 단계에서 언제 읽는지 적어 두었다)

흐름은 아래 9단계다. **관문**(명세표 확정·브리프 확정)에서는 사용자 확인을 받기 전에 다음 단계로 가지 않는다 — 그리고 나서 고치면 화면 수만큼 다시 그린다.

## ① 선행 조건

1. **이어 붙이기인가.** `docs/prototypes/<이름>/` 이 이미 있으면 새로 만들지 않고 ⑧로 간다.
2. **디자인 맥락.** 프로젝트 루트의 `.impeccable.md` 를 읽는다.
   - 있으면 그 색·글꼴·느낌을 따른다.
   - 없고 `impeccable` 스킬이 있으면 `impeccable teach` 로 맥락부터 만들고 돌아온다.
   - 둘 다 없으면 세 가지를 한 번에 묻는다 — 제품 느낌 세 단어 · 라이트/다크/둘 다 · 닮으면 안 되는 앱. 답으로 `.impeccable.md` 에 `## Design Context` 를 짧게 써서 확정받는다 (나중에 impeccable 이 깔려도 이어 쓴다).
3. **입력 수준 판정.** 가진 문서를 훑어 A · A+B · B · C 중 하나로 판정하고 **한 줄로 보여 준다** (`references/spec-from-docs.md` 1절).

## ①-b 시안 명세표 (관문)

`references/spec-from-docs.md` 를 읽고 `assets/spec-table.md` 양식으로 명세표를 만든다.

- 수준 C 면 먼저 보강 질문 세 개(누가 · 무엇을 끝내면 성공 · 돈이나 약속이 오가나) → 짧은 브리프 확정 → 수준 B 로.
- 문서에 없어서 정한 것은 근거 칸에 `가정 P<n>` 을 붙이고 표 아래 목록으로 모은다.
- 범위 안 요구 ID 는 `<!-- ui-prototype:requires ... -->` 줄에 — 빠진 요구를 기계가 잡는다.

이 단계에서는 표를 대화에 보여 주고(행이 많으면 1차 행 + 가정 목록만) 확정을 받는다. 파일은 ④에서 시안 폴더에 쓴다.

## ② 질문

최대 세 개, 명세표·문서에 답이 있으면 묻지 않는다. 추천안을 첫 선택지로 둔다.

- **범위** — 핵심 고리부터(추천) / 전체
- **완성도** — 디자인 입힌 시안(추천, `.impeccable.md` 를 따른다) / 흑백 뼈대(토큰을 무채색으로)
- **틀** — 명세표의 `틀` 칸으로 정해졌으면 묻지 않는다

## ③ 브리프 (관문)

실행 계획서(`docs/exec-plans/active/YYYY-MM-DD-prototype-<이름>.md`, 프로젝트에 계획서 규약이 없으면 대화에)에 적는다:

- 시안 이름 `<이름>` (영문 소문자·숫자·`-`), 화면 범위(1차 몇 화면·몇 장면)
- 시각 방향과 글꼴 근거 (`.impeccable.md` 의 어느 문장에서 왔나)
- 파일 목록 — 파일마다 책임 한 줄. 화면 파일은 역할별 (`screens-<역할>.js`)
- 검증 명령 (⑤⑥ 그대로)

확정받은 뒤 만든다.

## ④ 만들기

1. 시작 틀을 복사한다: `cp -r <스킬>/assets/template docs/prototypes/<이름>`
2. 견본을 걷어 낸다: `scripts/screens-example.js` 와 그 로드 태그를 지우고, `spec.md` 를 ①-b 의 명세표로 바꾼다.
3. `scripts/config.js` — 시안 이름·기본 틀·묶음 순서. 시안 이름과 `index.html` 의 `<title>` 은 폴더 이름(`sada-core-loop`)이 아니라 사람이 읽는 이름으로 (예: `엔빵런 사다드림 핵심 고리 시안`).
4. `styles/tokens.css` — `.impeccable.md` 에서 색·글꼴을 채운다. 역할 이름(`--accent` 등)은 그대로 두고 값만. 글꼴은 Google Fonts 링크로.
5. `scripts/content.js` — 표시 내용을 **문서 예시만으로** (`references/content-rules.md`). 값마다 출처 주석.
6. `scripts/parts.js` + `styles/components.css` — 여러 화면에 나오는 덩어리를 부품으로.
7. 역할별 화면 파일 — 명세표 행을 그대로 따른다: 행마다 `NB.register`, `행동` 칸마다 `data-go` 버튼. 새 파일은 `index.html` 로드 태그에도.

폴더 구조·등록 규약·틀 4종은 `references/structure.md`. `scripts/shell/` 과 `shell.css`·`frames.css` 는 고치지 않는다 — 고칠 일이 생기면 스킬 쪽 결함이다.
1차가 20화면을 넘으면 두 묶음으로 나눠 중간에 한 번 보여 준다.

## ⑤ 기계 검사

`references/verification.md` 의 ⑤ 명령을 **전부** 돌린다 — 문법 · `check_spec.py` · 모듈/fetch · 줄 수 · 금지어.
`check_spec.py` 가 종료 0 이 될 때까지 고친다. `[알림]` 도 읽는다: 들어오는 버튼 없는 장면이 의도가 아니면 버튼이 빠진 것이다.

## ⑥ 시각 점검

Playwright 가 있으면 `references/verification.md` 의 ⑥ 절차대로: 폭 1280·768·375·360 × 라이트·다크 × 전 장면의 페이지 넘침 0,
틀별 대표 장면 스크린숏(창 전체), 명세표 핵심 고리를 실제 클릭으로 끝까지. 고쳤으면 넘침 검사를 처음부터 다시.
막히면 `references/pitfalls.md` 를 먼저 본다 — 하류에서 실제로 밟은 것들이다.
Playwright 가 없으면 무엇을 봐 달라고 할지 구체적으로 적어 사용자에게 부탁한다.

## ⑦ 출력·보고

`python3 <스킬>/scripts/build_single.py docs/prototypes/<이름> --artifact <임시 경로>` → `docs/prototypes/<이름>.html`.
아티팩트 도구가 있으면 아티팩트용 파일을 게시한다(제목 `<제품> <이름> 시안`). 없으면 단일 HTML 까지가 완료다.

보고는 세 칸으로:

- **확인한 것** — 장면 수, 검사 결과 숫자(실패 0 · 알림 n), 넘침 0 의 폭·테마, 끝까지 누른 클릭 경로
- **못 한 것** — 돌리지 못한 검사와 이유 (예: `file://` 직접 열기)
- **내가 정한 것** — 가정 P 목록과, 문서끼리 달라서 고른 쪽

## ⑧ 수정·이어 붙이기

피드백을 화면 번호로 받아 두 갈래로 나눈다:

- **기능·흐름 변경** (화면 추가·버튼 연결·단계 순서) → `spec.md` 먼저 고쳐 보여 주고 확인 → 화면 파일 → ⑤⑥
- **보기만 변경** (색·간격·문구) → 토큰·부품·`content.js` 만 → ⑥

2차 화면 추가: 명세표의 `2차` 행을 `1차` 로 올리고 화면 파일을 더한다 → ⑤⑥⑦.
단일 HTML 은 덮어쓰고, 아티팩트는 같은 파일 경로로 다시 게시해 주소를 유지한다.
같은 브랜드의 두 번째 시안(예: 관리자 웹)은 복사하지 말고 첫 시안의 토큰·`shell/` 을 `../` 로 불러 쓴다 (`references/structure.md` 끝 절).

## 참고 문서

| 문서 | 읽는 때 |
|---|---|
| `references/spec-from-docs.md` | ① 수준 판정, ①-b 명세표 |
| `assets/spec-table.md` | ①-b 명세표 양식, ⑤ 검사 실패를 고칠 때 |
| `references/structure.md` | ④ 만들기, ⑧ 이어 붙이기 |
| `references/content-rules.md` | ④ 표시 내용, ⑤ 금지어 |
| `references/verification.md` | ⑤ ⑥ ⑦ |
| `references/pitfalls.md` | ⑥ 에서 막혔을 때 |
