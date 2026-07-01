#!/usr/bin/env python3
"""헤르메스 결정화 스크립트.

Claude CLI(claude -p)를 텍스트 생성기로만 사용하고,
파일 쓰기·DB 업데이트는 이 스크립트가 직접 처리한다.
→ Claude 세션에서 Write/Bash 도구 권한 불필요.

품질 게이트: 패턴이 재사용 가능한 작업 지식이 아니면 모델이 SKIP 을 출력하고,
해당 패턴은 crystallized=-1(거부)로 마킹돼 재시도하지 않는다 (C3).

사용법:
  python3 hermes-crystallize.py --db PATH --crystallize KEY1,KEY2 --project-dir PATH
"""

import argparse
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_skills import extract_keywords  # noqa: E402  (본문 키워드 추출 공유 헬퍼)


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _log(msg: str) -> None:
    """stderr 진단 로그 — 훅 컨텍스트에서 stdout 오염 금지 (M2)."""
    print(f"[hermes-crystallize] {msg}", file=sys.stderr)


# 카테고리 메타데이터의 단일 정의처 (hermes-build-prompt.py 의 중복 정의는 제거됨)
CATEGORY_METADATA: dict[str, dict] = {
    "worktree-not-synced": {
        "description": "백그라운드 세션 worktree 편집 후 메인 checkout에 미동기화",
        "search_terms": ["워크트리", "worktree", "메인브랜치", "반영", "적용"],
        "known_rule": (
            "백그라운드 세션은 `.claude/worktrees/<name>/` 안에서만 Edit/Write가 허용된다. "
            "커밋 후 반드시 `cp <worktree-path> <main-checkout-path>`로 메인 checkout에 복사해야 "
            "사용자가 dev server / Storybook에서 변경사항을 볼 수 있다."
        ),
    },
    "css-property-missing": {
        "description": "CSS flex 체인 누락 — 부모에 display:flex 없어서 자식 flex:1 미동작",
        "search_terms": ["display", "flex", "css", "스타일", "없어"],
        "known_rule": (
            "자식 요소에 `flex: 1` 또는 `flex-grow`를 쓸 때 "
            "부모 요소에 반드시 `display: flex`와 `flex-direction`이 있어야 한다."
        ),
    },
    "repeated-mistake": {
        "description": "동일 실수 반복 — 사용자가 여러 번 같은 지적을 함",
        "search_terms": ["자꾸", "또", "계속", "몇번째", "반복"],
        "known_rule": (
            "사용자가 '자꾸', '몇번째', '계속' 등의 표현을 쓰면 같은 실수가 반복되고 있다는 신호다. "
            "해당 작업 시작 전에 관련 메모리와 스킬을 먼저 확인한다."
        ),
    },
}

# 검증 게이트 + 길이 제한은 프롬프트 지시로 처리한다
# (claude CLI 에 --max-tokens 옵션이 없으므로 — C1)
QUALITY_GATE = """\
검증 게이트 (가장 먼저 판단):
이 패턴 키가 재사용 가능한 작업 지식(반복 실수, 작업 규칙, 절차)이 아니라
단순 빈출 단어·일반 어휘·무의미한 토큰이면, 다른 출력 없이 첫 줄에 SKIP 만 출력하세요.

스킬 본문은 60줄 이내로 작성하세요.
"""

SKILL_PROMPT = """\
다음 반복 패턴에 대한 헤르메스 스킬 파일 본문만 출력하세요.
다른 설명, 서두, 코드블록 래퍼 없이 마크다운 원문만 출력합니다.

{quality_gate}
패턴 키: {key}
설명: {description}
알려진 규칙: {known_rule}
관련 증거:
{evidence}
오늘 날짜: {date}

출력 형식 (이 형식 그대로):
# {key}
<!-- hermes:auto-generated version:1 created:{date} -->

## 문제 상황
[이 프로젝트에서 실제로 반복된 실수 — 구체적으로, generic 금지]

## 규칙
- [ ] 체크리스트 항목 1
- [ ] 체크리스트 항목 2
...

## 근거
- 감지 횟수: {count}회
- 패턴 키: {key}
"""

# CATEGORY_METADATA에 없는 동적 키 전용 — known_rule 없이 증거에서 규칙을 도출한다
SKILL_PROMPT_FROM_EVIDENCE = """\
다음 반복 패턴에 대한 헤르메스 스킬 파일 본문만 출력하세요.
다른 설명, 서두, 코드블록 래퍼 없이 마크다운 원문만 출력합니다.

{quality_gate}
패턴 키: {key}
설명: {description}
아래 세션 기록을 분석해 실제로 반복된 실수와 규칙을 직접 도출하세요:
{evidence}
오늘 날짜: {date}

출력 형식 (이 형식 그대로):
# {key}
<!-- hermes:auto-generated version:1 created:{date} -->

## 문제 상황
[세션 기록에서 발견된 실제 반복 실수 — 구체적으로, generic 금지]

## 규칙
- [ ] 체크리스트 항목 1
- [ ] 체크리스트 항목 2
...

## 근거
- 감지 횟수: {count}회
- 패턴 키: {key}
"""

# generate_skill_content 가 "이 패턴은 스킬이 아님" 판정 시 반환하는 센티널
SKIP_SENTINEL = "__HERMES_SKIP__"


def _derive_search_terms(key: str) -> list[str]:
    """임의 패턴 키에서 검색 토큰 목록을 도출한다."""
    tokens = re.split(r"[-_\s]+", key)
    terms = [key.replace("-", " "), key]
    terms += [t for t in tokens if len(t) >= 2]
    seen: set[str] = set()
    result = []
    for t in terms:
        if t not in seen:
            seen.add(t)
            result.append(t)
    return result[:5]


def fetch_evidence(db_path: str, search_terms: list[str], limit: int = 5) -> str:
    if not os.path.isfile(db_path):
        return "(DB 없음)"
    try:
        con = connect_db(db_path)
        snippets: list[str] = []
        for term in search_terms[:3]:
            try:
                # FTS5 MATCH 는 하이픈 등을 구문으로 해석하므로 phrase 인용 필수
                rows = con.execute(
                    "SELECT role, content FROM session_history "
                    "WHERE session_history MATCH ? "
                    "ORDER BY timestamp DESC LIMIT ?",
                    ('"' + term.replace('"', '""') + '"', limit),
                ).fetchall()
                for role, content in rows:
                    short = content[:300].replace("\n", " ").strip()
                    entry = f"[{role}] {short}"
                    if entry not in snippets:
                        snippets.append(entry)
                if len(snippets) >= limit:
                    break
            except Exception as e:
                _log(f"증거 검색 실패(term={term}): {e}")
                continue
        con.close()
        return "\n".join(f"- {s}" for s in snippets[:limit]) if snippets else "(기록 없음)"
    except Exception as e:
        _log(f"증거 조회 DB 오류: {e}")
        return "(DB 쿼리 실패)"


def get_pattern_count(db_path: str, key: str) -> int:
    try:
        con = connect_db(db_path)
        row = con.execute(
            "SELECT count FROM pattern_count WHERE pattern_key=?", (key,)
        ).fetchone()
        con.close()
        return row[0] if row else 0
    except Exception as e:
        _log(f"pattern_count 조회 실패({key}): {e}")
        return 0


def generate_skill_content(
    key: str, meta: dict, evidence: str, count: int, *, from_evidence: bool = False
) -> str | None:
    """Claude CLI를 텍스트 생성기로만 사용해 스킬 본문을 생성한다.

    반환값:
      - 스킬 본문 (str)
      - SKIP_SENTINEL: 모델이 패턴을 junk 로 판정 (crystallized=-1 마킹 대상)
      - None: 생성 실패 (다음 기회에 재시도)
    """
    if not shutil.which("claude"):
        _log(f"claude CLI 없음 — {key} 스킵")
        return None

    date_str = datetime.now().strftime("%Y-%m-%d")
    if from_evidence:
        prompt = SKILL_PROMPT_FROM_EVIDENCE.format(
            quality_gate=QUALITY_GATE,
            key=key,
            description=meta["description"],
            evidence=evidence,
            date=date_str,
            count=count,
        )
    else:
        prompt = SKILL_PROMPT.format(
            quality_gate=QUALITY_GATE,
            key=key,
            description=meta["description"],
            known_rule=meta["known_rule"],
            evidence=evidence,
            date=date_str,
            count=count,
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
            _log(f"claude -p 실패({key}): rc={result.returncode} stderr={stderr_tail}")
            return None
        output = result.stdout.strip()
        if not output:
            _log(f"claude 출력 없음: {key}")
            return None
        # 코드블록 래퍼 제거 (```markdown ... ``` 등)
        output = re.sub(r"^```[a-z]*\n", "", output)
        output = re.sub(r"\n```$", "", output)
        # 검증 게이트: 첫 줄 SKIP → junk 패턴 판정
        first_line = output.splitlines()[0].strip() if output else ""
        if first_line.upper() == "SKIP":
            return SKIP_SENTINEL
        return output
    except subprocess.TimeoutExpired:
        _log(f"timeout: {key}")
        return None
    except Exception as e:
        _log(f"오류: {e}")
        return None


def ensure_pattern_row(db_path: str, key: str) -> None:
    """pattern_count 밖에서 들어온 키(드림 propose 의 의미론적 키 등)도 장부에 1행 보장.
    이 행이 없으면 register_skill(crystallized=1)·mark_rejected(crystallized=-1) 의
    UPDATE 가 0행 매칭으로 조용히 무효가 되어 멱등성·junk 거부 기억이 깨진다.
    count=0 명시로 기존 fallback 동작(get_pattern_count→0)을 보존하고,
    이미 있는 경로 A 집계 키는 OR IGNORE 로 건드리지 않는다."""
    try:
        con = connect_db(db_path)
        con.execute(
            "INSERT OR IGNORE INTO pattern_count (pattern_key, count, crystallized) "
            "VALUES (?, 0, 0)", (key,)
        )
        con.commit()
        con.close()
    except Exception as e:
        _log(f"pattern_count 행 보장 실패({key}): {e}")


def mark_rejected(db_path: str, key: str) -> None:
    """junk 판정 패턴을 crystallized=-1 로 마킹해 재시도를 방지한다 (C3)."""
    try:
        con = connect_db(db_path)
        con.execute(
            "UPDATE pattern_count SET crystallized=-1 WHERE pattern_key=?", (key,)
        )
        con.commit()
        con.close()
    except Exception as e:
        _log(f"거부 마킹 실패({key}): {e}")


def register_skill(db_path: str, skill_path: str, key: str) -> None:
    """skill_index 에 등록하고 pattern_count를 결정화 완료로 표시한다."""
    # 영문 슬러그 토큰 + 본문(제목·문제상황·규칙·코드)의 한글 포함 키워드 합집합 —
    # 영문 키만 등록하면 한글 질의로 검색이 안 됐다(①). 본문 키워드로 한글도 색인.
    kw_set = set(t for t in key.replace("-", " ").split() if t)
    kw_set.add(key)
    try:
        kw_set |= extract_keywords(skill_path)
    except Exception as e:
        _log(f"본문 키워드 추출 실패({key}): {e}")
    keywords = ",".join(sorted(kw_set))
    now = datetime.now(timezone.utc).isoformat()
    con = connect_db(db_path)
    con.execute(
        "INSERT INTO skill_index (skill_path, keywords, scope, version, created_at, used_count) "
        "VALUES (?, ?, 'local', 1, ?, 0) "
        "ON CONFLICT(skill_path) DO UPDATE SET "
        "keywords = excluded.keywords, version = skill_index.version + 1",
        (skill_path, keywords, now),
    )
    con.execute(
        "UPDATE pattern_count SET crystallized=1 WHERE pattern_key=?", (key,)
    )
    con.commit()
    con.close()


def record_global_summary(key: str, skill_path: str, project_id: str) -> None:
    """결정화 성공 시 ~/.hermes/global.db 에 패턴 요약 1행을 기록한다 (LOW).

    전역 DB가 없으면 조용히 건너뛴다 — 최소 연동만.
    """
    global_db = os.path.join(os.path.expanduser("~/.hermes"), "global.db")
    if not os.path.isfile(global_db):
        return
    try:
        con = connect_db(global_db)
        con.execute(
            "INSERT INTO harness_rules (trigger_keywords, instruction, source_session_id, scope) "
            "VALUES (?, ?, ?, 'local')",
            (key, f"[{project_id}] 결정화 스킬: {skill_path}", project_id),
        )
        con.commit()
        con.close()
    except Exception as e:
        _log(f"global.db 요약 기록 실패({key}): {e}")


def crystallize(db_path: str, keys: list[str], project_dir: str) -> None:
    skills_dir = os.path.join(os.path.dirname(db_path), "skills")
    os.makedirs(skills_dir, exist_ok=True)
    project_id = os.path.basename(os.path.abspath(project_dir)) if project_dir else ""

    for key in keys:
        is_fallback = key not in CATEGORY_METADATA
        meta = CATEGORY_METADATA.get(key, {
            "description": key,
            "search_terms": _derive_search_terms(key),
        })

        # 장부 행 보장 — 드림 propose 등 pattern_count 밖 키의 멱등/거부기억 활성화
        ensure_pattern_row(db_path, key)

        # 이미 결정화(1)됐거나 거부(-1)됐으면 스킵
        try:
            con = connect_db(db_path)
            row = con.execute(
                "SELECT crystallized FROM pattern_count WHERE pattern_key=?", (key,)
            ).fetchone()
            con.close()
            if row and row[0] != 0:
                state = "이미 결정화됨" if row[0] == 1 else "junk 거부됨"
                print(f"[hermes-crystallize] SKIP:{key} — {state}")
                continue
        except Exception as e:
            _log(f"결정화 상태 조회 실패({key}): {e}")

        skill_path = os.path.join(skills_dir, f"{key}.md")
        evidence_limit = 10 if is_fallback else 5
        evidence = fetch_evidence(db_path, meta["search_terms"], limit=evidence_limit)
        count = get_pattern_count(db_path, key)

        content = generate_skill_content(key, meta, evidence, count, from_evidence=is_fallback)
        if content == SKIP_SENTINEL:
            mark_rejected(db_path, key)
            print(f"[hermes-crystallize] REJECT:{key} — junk 패턴 (재시도 안 함)")
            continue
        if not content:
            print(f"[hermes-crystallize] SKIP:{key} — 콘텐츠 생성 실패")
            continue

        with open(skill_path, "w", encoding="utf-8") as f:
            f.write(content + "\n")

        register_skill(db_path, skill_path, key)
        record_global_summary(key, skill_path, project_id)
        print(f"[hermes] DONE:{key}.md")


def main() -> None:
    parser = argparse.ArgumentParser(description="헤르메스 결정화")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--crystallize", required=True, help="결정화 대상 패턴 (콤마 구분)")
    parser.add_argument("--project-dir", default="", help="프로젝트 디렉터리")
    args = parser.parse_args()

    keys = [k.strip() for k in args.crystallize.split(",") if k.strip()]
    if not keys:
        print("[hermes-crystallize] no keys — skipped")
        return

    crystallize(args.db, keys, args.project_dir or os.path.dirname(os.path.dirname(args.db)))


if __name__ == "__main__":
    main()
