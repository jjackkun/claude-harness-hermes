---
name: hermes-recall
description: Recall past conversation context from Hermes rolling summaries. Use when the user types /hermes-recall [keyword]. Reads the project's .hermes/state.db session_summary table and prints matching 5-slot summaries (decisions/open tasks). Without a keyword, shows the most recent session summary.
---

# hermes-recall

헤르메스 롤링 요약에서 과거 대화 맥락을 회상한다.

## 트리거

사용자가 `/hermes-recall [키워드]` 를 입력할 때.

## 동작 순서

1. 키워드가 있으면 `--query`, 없으면 최근 세션 요약을 출력한다.
2. 다음을 실행한다(`$ARGS` 는 사용자가 넘긴 키워드, 없으면 빈 문자열):

```bash
DB="$(pwd)/.hermes/state.db"
SCRIPTS="$(dirname "$(dirname "$(pwd)")")/scripts"
[ -f "$SCRIPTS/hermes-recall.py" ] || SCRIPTS="$(pwd)/scripts"
if [ -n "$ARGS" ]; then
  python3 "$SCRIPTS/hermes-recall.py" --query "$ARGS" --db "$DB"
else
  python3 "$SCRIPTS/hermes-recall.py" --query "" --db "$DB" 2>/dev/null \
    || echo "[hermes] 요약 없음 또는 DB 미설치"
fi
```

3. 결과를 사용자에게 보여준다.
