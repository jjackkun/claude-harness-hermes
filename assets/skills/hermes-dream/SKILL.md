---
name: hermes-dream
description: Run Hermes dreaming — consolidate accumulated rolling summaries into crystallized/evolved skills and propose junk-skill deletions. Use when the user types /hermes-dream [apply]. Without 'apply' it crystallizes/evolves automatically and only PROPOSES deletions (dry-run); with 'apply' it also EXECUTES the proposed deletions.
---

# hermes-dream

누적된 롤링 요약을 통합해 스킬을 결정화·진화하고, junk 스킬 삭제를 제안한다.

## 트리거

사용자가 `/hermes-dream` 또는 `/hermes-dream apply` 를 입력할 때.

## 동작 순서

1. `apply` 인자 유무로 dry-run(기본) / 삭제 실행을 가른다.
2. 다음을 실행한다(`$ARGS` 는 사용자가 넘긴 인자):

```bash
DB="$(pwd)/.hermes/state.db"
SCRIPTS="$(dirname "$(dirname "$(pwd)")")/scripts"
[ -f "$SCRIPTS/hermes-dream.py" ] || SCRIPTS="$(pwd)/scripts"
if printf '%s' "$ARGS" | grep -qiw apply; then
  python3 "$SCRIPTS/hermes-dream.py" --db "$DB" --project-dir "$(pwd)" --apply
else
  python3 "$SCRIPTS/hermes-dream.py" --db "$DB" --project-dir "$(pwd)"
fi
```

3. 출력된 결과(결정화/진화 건수, 드림 리포트 경로)를 사용자에게 보여준다.
4. 삭제 제안이 있으면 "`/hermes-dream apply` 로 실행할까요?" 라고 안내한다.
