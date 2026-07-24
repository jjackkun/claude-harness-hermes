#!/usr/bin/env python3
"""헤르메스 생애주기 압축 실행부 — `--apply` 의 무손실 가드·원자적 교체 (Part D).

제안 리포트(proposal.json)의 클러스터를 읽어, 대상 세션의 history 파일과
DB `session_history` 를 **같은 요약본으로 동시 교체**한다.

★DB 동시교체가 필수인 이유(D5): 배포단계 전량 backfill export
(`hermes-export-history.py --all`)는 DB→파일 전량 재작성이라
DB 가 원문이면 요약본 파일을 원문으로 되돌린다. 또 `hermes-reindex.py` 의
행수 감소 가드는 "DB N행 > 파일 1행" 이면 교체를 거부한다. 파일 1행 ⟺ DB 1행
이어야 압축·export·reindex 3자가 정합한다.

★무손실 가드(둘 다 통과해야 교체):
  1. HEAD blob 실재 — `git cat-file -e HEAD:<파일>`.
     "추적 + clean" 만으론 부족하다. 커밋 0회(초기 `git add` 만) 파일은
     clean 이어도 HEAD 에 원문이 없어 되돌릴 곳이 사라진다.
  2. working-tree clean — `git status --porcelain -- <파일>` 이 비어 있을 것.
  3. DB 행수 ≤ 파일 행수 — DB 에만 있는 행은 git 에 원문이 없어 교체 시 영구 소실된다.
     (Stop 훅 export 는 실패를 삼키고 현재 세션만 재-export 하므로 과거 세션 파일이
      영구히 DB 보다 뒤처질 수 있다. `hermes-reindex.py` 의 행수감소 가드와 대칭.)
  하나라도 실패하면 그 세션은 스킵 + 경고. 원문은 건드리지 않는다.

★복구 경로: `--apply` 후 DB 에는 원문이 남지 않는다(git 은 파일만 보존).
  복구는 "git 히스토리의 압축 전 파일 → `hermes-reindex.py --force` 재색인" 뿐이다.

★알려진 한계 — 압축은 기계-로컬이다:
  (a) 전파 없음. 압축본을 push 해도 다른 기계는 pull 후에도 DB 에 원문을 유지한다.
      그 기계의 `hermes-reindex.py` 는 행수감소 가드에 걸려 --force 없이는 거부하고,
      SessionStart 재색인 훅도 자동 복구를 하지 않는다(`skip:diverged` 로그만).
      수용하려면 각 기계에서 수동으로 `hermes-reindex.py --force`(파일→DB).
      ★`--force` 는 세션 단위가 아니라 **전역**이다. 그 기계에 export 가 밀려
      파일이 DB 보다 뒤처진 다른 세션이 있으면 그 원문까지 함께 덮어쓴다.
      먼저 `hermes-export-history.py --session <sid>` 로 뒤처진 세션을 맞춘 뒤
      실행할 것(SessionStart 재색인 훅이 `skip:diverged:*` 로 사유를 구분해 준다).
  (b) 역방향 위험. 그 발산 상태의 기계에서 전량 export(DB→파일)를 1회 돌리면
      로컬 DB 원문이 요약본 파일을 덮어써 fleet 전체의 압축이 되돌아간다.
      그래서 `hermes-export-history.py` 는 전량 모드에 `--all` 명시 동의를 요구하고,
      압축본(1행) 위에 DB 원문(N행)을 쓰려는 세션은 스킵한다.
"""

import json
import os
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime

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
DIVERGE_REASON = "파일 교체 실패 — DB만 교체됨(발산)"
RECOVERY_HINT = (
    "되돌리려면: git checkout <압축전커밋> -- <history파일> && "
    "python3 scripts/hermes-reindex.py --db <state.db> --project <프로젝트> --force"
)


class DivergedError(RuntimeError):
    """DB 는 요약본으로 교체됐으나 파일 교체가 실패한 상태(파일·DB 발산).

    단순 스킵과 달리 **이미 파괴적 변경이 일어난 뒤**라 별도 집계·감사가 필요하다.
    """


def _log(msg):
    print("[hermes-lifecycle] %s" % msg, file=sys.stderr)


def ensure_compaction_log(con: sqlite3.Connection) -> None:
    con.execute(COMPACTION_LOG_DDL)


def log_compaction(con: sqlite3.Connection, topic: str, sids: list,
                   before: int, after: int, report_path: str, reason: str) -> None:
    """compaction_log 감사 1행. 성공 압축과 발산 모두 같은 경로로 남긴다."""
    con.execute(
        "INSERT INTO compaction_log "
        "(cluster_topic, session_ids, lines_before, lines_after, report_path, reason) "
        "VALUES (?,?,?,?,?,?)",
        (topic, ",".join(sids), before, after, report_path, reason),
    )
    con.commit()


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


def db_row_count(con, sid: str) -> int:
    """이 세션의 DB 행수. 테이블 부재는 0(교체할 원문이 DB 에 없음)."""
    try:
        return con.execute(
            "SELECT COUNT(*) FROM session_history WHERE session_id=?", (sid,)
        ).fetchone()[0]
    except sqlite3.OperationalError:
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
            # 복구 방향에 주의: 살아남은 원문은 **파일** 쪽이다. export(DB→파일)로
            # 맞추면 유일하게 온전한 원문을 요약본으로 덮어쓴다. 파일→DB 인
            # reindex 로 DB 를 파일에 맞춰야 하며, 파일 N행 > DB 1행이라
            # 행수감소 가드에 걸리지 않아 --force 없이 복구된다.
            raise DivergedError(
                "DB 는 요약본으로 교체됐으나 파일 교체 실패(%s) — "
                "hermes-reindex.py --db <state.db> --project <프로젝트> 로 "
                "DB 를 파일에 맞추세요(원문 파일이 정본)" % e)
    finally:
        if tmp and os.path.exists(tmp):
            os.remove(tmp)


# ───────────────────────── 클러스터 적용 ─────────────────────────

def _apply_session(con, root: str, sid: str, path: str, cluster: dict,
                   result: dict, report_path: str):
    """한 세션 적용. 가드 통과 시 (원문 라인수), 스킵·발산이면 None."""
    skipped = result["skipped"]
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
    db_rows = db_row_count(con, sid)
    if db_rows > before:
        # 파일이 DB 보다 뒤처진 상태. 교체하면 DB 에만 있던 (db_rows - before)개
        # 메시지가 git 어디에도 없이 영구 소실된다 — reindex 행수감소 가드의 대칭.
        skipped.append(sid)
        _log("%s: DB 행수(%d) > 파일 행수(%d) — 먼저 "
             "hermes-export-history.py --session %s 로 파일을 동기화한 뒤 "
             "커밋하세요" % (sid, db_rows, before, sid))
        return None

    project_id, timestamp = _session_meta(con, sid, path)
    record = summary_record(sid, project_id, timestamp,
                            cluster.get("topic") or "(무제)",
                            cluster.get("summary") or "", before)
    try:
        replace_session(con, path, record)
    except DivergedError as e:
        # 스킵이 아니다 — DB 원문은 이미 삭제됐다. 별도 집계 + 감사 필수.
        result["diverged"].append(sid)
        log_compaction(con, cluster.get("topic") or "(무제)", [sid],
                       before, 1, report_path, DIVERGE_REASON)
        _log("%s: ★발산(파일 원문 / DB 요약본) — %s" % (sid, e))
        return None
    except Exception as e:
        skipped.append(sid)
        _log("%s: 교체 실패 — %s" % (sid, e))
        return None
    return before


def apply_proposal(con: sqlite3.Connection, project: str, paths: dict,
                   proposal: dict, report_path: str, gate_check=None) -> dict:
    """제안 클러스터를 적용한다. git 커밋은 하지 않는다(사용자 몫).

    gate_check: sid → 탈락 사유(str) 또는 None. 리포트는 propose 시점 상태라
    낡을 수 있으므로(propose 는 주기 자동, apply 는 수동) 적용 직전에 재평가한다.

    반환: {"applied": [...], "skipped": [...], "diverged": [...],
           "clusters": n, "lines_saved": n}
    """
    result = {"applied": [], "skipped": [], "diverged": [],
              "clusters": 0, "lines_saved": 0}
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
            reason = gate_check(sid) if gate_check else None
            if reason:
                result["skipped"].append(sid)
                _log("%s: 제안 이후 게이트 탈락(%s) — 스킵" % (sid, reason))
                continue
            before = _apply_session(con, root, sid, paths.get(sid), cluster,
                                    result, report_path)
            if before is None:
                continue
            applied.append(sid)
            before_total += before
        if not applied:
            continue
        log_compaction(con, cluster.get("topic") or "(무제)", applied,
                       before_total, len(applied), report_path, COMPACT_REASON)
        result["applied"].extend(applied)
        result["clusters"] += 1
        result["lines_saved"] += max(before_total - len(applied), 0)
    return result


# ───────────────────────── 적용 오케스트레이션 ─────────────────────────

def _append_apply_note(md_path: str, result: dict) -> None:
    """리포트 말미에 적용 결과와 복구 경로를 남긴다(커밋은 사용자 몫)."""
    if not md_path or not os.path.isfile(md_path):
        return
    diverged = result.get("diverged") or []
    with open(md_path, "a", encoding="utf-8") as f:
        f.write("\n## 적용 결과 (--apply)\n\n"
                "- 압축: %d세션 / 클러스터 %d개 (절약 %d줄)\n"
                "- 스킵(무변경): %s\n"
                "- ★발산(DB만 교체됨 — 파일이 정본, reindex 로 복구 필요): %s\n"
                "- git 커밋은 하지 않았다. `git diff` 로 요약본을 확인한 뒤 직접 커밋하라.\n"
                "- %s\n"
                % (len(result["applied"]), result["clusters"], result["lines_saved"],
                   ", ".join(result["skipped"]) or "(없음)",
                   ", ".join(diverged) or "(없음)", RECOVERY_HINT))


def _mark_proposal_applied(json_file: str, data: dict, result: dict) -> None:
    """소비된 제안에 applied_at 을 남겨 재적용을 막는다(낡은 리포트 재사용 방지)."""
    if not json_file:
        return
    payload = dict(data)                  # 원본 불변 — 새 dict 로 기록
    payload["applied_at"] = datetime.now().isoformat(timespec="seconds")
    payload["applied_result"] = {k: result.get(k) or []
                                 for k in ("applied", "skipped", "diverged")}
    try:
        with open(json_file, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
    except OSError as e:
        _log("제안 소비 표시 실패: %s (%s)" % (json_file, e))


def run_apply(con: sqlite3.Connection, project: str, paths: dict,
              json_file: str, data: dict, gate_check=None):
    """읽어 둔 제안을 적용하고, 소비 표시·리포트 追記·요약 로그까지 끝낸다.

    호출부(hermes-lifecycle.py)는 리포트 탐색과 게이트 재평가기 주입만 담당한다.
    """
    if data.get("applied_at"):
        _log("이미 적용된 제안이다(applied_at=%s) — 재적용 거부. "
             "다시 압축하려면 --propose 로 새 리포트를 만들라" % data["applied_at"])
        return None
    report_path = data.get("report") or json_file
    result = apply_proposal(con, project, paths, data, report_path,
                            gate_check=gate_check)
    if result["applied"] or result["diverged"]:
        # 파괴적 변경이 실제로 일어난 리포트만 소비 처리한다. 전부 스킵이면
        # 아무것도 안 바뀐 것이니 원인(커밋 등)을 고친 뒤 재시도할 수 있어야 한다.
        _mark_proposal_applied(json_file, data, result)
    _append_apply_note(data.get("report") or "", result)
    _log("압축 %d세션 / 스킵 %d세션 / 발산 %d세션 — "
         "git 커밋은 하지 않았다(검토 후 직접 커밋). %s"
         % (len(result["applied"]), len(result["skipped"]),
            len(result["diverged"]), RECOVERY_HINT))
    return result
