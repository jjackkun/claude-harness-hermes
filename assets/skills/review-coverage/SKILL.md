---
name: review-coverage
description: 코드 리뷰를 할 때 볼 파일을 기계로 고정하고(작업 중 변경·브랜치 범위·커밋 하나), 파일 종류마다 검사 기준을 붙이고, 끝에 "몇 개 중 몇 개를 봤는지"와 지적한 줄 번호가 실제 파일과 맞는지를 스크립트로 검사한다. 사용자가 "리뷰해", "코드 리뷰", "변경 검토해 줘", "이 브랜치 리뷰", "커밋 abc 봐 줘", "PR 전에 훑어 줘" 라고 하거나, code-reviewer 같은 리뷰 에이전트를 부르기 직전·리뷰 결과를 쓰기 직전이면, 단어가 '빠짐'이나 '범위'가 아니어도 반드시 이 스킬을 쓴다. 큰 변경에서 파일 몇 개만 보고 끝내는 일과 줄 번호가 어긋나는 일을 막는다. 코드 품질 정리(simplify)·버그 원인 찾기·문서와 코드 대조(intended-vs-implemented)는 다른 스킬이 맡는다. Use for any code review to pin the file list, attach per-language rules, and verify coverage and line numbers.
---

# review-coverage — 리뷰할 파일을 고정하고, 다 봤는지 센다

## 왜 있나

자연어 지시만으로 돌리는 리뷰는 큰 변경에서 파일 몇 개만 보고 끝내고, 지적한 줄 번호가 실제 자리와 어긋난다.
알리바바 open-code-review(OCR) 가 2년간 사내에서 겪고 고친 문제다. 그들의 답은 "고르기·묶기·위치 확인은 정해진 코드가, 판단만 모델이" 였다.
이 스킬은 그 나눔을 `ocr` 설치 없이 python 표준 라이브러리 스크립트로 옮겼다(출처: `NOTICE.md`).
`git diff` 만 보면 아직 `git add` 하지 않은 새 파일(untracked)은 빠진다 — 스크립트는 이것도 센다.

## 흐름

`R="$(git rev-parse --show-toplevel)/.claude/skills/review-coverage/scripts/review_scope.py"` (공장에서는 `assets/skills/...`)

범위 방식은 셋이다. 세 명령에 **같은 방식 인자와 같은 `--exclude`** 를 넘긴다 — 다르면 `check` 가 빠진 파일·범위 밖 파일로 실패한다. 하위 폴더에서 불러도 경로는 저장소 맨 위 기준이다.

| 리뷰 대상 | 인자 |
|---|---|
| 작업 중 변경 (staged·unstaged·untracked) | 없음 |
| 현재 브랜치 전체 (main 에서 갈라진 뒤) | `--from main` |
| 두 ref 사이 | `--from A --to B` |
| 커밋 하나 | `--commit <해시>` |

### ① 볼 파일 고정

```bash
python3 $R scope [방식 인자] [--exclude 'gen/**,*.pb.go']
```

리뷰할 파일 목록과 뺀 파일(이유 포함)이 나온다. 뺀 것: 삭제된 파일 · 하위 저장소·링크 · `vendor/` `node_modules/` `target/` 등 · 잠금 파일·압축본 · 바이너리 · `--exclude`(쉼표로 여러 개, `*.{py,md}` 처럼 중괄호 가능, `gen/` 은 그 폴더 아래 전부).
이 목록이 체크리스트다. 사람이 고른 것이 아니라 git 이 낸 목록이라서 "중요해 보이는 것만" 보는 일이 생기지 않는다.

### ② 검사 기준 받기

```bash
python3 $R rule [방식 인자]          # 파일을 생략하면 ① 의 리뷰할 파일 전부
```

파일 종류마다 OCR 내장 규칙(`references/rules/*.md`, 영어 원문)이 붙고, 같은 기준을 쓰는 파일끼리 묶여 나온다.
묶음 하나씩 리뷰하면 기준을 한 번만 읽는다. 기준 본문이 길면(묶음마다 수 KB) `--no-text` 로 묶음만 먼저 보고, 본문은 `references/rules/<이름>` 에서 읽는다. 대응표에 없는 확장자(`.svelte`·`.sh` 등)는 `default.md` 로 간다.

프로젝트 고유 기준은 `.claude/review-rules.json` 에 적는다. 처음 맞는 항목이 내장 기준을 **바꾸고**, `merge_system_rule: true` 면 **더한다**:

```json
{"rules": [
  {"path": "src/routes/**/*.svelte", "rule": "load 함수에서 쿠키를 읽으면 서버 전용인지 확인한다", "merge_system_rule": true},
  {"path": "**/*.sql", "rule": "마이그레이션은 되돌리기 쿼리가 짝으로 있어야 한다"}
]}
```

### ③ 파일마다 리뷰

①의 파일을 하나도 빼지 않고 diff 를 읽는다. 높은 심각도 문제를 하나 찾았다고 멈추지 않는다 — 나머지 파일의 문제가 가려진다.

- 작업 중: `git --no-pager diff HEAD -- <파일>` · untracked 는 파일을 그대로 읽는다
- 범위·커밋: `git --no-pager diff <base>..<target> -- <파일>` (base·target 은 `scope --json` 에 있다)

볼 이유가 없는 파일(이름만 바뀜, 생성 코드 등)은 건너뛰되 **이유를 적는다**.

### ④ 장부를 쓰고 검사

```bash
python3 $R check [방식 인자] - <<'JSON'
{"files": [
  {"path": "src/a.py", "status": "reviewed"},
  {"path": "src/b.ts", "status": "skipped", "reason": "이름만 바뀜"}
 ],
 "findings": [
  {"path": "src/a.py", "start_line": 42, "end_line": 44, "severity": "high"}
 ]}
JSON
```

- **실패(종료 1)**: 장부에 없는 파일 · 이유 없는 skipped · 범위 밖 파일 지적 · 파일 길이를 넘는 줄 번호
- **실패**: 형식이 틀린 항목(문자열 아닌 path, 정수 아닌 줄 번호)
- **경고**: 바뀐 줄 밖 지적(주변 코드 문제일 수 있다) · 줄 번호 없는 지적 · 파일 길이를 알 수 없음
- 실패가 나면 빠진 파일을 마저 리뷰하거나 줄 번호를 파일에서 다시 확인하고 다시 돌린다. 통과할 때까지 결과를 보고하지 않는다.

줄 번호는 범위·커밋 방식이면 target 커밋의 파일, 작업 중 방식이면 지금 작업 트리의 파일 기준이다.

### ⑤ 보고

지적은 심각도 순서로, 맨 끝에 `check` 요약 줄을 그대로 붙인다:

```text
요약: total_files=7 · reviewed_files=6 · skipped_files=1 · coverage_rate=0.857
건너뜀: src/gen.ts(생성 코드)
```

`coverage_rate` 는 **실제로 읽은** 파일 비율이다. 건너뛴 파일은 통과에는 막히지 않지만 비율을 깎고 이름이 보고에 남는다 — "안 읽음" 같은 이유로 건너뛰면 그대로 드러난다.

## 하지 않는 것

- `ocr` 설치·호출 — 이 스킬은 그 도구 없이 돈다
- `check` 를 통과하지 않은 장부로 "리뷰 완료" 라고 말하기
- 스크립트 실패(종료 2)를 조용히 넘기기 — 오류 줄을 보이고, 스크립트 없이 리뷰했다고 보고에 적는다
