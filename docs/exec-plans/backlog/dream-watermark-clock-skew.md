# dream 워터마크가 시계 역행 시 요약을 영구 누락한다

> 출처: `docs/exec-plans/completed/2026-09-18-dream-test-clock.md` §7

## 문제

`scripts/hermes-dream.py` 는 `session_summary.updated_at > watermark` 로 새 요약을 수집하고, 워터마크를 마지막 요약의
`updated_at` 으로 올린다. 벽시계가 뒤로 가면(WSL2 시계 보정 — 2026-09-09 시험 덤프에서 1.1초 뒤 삽입이 1초 이른 시각으로
기록된 실측) 그 뒤 종료된 세션의 요약이 워터마크보다 이르게 찍혀 **다음 드리밍에서도, 그 다음에서도 수집되지 않는다.**

시험(`hermes-pipeline-test.sh` 20·21)은 2026-09-18 부터 합성 시각을 써서 이 결함을 더는 재현하지 않는다. 운영 결함은 남아 있다.

## 고칠 때 후보

- 수집 조건을 `updated_at >= watermark AND session_id NOT IN (처리된 세션)` 으로 — 처리 이력 테이블 필요.
- 또는 `session_summary` 에 단조 증가 `seq`(AUTOINCREMENT) 를 두고 워터마크를 `seq` 로 — 스키마 변경 + 마이그레이션.

## 실측 (2026-09-18) — 우선순위 낮음

`docs/audits/2026-09-18-dream-watermark-clock-skew.md`: 8개 DB · 요약 330 · dream 실행 95 에서 **누락 후보 0**,
`dream_log.run_at` 역행 0. 규칙대로 우선순위를 낮춘다. 재측정 조건: 어느 소우주에서든 누락 후보 ≥ 1.

주의: `session_summary` 를 rowid 순으로 비교하면 역행이 많이 보이지만(zeroday 70) 그것은 `ON CONFLICT DO UPDATE` 가
rowid 를 유지해 최초 삽입 순서와 마지막 갱신 시각을 비교한 것 — 지표가 아니다.

### 재측정 (2026-09-22) — 여전히 0

누락 후보 **0** (7곳: zeroday-frontend · novel-ab · novel-bc · ai-create · upbit-ai-trading · terminal-shipping · 공장). 우선순위 낮음 유지.
`jjackkun_bot` · `kis-trading` 은 `dream_log` 에 `watermark_at` 칸이 없는 옛 형식이라 측정되지 않았다 — 워터마크 자체가 없으므로 이 결함의 대상이 아니지만, 스키마가 뒤처진 이유(재설치 누락?)는 따로 볼 일이다.

## 재측정 명령

```bash
for p in $(grep -v '^#' .installed-projects | awk '{print $1}'); do db="$p/.hermes/state.db"; [[ -f "$db" ]] || continue
python3 - "$db" "$(basename $p)" <<'PY'
import sqlite3, sys
con = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
tabs = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
if not {"session_summary","dream_log"} <= tabs: print(sys.argv[2], "표 없음"); sys.exit()
wm = con.execute("SELECT MAX(watermark_at) FROM dream_log WHERE watermark_at IS NOT NULL").fetchone()[0]
lost = 0 if not wm else con.execute("SELECT COUNT(*) FROM session_summary WHERE updated_at <= ? AND updated_at > (SELECT MIN(run_at) FROM dream_log WHERE watermark_at = ?)", (wm, wm)).fetchone()[0]
print("%-22s 워터마크 %s 누락후보 %d" % (sys.argv[2], wm, lost))
PY
done
```
