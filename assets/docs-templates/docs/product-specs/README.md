# product-specs — 기획 문서 모음

contract-version: 1

기획 하나 = 폴더 하나 (`docs/product-specs/<이름>/`). 같은 이름으로 시안(`docs/prototypes/<이름>/`)이 이어진다.

## 이렇게 말하면 이 문서가 생긴다

| 말 (예) | 스킬 | 남는 것 |
|---|---|---|
| "이거 만들 가치 있나", "아이디어 검증하자" | idea-check | `<이름>/brief.md` |
| "기획서 써 줘", "PRD 만들자" | prd-writer | `<이름>/prd.md` |
| "시안 만들어", "와이어프레임" | ui-prototype | `docs/prototypes/<이름>/` |
| "구현 계획 세우자" | 실행 계획서 양식 | `docs/exec-plans/active/…` (§2 에 FR ID) |
| "기획대로 됐는지 확인해" | intended-vs-implemented | `docs/audits/…-intent-check.md` |

어느 단계에서 시작해도 된다. 앞 문서가 없으면 각 스킬이 질문으로 메운다.

## 규칙의 정본

폴더·이름·필수 칸·FR 번호 규칙은 설치된 스킬의 `.claude/skills/prd-writer/references/contract.md` 에 있다.
이 파일은 안내일 뿐이고, 설치기가 덮어쓰지 않으므로 이 아래에 프로젝트 메모를 적어도 된다.
