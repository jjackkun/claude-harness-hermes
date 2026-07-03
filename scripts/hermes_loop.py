#!/usr/bin/env python3
"""헤르메스 목표 기반 자율 루프 — 공용 코어 모듈.

loops/loop_steps 스키마, GOAL.md 읽기/쓰기, 안전캡 판정, 반복 기록,
완료 아카이브, 검증 명령 실행을 담당한다.
CLI(hermes-loop.py)와 대화형 스킬(/hermes-loop)이 이 모듈을 공유한다.
설계: docs/superpowers/specs/2026-07-02-hermes-loop-design.md
"""

import os
import re
import sqlite3
import subprocess
import sys
import uuid
from datetime import datetime

from hermes_redact import redact

# ── 기본값 (설계 §6.1 — 근거 명시) ──────────────────────────────────────────
RETRIES_PER_CONDITION = 3    # 완료조건 1개당 재시도 여유 — HTTP 재시도 업계 관례 3회
MIN_MAX_ITERATIONS = 5       # 조건 0~1개 단순 목표의 최소 시도 횟수
NO_PROGRESS_LIMIT = 3        # 결정화 임계(동일 패턴 3회)와 동일 근거
RECENT_LOG_COUNT = 5         # 롤링 요약 5슬롯과 동일 — 직전 시도 맥락 유지
GIT_CMD_TIMEOUT = 10         # 로컬 git 조회 상한(초) — 원격 접근 없는 로컬 명령
# 검증 명령 상한(초): 통합 테스트 스위트도 수 분 단위 — 행(hang) 명령이
# 루프 전체를 무한 블록하지 않게 하는 안전 상한. 환경변수로 조정 가능.
VERIFY_TIMEOUT = int(os.environ.get("HERMES_LOOP_VERIFY_TIMEOUT", "600"))

VERDICTS = ("continue", "goal-met", "blocked")
SIGNALS = ("pass", "fail", "none")

# 파괴적 verify 명령 차단 — "탐지는 정규식(결정적 코드)" 원칙 (G9)
_DENY_VERIFY_RE = re.compile(
    r"rm\s+-[a-z]*f|git\s+push\s+--force|--force-with-lease|"
    r"git\s+reset\s+--hard|git\s+clean|drop\s+(table|database)|mkfs|>\s*/dev/sd|"
    r"\|\s*(ba|z|k)?sh\b|find\b.*-delete|find\b.*-exec\s+rm|"
    r"dd\s|truncate\b|chmod\s+-R|chown\s+-R|git\s+push|sudo\b|:\s*>\s*\S",
    re.I)

# hermes-init.py 가 import 하여 동일 DDL 로 마이그레이션한다 (G13)
LOOP_SCHEMA_STATEMENTS = (
    """
    CREATE TABLE IF NOT EXISTS loops (
      id                TEXT PRIMARY KEY,
      title             TEXT NOT NULL,
      goal_md_path      TEXT NOT NULL,
      mode              TEXT NOT NULL DEFAULT 'goal',
      branch            TEXT,
      status            TEXT NOT NULL DEFAULT 'running',
      max_iterations    INTEGER NOT NULL,
      no_progress_limit INTEGER NOT NULL DEFAULT 3,
      iterations_used   INTEGER NOT NULL DEFAULT 0,
      no_progress_count INTEGER NOT NULL DEFAULT 0,
      created_at        TEXT NOT NULL,
      updated_at        TEXT NOT NULL,
      finished_at       TEXT,
      finish_reason     TEXT
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS loop_steps (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      loop_id          TEXT NOT NULL,
      iteration        INTEGER NOT NULL,
      action_summary   TEXT,
      verdict          TEXT,
      objective_signal TEXT,
      progressed       INTEGER NOT NULL DEFAULT 0,
      created_at       TEXT NOT NULL
    )
    """,
)


def connect_db(db_path):
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def ensure_schema(db_path):
    con = connect_db(db_path)
    for ddl in LOOP_SCHEMA_STATEMENTS:
        con.execute(ddl)
    con.commit()
    con.close()


def default_max_iterations(condition_count):
    """완료조건 수 × 재시도 여유(3), 최소 5회 (설계 §6.1)."""
    return max(condition_count * RETRIES_PER_CONDITION, MIN_MAX_ITERATIONS)


def _now():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


# ── GOAL.md I/O ──────────────────────────────────────────────────────────────

GOAL_MD_TEMPLATE = """\
# Loop: {title}
> loop-id: {loop_id} · created: {created} · mode: goal · status: running

## 목표
{goal}

## 완료 조건 (Definition of Done)
{conditions_block}

## 객관 검증 (선택)
{verify_line}

## 진행 로그
"""

_COND_RE = re.compile(r"^- \[([ x])\] (.+)$")
_VERIFY_RE = re.compile(r"^- verify: `(.+)`\s*$")
_LOG_RE = re.compile(r"^- \[iter (\d+)\]")


def goal_md_path(project_dir, loop_id):
    return os.path.join(project_dir, ".hermes", "loops", loop_id, "GOAL.md")


def create_loop(db_path, project_dir, goal, title=None, conditions=None,
                verify_cmd=None, max_iterations=None,
                no_progress_limit=NO_PROGRESS_LIMIT):
    """GOAL.md 생성 + loops 행 INSERT (G1). (loop_id, goal_md_path) 반환."""
    ensure_schema(db_path)
    conditions = conditions or []
    goal = redact(goal)                      # 저장 경계 마스킹 (G12)
    title = (redact(title) if title else goal.strip().splitlines()[0])[:60]
    if max_iterations is None:
        max_iterations = default_max_iterations(len(conditions))
    # 초 단위 타임스탬프 충돌 방지용 uuid 6자리 (16^6 ≈ 1,678만 조합)
    loop_id = "loop-{}-{}".format(
        datetime.now().strftime("%Y%m%d-%H%M%S"), uuid.uuid4().hex[:6])
    path = goal_md_path(project_dir, loop_id)
    os.makedirs(os.path.dirname(path), exist_ok=True)

    cond_block = "\n".join(f"- [ ] {redact(c)}" for c in conditions) \
        or "(첫 반복에서 에이전트가 검증 가능한 체크박스로 작성)"
    # verify 명령은 드라이버가 재실행할 문자열이라 마스킹하지 않는다 —
    # 비밀은 명령에 직접 넣지 말고 환경변수로 전달 (가이드 문서 명시)
    verify_line = f"- verify: `{verify_cmd}`" if verify_cmd else "- verify: none"

    with open(path, "w", encoding="utf-8") as f:
        f.write(GOAL_MD_TEMPLATE.format(
            title=title, loop_id=loop_id, created=_now()[:10],
            goal=goal, conditions_block=cond_block, verify_line=verify_line))

    con = connect_db(db_path)
    con.execute(
        "INSERT INTO loops (id, title, goal_md_path, mode, status,"
        " max_iterations, no_progress_limit, created_at, updated_at)"
        " VALUES (?,?,?,?,?,?,?,?,?)",
        (loop_id, title, path, "goal", "running",
         max_iterations, no_progress_limit, _now(), _now()))
    con.commit()
    con.close()
    return loop_id, path


def read_goal_md(path):
    """GOAL.md 파싱 → {goal, conditions:[(done,text)], verify_cmd, log_lines}."""
    section = None
    goal_lines, conditions, log_lines = [], [], []
    verify_cmd = None
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if line.startswith("## "):
                head = line[3:]
                section = ("goal" if head.startswith("목표") else
                           "cond" if head.startswith("완료 조건") else
                           "verify" if head.startswith("객관 검증") else
                           "log" if head.startswith("진행 로그") else None)
                continue
            if section == "goal":
                goal_lines.append(line)
            elif section == "cond":
                m = _COND_RE.match(line)
                if m:
                    conditions.append((m.group(1) == "x", m.group(2)))
            elif section == "verify":
                m = _VERIFY_RE.match(line)
                if m and m.group(1) != "none":
                    verify_cmd = m.group(1)
            elif section == "log" and _LOG_RE.match(line):
                log_lines.append(line)
    return {"goal": "\n".join(goal_lines).strip(), "conditions": conditions,
            "verify_cmd": verify_cmd, "log_lines": log_lines}


def checked_count(conditions):
    return sum(1 for done, _ in conditions if done)


def append_progress_log(path, iteration, action, signal, verdict):
    """진행 로그 1줄 append — 마스킹 경유 (G12)."""
    safe = redact(action or "").replace("\n", " ").strip()[:200]
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"- [iter {iteration}] {safe} · signal:{signal} · verdict:{verdict}\n")


def update_goal_status(path, status):
    """GOAL.md 헤더의 status 필드 갱신 (best-effort)."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
        for i, line in enumerate(lines):
            if line.startswith("> loop-id:"):
                lines[i] = re.sub(r"status: \S+", f"status: {status}", line)
                break
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(lines)
    except OSError as e:
        print(f"[hermes-loop] GOAL.md status 갱신 실패: {e}", file=sys.stderr)


# ── 상태 조회·기록 ───────────────────────────────────────────────────────────

def get_loop(db_path, loop_id):
    con = connect_db(db_path)
    con.row_factory = sqlite3.Row
    row = con.execute("SELECT * FROM loops WHERE id=?", (loop_id,)).fetchone()
    con.close()
    return dict(row) if row else None


def list_loops(db_path, limit=20):
    con = connect_db(db_path)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        "SELECT * FROM loops ORDER BY created_at DESC LIMIT ?",
        (limit,)).fetchall()
    con.close()
    return [dict(r) for r in rows]


def last_signal(db_path, loop_id):
    con = connect_db(db_path)
    row = con.execute(
        "SELECT objective_signal FROM loop_steps WHERE loop_id=?"
        " ORDER BY iteration DESC LIMIT 1", (loop_id,)).fetchone()
    con.close()
    return row[0] if row else "none"


def check_caps(loop):
    """안전캡 판정 — 'max-iter' | 'no-progress' | None (G5·G6)."""
    if loop["iterations_used"] >= loop["max_iterations"]:
        return "max-iter"
    if loop["no_progress_count"] >= loop["no_progress_limit"]:
        return "no-progress"
    return None


def record_iteration(db_path, loop_id, iteration, action, verdict, signal,
                     progressed):
    """loop_steps INSERT + loops 카운터 갱신 (한 트랜잭션)."""
    con = connect_db(db_path)
    con.execute(
        "INSERT INTO loop_steps (loop_id, iteration, action_summary, verdict,"
        " objective_signal, progressed, created_at) VALUES (?,?,?,?,?,?,?)",
        (loop_id, iteration, redact(action or ""), verdict, signal,
         1 if progressed else 0, _now()))
    if progressed:
        con.execute(
            "UPDATE loops SET iterations_used=?, no_progress_count=0,"
            " updated_at=? WHERE id=?", (iteration, _now(), loop_id))
    else:
        con.execute(
            "UPDATE loops SET iterations_used=?,"
            " no_progress_count=no_progress_count+1, updated_at=? WHERE id=?",
            (iteration, _now(), loop_id))
    con.commit()
    con.close()


def finish_loop(db_path, loop_id, status, reason):
    """상태 전이 running→done/stopped + GOAL.md status 동기화."""
    con = connect_db(db_path)
    con.execute(
        "UPDATE loops SET status=?, finish_reason=?, finished_at=?,"
        " updated_at=? WHERE id=?", (status, reason, _now(), _now(), loop_id))
    con.commit()
    con.close()
    loop = get_loop(db_path, loop_id)
    if loop:
        update_goal_status(loop["goal_md_path"], status)


def archive_loop(db_path, loop_id):
    """완료 아카이브 — messages(from=loop, to=archive) 1건 (G11)."""
    loop = get_loop(db_path, loop_id)
    if not loop:
        return
    content = ("루프종료 {id} REASON:{reason} ITER:{used}/{cap} TITLE:{title}"
               .format(id=loop_id, reason=loop["finish_reason"],
                       used=loop["iterations_used"],
                       cap=loop["max_iterations"], title=loop["title"]))
    con = connect_db(db_path)
    try:
        con.execute(
            "INSERT INTO messages (from_agent, to_agent, content, status,"
            " created_at) VALUES ('loop','archive',?,'unread',"
            " CURRENT_TIMESTAMP)", (content,))
        con.commit()
    except sqlite3.OperationalError as e:
        print(f"[hermes-loop] 아카이브 실패 (messages 테이블 없음?): {e}",
              file=sys.stderr)
    finally:
        con.close()


# ── 객관 신호 ────────────────────────────────────────────────────────────────

def run_verify(cmd, cwd):
    """VERIFY 명령을 드라이버가 직접 실행 → 'pass' | 'fail' (G3).

    파괴적 패턴은 실행 없이 fail 처리한다 — 탐지는 정규식 (G9).
    """
    if not cmd or _DENY_VERIFY_RE.search(cmd):
        return "fail"
    try:
        proc = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True,
                              text=True, timeout=VERIFY_TIMEOUT)
        return "pass" if proc.returncode == 0 else "fail"
    except (subprocess.TimeoutExpired, OSError):
        return "fail"


def git_head(project_dir):
    """현재 HEAD 커밋 해시 (git 저장소 아니면 None) — 진전 판정용."""
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=project_dir,
            capture_output=True, text=True, timeout=GIT_CMD_TIMEOUT)
        return proc.stdout.strip() if proc.returncode == 0 else None
    except (subprocess.TimeoutExpired, OSError):
        return None


def ensure_loop_branch(db_path, project_dir, loop_id):
    """루프 전용 브랜치 loop/<id> 생성·체크아웃 (G14).

    에이전트 커밋을 이 브랜치에 격리한다 — 머지·push 는 사용자 수동.
    git 저장소가 아니면 경고 후 None (루프는 파일 수정만으로 계속, 설계 G14).
    실제 git 저장소인데 체크아웃에 실패하면 격리를 보장할 수 없으므로
    None 을 반환하지 않고 RuntimeError 를 던진다 — 호출부가 루프를 시작하지
    않도록 강제해 커밋이 격리 없이 main(또는 이전 브랜치)에 쌓이는 사고를 막는다.
    """
    try:
        probe = subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"], cwd=project_dir,
            capture_output=True, text=True, timeout=GIT_CMD_TIMEOUT)
        if probe.returncode != 0:
            print("[hermes-loop] git 저장소 아님 — 루프 브랜치 생략 (G14)",
                  file=sys.stderr)
            return None
        branch = f"loop/{loop_id}"
        exists = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", branch],
            cwd=project_dir, capture_output=True, text=True,
            timeout=GIT_CMD_TIMEOUT).returncode == 0
        args = (["git", "checkout", branch] if exists
                else ["git", "checkout", "-b", branch])
        proc = subprocess.run(args, cwd=project_dir, capture_output=True,
                              text=True, timeout=GIT_CMD_TIMEOUT)
        if proc.returncode != 0:
            raise RuntimeError(
                f"루프 브랜치 격리 실패: {branch} 체크아웃 실패 —"
                f" {proc.stderr.strip()}")
    except (subprocess.TimeoutExpired, OSError) as e:
        raise RuntimeError(f"루프 브랜치 준비 실패: {e}") from e
    con = connect_db(db_path)
    con.execute("UPDATE loops SET branch=?, updated_at=? WHERE id=?",
                (branch, _now(), loop_id))
    con.commit()
    con.close()
    return branch
