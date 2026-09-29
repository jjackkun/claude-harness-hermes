"""올리기 전 판정의 정답지(privacy_gold)와 그 통계만 담당한다.

사람이 "이 통과 문장도 올려도 됩니까"에 답한 결과를 **해시와 판정(ok·leak)만** 쌓는다 — 원문은 저장하지 않는다.
같은 문장은 해시로 한 번만 센다. 통계는 "스테이징된 문장 중 사람이 응답한 표본" 기준이며 모집단 전체의 보증이 아니다.
계획: docs/exec-plans/completed/2026-09-29-privacy-gate-hardening.md 목표 7

공개: TARGET · ensure_table · known · record · count · stats
"""

# 표본 목표. 놓침이 0건일 때 95% 상한이 약 3/n(세 배 법칙)이라 100개면 3% 이하다.
TARGET = 100
_RULE_OF_THREE = 3.0


def ensure_table(con) -> None:
    con.execute("CREATE TABLE IF NOT EXISTS privacy_gold ("
                " hash TEXT PRIMARY KEY, verdict TEXT NOT NULL CHECK (verdict IN ('ok','leak')),"
                " source TEXT, ts TEXT DEFAULT CURRENT_TIMESTAMP)")


def known(con, hash_: str) -> bool:
    ensure_table(con)
    return con.execute("SELECT 1 FROM privacy_gold WHERE hash=?", (hash_,)).fetchone() is not None


def record(con, hash_: str, verdict: str, source: str = "staged") -> None:
    """같은 문장이 이미 있으면 덮지 않는다(한 번만 센다)."""
    ensure_table(con)
    con.execute("INSERT OR IGNORE INTO privacy_gold (hash, verdict, source) VALUES (?,?,?)", (hash_, verdict, source))


def count(con) -> int:
    ensure_table(con)
    return con.execute("SELECT COUNT(*) FROM privacy_gold").fetchone()[0]


def stats(con) -> dict:
    """표본 수 · 놓침 수 · 놓침 0건일 때의 95% 상한(비율, 없으면 None) · 대기 문장의 사람 판정(둠=과탐, 지움=맞게 걸림)."""
    ensure_table(con)
    n = count(con)
    leaks = con.execute("SELECT COUNT(*) FROM privacy_gold WHERE verdict='leak'").fetchone()[0]
    human = dict(con.execute("SELECT status, COUNT(*) FROM privacy_review WHERE status IN ('keep','drop') GROUP BY status"))
    return {"n": n, "leaks": leaks, "upper": (_RULE_OF_THREE / n) if n and not leaks else None,
            "keep": human.get("keep", 0), "drop": human.get("drop", 0)}
