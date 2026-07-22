#!/usr/bin/env python3
"""헤르메스 생애주기 압축 실행부 — `--apply` 의 무손실 가드·원자적 교체 (Part D).

제안 리포트(proposal.json)의 클러스터를 읽어, 대상 세션의 history 파일과
DB `session_history` 를 **같은 요약본으로 동시 교체**한다.

★DB 동시교체가 필수인 이유(D5): 배포단계 전량 backfill export
(`hermes-export-history.py` --session 미지정)는 DB→파일 전량 재작성이라
DB 가 원문이면 요약본 파일을 원문으로 되돌린다. 또 `hermes-reindex.py` 의
행수 감소 가드는 "DB N행 > 파일 1행" 이면 교체를 거부한다. 파일 1행 ⟺ DB 1행
이어야 압축·export·reindex 3자가 정합한다.

★무손실 가드(둘 다 통과해야 교체):
  1. HEAD blob 실재 — `git cat-file -e HEAD:<파일>`.
     "추적 + clean" 만으론 부족하다. 커밋 0회(초기 `git add` 만) 파일은
     clean 이어도 HEAD 에 원문이 없어 되돌릴 곳이 사라진다.
  2. working-tree clean — `git status --porcelain -- <파일>` 이 비어 있을 것.
  하나라도 실패하면 그 세션은 스킵 + 경고. 원문은 건드리지 않는다.

★복구 경로: `--apply` 후 DB 에는 원문이 남지 않는다(git 은 파일만 보존).
  복구는 "git 히스토리의 압축 전 파일 → `hermes-reindex.py --force` 재색인" 뿐이다.
"""

import json
import os
import sqlite3
import subprocess
import sys
import tempfile

# compaction_log 자가수리 DDL — 정본은 hermes-init.py. init.py 만 고치면
# 기존 DB 가 안 따라오므로 소비처에서도 CREATE IF NOT EXISTS 한다(Part B 교훈).
COMPACTION_LOG_DDL = """
    CREATE TABLE IF NOT EXISTS compaction_log (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        run_at        DATETIME DEFAULT CURRENT_TIMESTAMP,
        cluster_topic TEXT,
        session_ids   TEXT,
        lines_before  INTEGER,
        lines_after   INTEGER,
        report_path   TEXT,
        reason        TEXT
    )
"""

COMPACT_REASON = "생애주기 3중 게이트 통과(오래됨·미사용·결정화) — 주제 클러스터 요약 압축"
RECOVERY_HINT = (
    "되돌리려면: git checkout <압축전커밋> -- <history파일> && "
    "python3 scripts/hermes-reindex.py --db <state.db> --project <프로젝트> --force"
)


def _log(msg):
    print("[hermes-lifecycle] %s" % msg, file=sys.stderr)


def ensure_compaction_log(con: sqlite3.Connection) -> None:
    con.execute(COMPACTION_LOG_DDL)


# ───────────────────────── git 무손실 가드 ─────────────────────────

def _git(root, *args):
    return subprocess.run(["git", "-C", root, *args],
                          capture_output=True, text=True)


def git_root(project: str):
    """프로젝트가 속한 git 저장소 루트. git 저장소가 아니면 None."""
    try:
        r = _git(project, "rev-parse", "--show-toplevel")
    except OSError:                       # git 미설치
        return None
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def head_blob_exists(root: str, rel: str) -> bool:
    """HEAD 에 그 경로의 blob 이 실재하는가(= 원문이 커밋돼 있는가)."""
    return _git(root, "cat-file", "-e", "HEAD:%s" % rel).returncode == 0


def worktree_clean(root: str, rel: str) -> bool:
    """그 파일에 미커밋 변경(스테이지·워킹트리·미추적)이 없는가."""
    r = _git(root, "status", "--porcelain", "--", rel)
    return r.returncode == 0 and not r.stdout.strip()


def local_only_commits(root: str) -> int:
    """원격에 없는 로컬 전용 커밋 수. 원문이 여기에만 있으면 rebase/reset 으로 소실 가능."""
    r = _git(root, "rev-list", "--count", "HEAD", "--not", "--remotes")
    try:
        return int(r.stdout.strip()) if r.returncode == 0 else 0
    except ValueError:
        return 0


# ───────────────────────── 요약본 생성·교체 ─────────────────────────

def count_lines(path: str) -> int:
    try:
        with open(path, encoding="utf-8") as f:
            return sum(1 for line in f if line.strip())
    except OSError:
        return 0


def _session_meta(con, sid: str, path: str):
    """(project_id, timestamp). timestamp 는 파일명 날짜 접두를 유지시키는 값이라
    반드시 원문 것을 물려받아야 한다 — 전량 export 가 파일명을 바꾸지 않도록."""
    try:
        row = con.execute(
            "SELECT project_id, timestamp FROM session_history WHERE session_id=? LIMIT 1",
            (sid,),
        ).fetchone()
    except sqlite3.OperationalError:
        row = None
    if row and (row[0] or row[1]):
        return row[0] or "", row[1] or ""
    try:                                   # DB 에 없으면 파일 첫 줄에서
        with open(path, encoding="utf-8") as f:
            obj = json.loads(f.readline() or "{}")
        return obj.get("project_id") or "", obj.get("timestamp") or ""
    except (OSError, json.JSONDecodeError, AttributeError):
        return "", ""


def summary_record(sid: str, project_id: str, timestamp: str,
                   topic: str, summary: str, orig_lines: int) -> dict:
    """요약본 JSONL 1줄. reindex 파싱(session_id/seq/content)·export 재작성과 정합."""
    content = "[압축 요약] %s\n%s\n(원문 %d줄 — %s)" % (
        topic, summary or "(요약 없음)", orig_lines, RECOVERY_HINT)
    return {
        "seq": 0,
        "session_id": sid,
        "project_id": project_id,
        "role": "system",
        "timestamp": timestamp,
        "content": content,
        "compacted": True,
        "orig_lines": orig_lines,
    }


def replace_session(con: sqlite3.Connection, path: str, record: dict) -> None:
    """파일·DB 원자적 동시 교체.

    순서: tmp 파일 선작성 → DB 트랜잭션 커밋 → 파일 원자적 os.replace.
    DB 실패 시 파일은 미교체(tmp 폐기), 파일 교체 실패 시 발산을 명시적으로 알린다.
    """
    line = json.dumps(record, ensure_ascii=False) + "\n"
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".",
                               prefix=".compact-", suffix=".jsonl")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(line)
            f.flush()
            os.fsync(f.fileno())

        cur = con.cursor()
        cur.execute("BEGIN IMMEDIATE")
        try:
            cur.execute("DELETE FROM session_history WHERE session_id = ?",
                        (record["session_id"],))
            cur.execute(
                "INSERT INTO session_history "
                "(content, role, timestamp, project_id, session_id) VALUES (?,?,?,?,?)",
                (record["content"], record["role"], record["timestamp"],
                 record["project_id"], record["session_id"]),
            )
            cur.execute("COMMIT")
        except Exception:
            try:
                cur.execute("ROLLBACK")
            except sqlite3.OperationalError:
                pass
            raise

        try:
            os.replace(tmp, path)          # DB 커밋 성공 후에만 파일 교체
            tmp = None
        except OSError as e:
            raise RuntimeError(
                "DB 는 요약본으로 교체됐으나 파일 교체 실패(%s) — "
                "hermes-export-history.py 로 파일을 DB 에 맞추세요" % e)
    finally:
        if tmp and os.path.exists(tmp):
            os.remove(tmp)


# ───────────────────────── 클러스터 적용 ─────────────────────────

def _apply_session(con, root: str, sid: str, path: str, cluster: dict, skipped: list):
    """한 세션 적용. 가드 통과 시 (원문 라인수), 스킵이면 None."""
    if not path or not os.path.isfile(path):
        skipped.append(sid)
        _log("%s: history 파일 없음 — 스킵" % sid)
        return None
    rel = os.path.relpath(path, root).replace(os.sep, "/")
    if not head_blob_exists(root, rel):
        skipped.append(sid)
        _log("%s: HEAD 에 원문 blob 없음(커밋 0회) — 스킵. "
             "먼저 .hermes/history 를 커밋하세요" % sid)
        return None
    if not worktree_clean(root, rel):
        skipped.append(sid)
        _log("%s: 워킹트리에 미커밋 변경 있음 — 스킵. 먼저 커밋하세요" % sid)
        return None

    before = count_lines(path)
    project_id, timestamp = _session_meta(con, sid, path)
    record = summary_record(sid, project_id, timestamp,
                            cluster.get("topic") or "(무제)",
                            cluster.get("summary") or "", before)
    try:
        replace_session(con, path, record)
    except Exception as e:
        skipped.append(sid)
        _log("%s: 교체 실패 — %s" % (sid, e))
        return None
    return before


def apply_proposal(con: sqlite3.Connection, project: str, paths: dict,
                   proposal: dict, report_path: str) -> dict:
    """제안 클러스터를 적용한다. git 커밋은 하지 않는다(사용자 몫).

    반환: {"applied": [sid...], "skipped": [sid...], "clusters": n, "lines_saved": n}
    """
    result = {"applied": [], "skipped": [], "clusters": 0, "lines_saved": 0}
    root = git_root(project)
    if root is None:
        _log("git 저장소가 아니다 — 원문 보존 불가라 압축하지 않는다")
        return result

    ensure_compaction_log(con)
    local_only = local_only_commits(root)
    if local_only:
        _log("경고: 로컬 전용 커밋 %d개 — 원문이 아직 push 되지 않았다. "
             "rebase/reset 으로 원문이 소실될 수 있으니 먼저 push 를 권한다" % local_only)

    for cluster in (proposal.get("clusters") or []):
        applied, before_total = [], 0
        for sid in (cluster.get("session_ids") or []):
            before = _apply_session(con, root, sid, paths.get(sid), cluster,
                                    result["skipped"])
            if before is None:
                continue
            applied.append(sid)
            before_total += before
        if not applied:
            continue
        con.execute(
            "INSERT INTO compaction_log "
            "(cluster_topic, session_ids, lines_before, lines_after, report_path, reason) "
            "VALUES (?,?,?,?,?,?)",
            (cluster.get("topic") or "(무제)", ",".join(applied), before_total,
             len(applied), report_path, COMPACT_REASON),
        )
        con.commit()
        result["applied"].extend(applied)
        result["clusters"] += 1
        result["lines_saved"] += max(before_total - len(applied), 0)
    return result
