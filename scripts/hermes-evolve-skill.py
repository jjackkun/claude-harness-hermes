#!/usr/bin/env python3
"""헤르메스 스킬 자가 진화 스크립트.

claude -p 로 개선 내용을 생성하고 Python이 직접 파일을 업데이트한다 — 재귀 루프 방지.
공통(harness) 스킬은 자동 수정 금지 — 사용자 안내만 출력.

반복 진화 방지 (H3): skill_index.last_evolved_at 에 마지막 진화 시각을 기록하고,
쿨다운(기본 24시간) 안에는 같은 스킬을 다시 진화시키지 않는다.
"""

import argparse
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime, timedelta, timezone


EVOLVE_COOLDOWN_HOURS = 24


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _log(msg: str) -> None:
    print(f"[hermes-evolve] {msg}", file=sys.stderr)


def _ensure_last_evolved_column(con: sqlite3.Connection) -> None:
    """구버전 DB 호환 — skill_index 에 last_evolved_at 컬럼이 없으면 추가한다."""
    cols = [r[1] for r in con.execute("PRAGMA table_info(skill_index)")]
    if "last_evolved_at" not in cols:
        con.execute("ALTER TABLE skill_index ADD COLUMN last_evolved_at TEXT")
        con.commit()


EVOLVE_PROMPT_TEMPLATE = """\
다음 헤르메스 스킬 파일을 사용자 피드백에 맞게 수정한 결과물만 출력하세요.
다른 설명, 서두, 코드블록 래퍼 없이 수정된 마크다운 원문만 출력합니다.

스킬 파일 경로: {skill_path}
버전: v{old_version} -> v{new_version}

### 사용자 피드백
{feedback}

### 현재 스킬 내용
{skill_content}

출력 규칙:
- hermes:auto-generated version:{old_version} 을 version:{new_version} 으로 변경
- 피드백 내용을 섹션에 반영
- 섹션 구조(# 제목, ## 문제 상황, ## 규칙, ## 근거)는 유지
- 스킬 본문은 60줄 이내로 유지
- 피드백이 불명확하면 원문 그대로 출력
"""

PR_GUIDE_TEMPLATE = """\
╔══════════════════════════════════════════════════════╗
║  헤르메스: 공통 스킬 변경 감지                         ║
║  스킬: {skill_name:<46} ║
║  피드백이 ai-dev-setting 공통 스킬에 영향을 줍니다.   ║
║  Claude 에게 "이 스킬 PR 만들어줘" 라고 요청하세요.  ║
╚══════════════════════════════════════════════════════╝
"""


def find_skill_by_keyword(db_path: str, keyword: str):
    try:
        con = connect_db(db_path)
        _ensure_last_evolved_column(con)
        row = con.execute(
            "SELECT skill_path, scope, last_evolved_at FROM skill_index "
            "WHERE keywords LIKE ? LIMIT 1",
            (f"%{keyword}%",),
        ).fetchone()
        con.close()
        return row
    except Exception as e:
        _log(f"스킬 조회 실패({keyword}): {e}")
        return None


def is_in_cooldown(last_evolved_at: str) -> bool:
    """쿨다운(24시간) 내 재진화 여부 판단 (H3)."""
    if not last_evolved_at:
        return False
    try:
        last = datetime.fromisoformat(last_evolved_at)
        if last.tzinfo is None:
            last = last.replace(tzinfo=timezone.utc)
        return datetime.now(timezone.utc) - last < timedelta(hours=EVOLVE_COOLDOWN_HOURS)
    except ValueError as e:
        _log(f"last_evolved_at 파싱 실패({last_evolved_at}): {e}")
        return False


def get_skill_version(content: str) -> int:
    m = re.search(r"hermes:auto-generated\s+version:(\d+)", content)
    return int(m.group(1)) if m else 0


def generate_evolved_content(skill_path: str, content: str, feedback: str,
                              old_ver: int, new_ver: int):
    """claude -p 로 진화된 스킬 내용 생성. HERMES_DISABLED=1 필수 — 재귀 루프 방지."""
    if not shutil.which("claude"):
        _log("claude CLI 없음 — 진화 스킵")
        return None

    prompt = EVOLVE_PROMPT_TEMPLATE.format(
        skill_path=skill_path,
        old_version=old_ver,
        new_version=new_ver,
        feedback=feedback,
        skill_content=content[:3000],
    )

    try:
        # 주의: claude CLI 에는 --max-tokens 옵션이 없다 (C1).
        # 출력 길이는 프롬프트 내 "60줄 이내" 지시로 제한한다.
        result = subprocess.run(
            ["claude", "-p", prompt,
             "--model", "claude-haiku-4-5-20251001"],
            capture_output=True,
            text=True,
            timeout=120,
            env={**os.environ, "HERMES_DISABLED": "1"},
        )
        if result.returncode != 0:
            stderr_tail = (result.stderr or "").strip()[-500:]
            _log(f"claude -p 실패: rc={result.returncode} stderr={stderr_tail}")
            return None
        output = result.stdout.strip()
        if not output:
            _log("claude 출력 없음")
            return None
        output = re.sub(r"^```[a-z]*\n", "", output)
        output = re.sub(r"\n```$", "", output)
        return output
    except subprocess.TimeoutExpired:
        _log("timeout")
        return None
    except Exception as e:
        _log(f"error: {e}")
        return None


def record_evolution(db_path: str, skill_path: str, new_ver: int) -> None:
    """진화 성공 시 skill_index 의 version 과 last_evolved_at 을 갱신한다 (H3)."""
    try:
        con = connect_db(db_path)
        _ensure_last_evolved_column(con)
        con.execute(
            "UPDATE skill_index SET version=?, last_evolved_at=? WHERE skill_path=?",
            (new_ver, datetime.now(timezone.utc).isoformat(), skill_path),
        )
        con.commit()
        con.close()
    except Exception as e:
        _log(f"진화 기록 실패({skill_path}): {e}")


def evolve_skill(db_path: str, keyword: str, feedback: str) -> str:
    row = find_skill_by_keyword(db_path, keyword)
    if not row:
        print(f"[hermes] 스킬 없음 — keyword: {keyword}")
        return "NOT_FOUND"

    skill_path, scope, last_evolved_at = row

    if scope == "harness":
        skill_name = os.path.basename(skill_path)
        print(PR_GUIDE_TEMPLATE.format(skill_name=skill_name), file=sys.stderr)
        print(f"[hermes] COMMON_SKILL:{skill_name}")
        return "COMMON"

    if not os.path.isfile(skill_path):
        print(f"[hermes] 스킬 파일 없음: {skill_path}")
        return "NOT_FOUND"

    skill_name = os.path.basename(skill_path)

    # H3 — 쿨다운 내 재진화 방지 (같은 스킬이 5분 내 3회 진화하던 문제)
    if is_in_cooldown(last_evolved_at):
        print(
            f"[hermes] EVOLVE_SKIPPED:{skill_name} "
            f"(쿨다운 {EVOLVE_COOLDOWN_HOURS}h — 마지막 진화: {last_evolved_at})",
            file=sys.stderr,
        )
        return "COOLDOWN"

    with open(skill_path, "r", encoding="utf-8") as f:
        old_content = f.read()

    old_ver = get_skill_version(old_content)
    new_ver = old_ver + 1 if old_ver > 0 else 1

    new_content = generate_evolved_content(skill_path, old_content, feedback, old_ver, new_ver)
    if not new_content:
        # claude 없거나 실패 시 → 버전만 올리는 것은 git 노이즈이므로 스킵
        print(f"[hermes] EVOLVE_SKIPPED:{skill_name} (claude 없음 또는 실패)", file=sys.stderr)
        return "SKIPPED"

    # 실제 내용 변경 여부 확인 (버전 줄 제외)
    _ver_re = re.compile(r"hermes:auto-generated\s+version:\d+")
    if _ver_re.sub("", new_content) == _ver_re.sub("", old_content):
        print(f"[hermes] EVOLVE_SKIPPED:{skill_name} (내용 변경 없음)", file=sys.stderr)
        return "SKIPPED"

    with open(skill_path, "w", encoding="utf-8") as f:
        f.write(new_content.rstrip() + "\n")

    record_evolution(db_path, skill_path, new_ver)

    result_str = f"{skill_name}:v{old_ver}>v{new_ver}"
    print(f"[hermes] EVOLVED:{result_str}")
    return f"EVOLVED:{result_str}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--keyword", required=True)
    parser.add_argument("--feedback", required=True)
    args = parser.parse_args()

    if not os.path.isfile(args.db):
        print(f"[hermes] DB not found: {args.db}", file=sys.stderr)
        sys.exit(1)

    evolve_skill(args.db, args.keyword, args.feedback)


if __name__ == "__main__":
    main()
