---
name: hermes-status
description: Show the overall Hermes engineering status. Use when the user types /hermes-status. Reads the project's .hermes/state.db and prints skill/rule/session counts, pending crystallization patterns, and the latest/most-used crystallized skills, then offers to run crystallization if patterns are pending.
---

# hermes-status

헤르메스 엔지니어링 전체 현황을 출력한다.

## 트리거

사용자가 `/hermes-status` 를 입력할 때.

## 동작 순서

1. 프로젝트 `.hermes/state.db` 를 읽어 현황을 출력한다.
2. 다음 Python 코드를 실행한다:

```python
import sqlite3, os

db = os.path.join(os.getcwd(), ".hermes", "state.db")
if not os.path.isfile(db):
    print("[hermes] DB 없음 — hermes 프리셋이 설치되지 않았습니다.")
else:
    con = sqlite3.connect(db)
    skill_count   = con.execute("SELECT COUNT(*) FROM skill_index").fetchone()[0]
    rule_count    = con.execute("SELECT COUNT(*) FROM harness_rules").fetchone()[0]
    session_count = con.execute("SELECT COUNT(*) FROM session_history").fetchone()[0]
    pending       = con.execute("SELECT COUNT(*) FROM pattern_count WHERE crystallized=0 AND count>=2").fetchone()[0]

    latest = con.execute(
        "SELECT skill_path, created_at FROM skill_index ORDER BY created_at DESC LIMIT 1"
    ).fetchone()
    top = con.execute(
        "SELECT skill_path, used_count FROM skill_index ORDER BY used_count DESC LIMIT 1"
    ).fetchone()
    con.close()

    print("╔══════════════════════════════════════════╗")
    print("║       헤르메스 현황 (Hermes Status)       ║")
    print("╠══════════════════════════════════════════╣")
    print(f"║  스킬: {skill_count:<6} 규칙: {rule_count:<6} 세션: {session_count:<6}   ║")
    print(f"║  결정화 대기 패턴: {pending}개                    ║")
    print("╠══════════════════════════════════════════╣")
    if latest:
        print(f"║  최근 결정화: {os.path.basename(latest[0])} ({latest[1][:10]})")
    if top:
        print(f"║  최다 활용:   {os.path.basename(top[0])} ({top[1]}회)")
    print("╚══════════════════════════════════════════╝")

    # 전역 패턴 현황 (크로스 프로젝트) — 읽기 전용 가시성
    # 크로스 후보(2곳 이상 프로젝트에서 나타난 패턴)가 1개 이상 보이면
    # 크로스 프로젝트 패턴 집계를 구현할 신호다.
    gdb = os.path.expanduser("~/.hermes/global.db")
    if os.path.isfile(gdb):
        gcon = sqlite3.connect(gdb)
        try:
            g_total = gcon.execute("SELECT COUNT(*) FROM harness_rules").fetchone()[0]
            g_proj = gcon.execute(
                "SELECT COUNT(DISTINCT source_session_id) FROM harness_rules"
            ).fetchone()[0]
            g_cross = gcon.execute(
                "SELECT COUNT(*) FROM (SELECT trigger_keywords FROM harness_rules "
                "GROUP BY trigger_keywords HAVING COUNT(DISTINCT source_session_id) >= 2)"
            ).fetchone()[0]
        except sqlite3.OperationalError:
            g_total = g_proj = g_cross = 0
        gcon.close()
        print(f"  전역 패턴: {g_total}개 · 프로젝트 {g_proj}곳 · 크로스 후보 {g_cross}개")
    else:
        print("  전역 패턴: 전역 DB 없음 (~/.hermes/global.db)")
```

3. 결과를 사용자에게 보여준다.
4. 결정화 대기 패턴이 있으면 "결정화를 실행할까요?" 라고 묻는다.
