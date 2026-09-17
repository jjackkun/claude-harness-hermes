#!/usr/bin/env python3
"""작업 이력 `journal_events` 의 스키마와 허용목록 검증기.

이력은 **추가만** 된다(UPDATE·DELETE 는 트리거가 막는다). 기록하는 값은 미리 정한
칸과 값 집합 안에서만 받는다 — 대화 원문이 흘러들어가지 않게 하는 것이 목적이다(J-06).
설계: docs/hermes-universe/design/agent/work-journal.md
계획: docs/exec-plans/active/2026-09-15-universe-id-journal.md 목표 3·4·5
"""

import json
import re

KINDS = (
    "agent.created",   # 입사 — 명부 등록·id 발급·정체성 폴더 뒤 (creation-and-organization.md §2)
    "task.assigned", "task.started", "step", "decision", "task.handoff",
    "task.finished", "correction", "tombstone",
    "handoff.declined", "handoff.question", "handoff.expired", "handoff.external",
)
CLAIMED = ("success", "failure", "partial", "blocked", "abandoned")
VERIFIED = ("pass", "fail", "none")
ACTOR_PREFIXES = ("human:", "agent:", "system:")

# 자유 글 칸 — 한 줄만 받는다. 계획 3에서 원격 사본만 암호화한다.
FREE_TEXT = ("intent", "lesson", "decision")
_FREE_TEXT_MAX = 500

# evidence 안에서 허용하는 칸. 그 밖은 버린다(모르는 칸으로 원문이 새는 경로를 막는다).
EVIDENCE_KEYS = ("exit_code", "commit", "files", "command", "bytes", "template", "usage", "reason")
_EVIDENCE_FILES_MAX = 50

COLUMNS = (
    "event_id", "ts", "kind", "universe_id", "task_id", "parent_task_id", "caused_by",
    "actor", "requested_by", "session_id", "claimed", "verified", "accepted",
    "evidence", "intent", "lesson", "decision",
)

# kind 의 CHECK 는 KINDS 에서 만든다 — 같은 목록이 튜플·SQL 두 곳에 있으면 갈라진다
# (2026-09-17: 설계가 요구한 agent.created 가 둘 다에 없었다). 기존 DB 의 옛 CHECK 는
# ensure_schema 가 hermes_journal_migrate 로 옮긴다.
_KIND_CHECK = ",".join("'%s'" % k for k in KINDS)

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS journal_events (
  event_id        TEXT PRIMARY KEY,
  ts              TEXT NOT NULL,
  kind            TEXT NOT NULL CHECK (kind IN (%s)),
  universe_id     TEXT NOT NULL,
  task_id         TEXT NOT NULL,
  parent_task_id  TEXT,
  caused_by       TEXT,
  actor           TEXT NOT NULL,
  requested_by    TEXT,
  session_id      TEXT,
  claimed         TEXT CHECK (claimed IN ('success','failure','partial','blocked','abandoned') OR claimed IS NULL),
  verified        TEXT CHECK (verified IN ('pass','fail','none') OR verified IS NULL),
  accepted        TEXT,
  evidence        TEXT,
  intent          TEXT,
  lesson          TEXT,
  decision        TEXT
);
CREATE INDEX IF NOT EXISTS journal_task_idx ON journal_events(task_id, ts);
CREATE INDEX IF NOT EXISTS journal_universe_idx ON journal_events(universe_id, ts);
CREATE TRIGGER IF NOT EXISTS journal_no_update BEFORE UPDATE ON journal_events
  BEGIN SELECT RAISE(ABORT,'journal_events is append-only'); END;
CREATE TRIGGER IF NOT EXISTS journal_no_delete BEFORE DELETE ON journal_events
  BEGIN SELECT RAISE(ABORT,'journal_events is append-only'); END;
""" % _KIND_CHECK


class JournalRejected(ValueError):
    """허용목록 밖의 값 — 기록하지 않는다."""


def ensure_schema(con) -> None:
    """테이블·인덱스·트리거를 만든다. 이미 있으면 아무것도 하지 않는다(기존 DB 무손실).

    옛 CHECK(KINDS 보다 좁은 목록)를 가진 표는 먼저 새 표로 옮긴다 — 한 트랜잭션,
    실패하면 원상(hermes_journal_migrate)."""
    from hermes_journal_migrate import migrate_kind_check
    migrate_kind_check(con, SCHEMA_SQL, KINDS)
    con.executescript(SCHEMA_SQL)
    con.commit()


def schema_disabled(con) -> bool:
    """rollback 으로 테이블 이름이 바뀌어 기록을 받지 않는 상태인가(목표 12).

    "테이블이 없다" 만으로 판정하면 **처음 쓰는 DB** 도 꺼진 것으로 보게 된다.
    꺼진 상태는 `journal_events` 가 없으면서 이름이 바뀐 사본이 있을 때다.
    """
    names = {r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'journal_events%'"
    )}
    return "journal_events" not in names and any(
        n.startswith("journal_events_disabled_") for n in names
    )


def _clean_command(value) -> str:
    """명령은 **이름만** 남긴다. 인자에 토큰·비밀번호가 섞여 들어오기 때문이다."""
    head = str(value).strip().split()
    if not head:
        raise JournalRejected("evidence.command 가 비었다")
    return head[0].rsplit("/", 1)[-1]


def clean_evidence(evidence) -> str:
    """허용한 칸만 남겨 JSON 문자열로 만든다. 모르는 칸은 조용히 버리지 않고 거부한다."""
    if evidence in (None, ""):
        return None
    if isinstance(evidence, str):
        try:
            evidence = json.loads(evidence)
        except json.JSONDecodeError as exc:
            raise JournalRejected(f"evidence 가 JSON 이 아니다: {exc}") from exc
    if not isinstance(evidence, dict):
        raise JournalRejected("evidence 는 객체여야 한다")
    unknown = sorted(set(evidence) - set(EVIDENCE_KEYS))
    if unknown:
        raise JournalRejected(f"evidence 에 모르는 칸: {', '.join(unknown)}")
    out = dict(evidence)
    if "command" in out:
        out["command"] = _clean_command(out["command"])
    if "files" in out:
        files = out["files"]
        if not isinstance(files, list):
            raise JournalRejected("evidence.files 는 배열이어야 한다")
        out["files"] = [str(f) for f in files[:_EVIDENCE_FILES_MAX]]
    return json.dumps(out, ensure_ascii=False, sort_keys=True)


def _check_free_text(field: str, value) -> str:
    if value is None:
        return None
    text = str(value)
    if "\n" in text or "\r" in text:
        raise JournalRejected(f"{field} 는 한 줄이어야 한다(원문 붙여넣기 방지)")
    if len(text) > _FREE_TEXT_MAX:
        raise JournalRejected(f"{field} 가 {_FREE_TEXT_MAX}자를 넘는다")
    return text


_REQUIRED = ("event_id", "ts", "universe_id", "task_id", "actor")


def _check_required(row: dict) -> None:
    if row["kind"] not in KINDS:
        raise JournalRejected(f"모르는 kind: {row['kind']}")
    for field in _REQUIRED:
        if not row[field]:
            raise JournalRejected(f"{field} 는 비울 수 없다")


def _check_actors(row: dict) -> None:
    for field in ("actor", "requested_by"):
        value = row[field]
        if value and not value.startswith(ACTOR_PREFIXES):
            raise JournalRejected(f"{field} 는 human:/agent:/system: 로 시작해야 한다: {value}")


def _check_outcomes(row: dict) -> None:
    for field, allowed in (("claimed", CLAIMED), ("verified", VERIFIED)):
        if row[field] and row[field] not in allowed:
            raise JournalRejected(f"모르는 {field}: {row[field]}")


def validate(event: dict) -> dict:
    """허용목록 검사를 통과한 행을 돌려준다. 통과 못 하면 JournalRejected."""
    unknown = sorted(set(event) - set(COLUMNS))
    if unknown:
        raise JournalRejected(f"모르는 칸: {', '.join(unknown)}")
    row = {c: event.get(c) for c in COLUMNS}

    _check_required(row)
    _check_actors(row)
    _check_outcomes(row)
    if row["caused_by"] is not None and not isinstance(row["caused_by"], str):
        row["caused_by"] = json.dumps(list(row["caused_by"]), ensure_ascii=False)

    row["evidence"] = clean_evidence(row["evidence"])
    for field in FREE_TEXT:
        row[field] = _check_free_text(field, row[field])
    return row
