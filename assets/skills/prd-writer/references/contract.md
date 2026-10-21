# 기획 문서 사슬 계약

contract-version: 1

기획 문서 사슬(idea-check → prd-writer → ui-prototype → 실행 계획서 → intended-vs-implemented)이 함께 지키는 **유일한 정본**이다.
다른 스킬과 프로젝트의 `docs/product-specs/README.md` 는 이 파일을 가리키기만 하고 규칙을 다시 적지 않는다.
규칙을 바꾸면 위 버전 숫자를 올리고, 프로젝트 README 의 같은 줄과 각 스킬이 말하는 버전도 함께 올린다(`tests/planning-chain-test.sh` 가 대조한다).

## 1. 폴더와 파일

```text
docs/product-specs/
├── README.md              ← 프로젝트용 안내 (사람이 읽음, 덮어쓰지 않음)
└── <이름>/                ← 기획 하나 = 폴더 하나
    ├── brief.md           ← idea-check 가 남김 (만들지 말지 판정)
    └── prd.md             ← prd-writer 가 남김 (요구와 검증)
docs/prototypes/<이름>/    ← ui-prototype 이 남김 (같은 이름)
```

- 실행 계획서는 원래 자리(`docs/exec-plans/active/`)에 두고, §2 목표에 FR ID 를 적는다.
- 의도 대조 결과는 `docs/audits/YYYY-MM-DD-<이름>-intent-check.md`.

## 2. `<이름>` 규칙

- 글자: `^[a-z0-9]+(-[a-z0-9]+)*$` — ui-prototype 의 시안 이름과 같다. 한글 제목은 영문으로 바꿔 제안한다 (예: "공구 대여" → `tool-rental`).
- 정하는 때: 사슬에서 처음 문서를 만드는 스킬이 제안하고 **사용자 확인을 받는다**.
- 같은 이름 폴더가 이미 있으면 "이어 쓸지 / 새 이름인지" 를 묻는다. 묻지 않고 덮지 않는다.

## 3. 어느 기획을 고르나

1. 사용자가 이름을 댔으면 그 폴더.
2. 안 댔고 `docs/product-specs/` 아래 기획 폴더가 하나면 그것.
3. 둘 이상이면 목록(폴더 이름 · prd.md 의 `status` · `updated`)을 보이고 하나를 묻는다. **수정 시각으로 추측하지 않는다.**

## 4. 문서 찾기 순서

1. `docs/product-specs/<이름>/`
2. 옛 위치 — `docs/product/`, `docs/prd/`, `docs/planning/`, `docs/design-docs/prd-*.md`, `docs/design-docs/` 의 기획서·화면 흐름
3. 사용자가 경로를 댄 파일 (언제나 1순위보다도 앞)

같은 기획이 1과 2에 모두 있으면 1을 따르고 "옛 위치에도 문서가 있다" 를 한 줄 보고한다. 옛 위치 문서는 옮기지 않는다.

## 5. brief.md 필수 칸

머리 세 줄 다음, 아래 절을 이 순서로 둔다 (절 번호는 붙여도 되고 안 붙여도 된다).

```text
- verdict: 만든다 | 좁힌다 | 보류
- updated: YYYY-MM-DD
- contract-version: 1
```

`## 문제` · `## 누가 겪나` · `## 지금은 어떻게 버티나` · `## 가장 좁은 시작점` · `## 대안` (2~3개) · `## 가정·열린 질문`

## 6. prd.md 필수 칸

머리:

```text
- status: draft | approved
- updated: YYYY-MM-DD
- contract-version: 1
```

절: `## 문제` · `## 대상 사용자` · `## 목표 지표` · `## 범위` · `## 비범위` · `## 요구사항` · `## 실행 계약` · `## 가정·열린 질문`

`## 요구사항` 아래 첫 표:

| 열 | 값 |
|---|---|
| ID | `^FR-[0-9]+$` |
| 요구 | 한 줄, 사용자가 얻는 것 |
| 검증 | 어떻게 확인하나 — 상태 `유효` 면 비울 수 없다 |
| 우선순위 | `필수` · `권장` · `선택` |
| 상태 | `유효` · `폐기` |

- FR 번호는 **다시 쓰지 않는다.** 지운 요구는 행을 남기고 상태를 `폐기` 로 (계획서 §2 의 FR 참조가 깨지지 않게).
- 문서에 없는 숫자·사실을 지어내지 않는다. 모르는 것은 `## 가정·열린 질문` 에 적는다.
- 검사: `python3 <prd-writer>/scripts/check_prd.py docs/product-specs/<이름>/prd.md` — 종료 0 이어야 사슬 다음 단계로 넘긴다.

## 7. 갱신

- prd.md 는 제자리에서 고친다. git 이력이 버전이다. 고칠 때마다 `updated` 를 바꾼다.
- 사용자가 확정하면 `status: approved`. 확정 뒤 바꾸면 다시 `draft` 로 내리고 무엇이 바뀌었는지 보고한다.

## 8. 하류가 받는 방식

- ui-prototype: 근거 칸과 `<!-- ui-prototype:requires … -->` 에 FR ID 를 그대로 쓴다 (`FR-1` 은 시안 명세표의 요구 ID 형식 `[A-Z]+-[0-9]+` 에 맞는다). 상태 `폐기` 인 요구는 넣지 않는다.
- 실행 계획서: §2 목표 줄에 대응하는 FR ID 를 적는다.
- intended-vs-implemented: FR 행마다 "코드에서 강제되는 곳" 을 찾는다.
- **FR ID 가 없는 문서**(옛 위치·다른 형식)를 받으면 절 제목과 줄 번호로 인용하고, 보고에 "FR ID 없음 — 계약 밖 문서" 를 적는다.
