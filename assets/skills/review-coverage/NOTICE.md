# NOTICE — review-coverage

이 스킬은 아래 원본의 절차와 규칙 문서를 옮기고 고쳤다. 스킬 폴더가 설치 단위라 출처를 폴더마다 둔다.

## 원본

- `alibaba/open-code-review` @ `817ed02d7b1917ec6a36630d926af34661af9b97` (2026-11-19)
  Apache License 2.0, Copyright 2026 Alibaba. 전문: https://www.apache.org/licenses/LICENSE-2.0
  - `skills/open-code-review-delegate/SKILL.md` — 가져온 것: 미리보기 → 규칙 → diff → 파일별 리뷰 → 빠짐률 필수 보고 흐름, 이유 없는 건너뜀 금지
  - `internal/config/rules/rule_docs/*.md` 68개 중 17개 — `references/rules/*.md` 에 **원문 그대로** 둔다
  - `internal/config/rules/system_rules.json` — 위 17개에 해당하는 경로 패턴만 남겨 `references/rules/path_rule_map.json` 으로
  - `internal/diff/git.go` 의 제외 디렉터리 목록

## 바꾼 점

- Go CLI `ocr delegate preview/rule` 대신 python 표준 라이브러리 스크립트(`scripts/`)로 같은 일을 한다. `ocr` 설치가 필요 없다.
- 장부 검사(`check`)를 새로 만들었다 — 원본은 빠짐률을 모델이 스스로 세게 한다. 여기서는 스크립트가 세고 줄 번호가 파일 안에 있는지도 확인한다.
- 잠금 파일·압축본(`*.lock`·`*-lock.json`·`*.min.js`)도 뺀다. 원본은 빼지 않는다.
- 프로젝트 규칙 파일 위치를 `.opencodereview/rule.json` → `.claude/review-rules.json` 으로 바꿨다. 형식은 같다.
- 한국어로 썼다. 규칙 문서는 번역하지 않았다.
