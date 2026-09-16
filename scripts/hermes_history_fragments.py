#!/usr/bin/env python3
"""대화 원문을 **턴 조각**으로 나눠 쓰고 읽는다.

전에는 세션 하나가 파일 하나였고 매 턴 전량 재작성했다. 그러면 (1) 같은 내용을 계속 다시
쓰고 (2) 두 컴퓨터가 같은 파일을 고쳐 충돌하며 (3) Step 3 에서 통째로 다시 암호화해야 한다.
조각은 한 번 쓰면 바뀌지 않으므로 이 셋이 모두 없어진다.

배치: `.hermes/history/<session_id>/<순번 4자리>.jsonl` (Step 3 에서 `.enc` 로 잠긴다)
계획: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 2

공개 함수: fragment_dir · existing_fragments · active_fragments · exported_line_count ·
write_fragment · mark_superseded · superseded_names · session_dates · count_active_lines
"""

import glob
import json
import os
from datetime import datetime

_SUFFIX = ".jsonl"
_SUPERSEDED = ".superseded"   # 압축이 대체한 조각 이름 목록(한 줄에 하나)


def fragment_dir(hist_dir: str, session_id: str) -> str:
    """그 세션의 조각 폴더."""
    return os.path.join(hist_dir, session_id)


def existing_fragments(hist_dir: str, session_id: str) -> list:
    """이미 쓴 조각 경로를 순번대로. 없으면 빈 목록."""
    return sorted(glob.glob(os.path.join(fragment_dir(hist_dir, session_id), "*" + _SUFFIX)))


def exported_line_count(hist_dir: str, session_id: str) -> int:
    """이미 조각으로 내보낸 줄 수 — 다음 조각의 시작 위치다."""
    total = 0
    for path in existing_fragments(hist_dir, session_id):
        with open(path, encoding="utf-8") as fh:
            total += sum(1 for line in fh if line.strip())
    return total


def write_fragment(hist_dir: str, session_id: str, records: list) -> str:
    """새 조각 하나를 쓰고 경로를 돌려준다. records 가 비면 아무것도 쓰지 않는다.

    기존 조각은 절대 건드리지 않는다(추가 전용).
    """
    if not records:
        return ""
    directory = fragment_dir(hist_dir, session_id)
    os.makedirs(directory, exist_ok=True)
    seq = len(existing_fragments(hist_dir, session_id))
    path = os.path.join(directory, "%04d%s" % (seq, _SUFFIX))
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        for record in records:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    os.replace(tmp, path)   # 원자적 — 반쯤 쓰인 조각이 남지 않는다
    return path


def superseded_names(hist_dir: str, session_id: str) -> set:
    """압축이 대체한 조각 이름들. 표시가 없으면 빈 집합."""
    path = os.path.join(fragment_dir(hist_dir, session_id), _SUPERSEDED)
    try:
        with open(path, encoding="utf-8") as fh:
            return {line.strip() for line in fh if line.strip()}
    except OSError:
        return set()


def active_fragments(hist_dir: str, session_id: str) -> list:
    """대체되지 않은 조각만. 압축된 세션은 요약 조각 하나만 남는다.

    원 조각 파일은 지우지 않는다 — 추가 전용이고, 복구 경로가 여기뿐이다(목표 12).
    """
    dead = superseded_names(hist_dir, session_id)
    return [p for p in existing_fragments(hist_dir, session_id)
            if os.path.basename(p) not in dead]


def mark_superseded(hist_dir: str, session_id: str, names) -> str:
    """조각들을 '대체됨' 으로 표시한다(파일은 그대로 둔다). 표시 파일 경로를 돌려준다."""
    path = os.path.join(fragment_dir(hist_dir, session_id), _SUPERSEDED)
    existing = superseded_names(hist_dir, session_id)
    merged = sorted(existing | {os.path.basename(n) for n in names})
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(merged) + "\n")
    os.replace(tmp, path)
    return path


def session_dates(hist_dir: str) -> dict:
    """{session_id: (첫 기록 시각, 조각 폴더)} — 조각 폴더 형식만.

    폴더 이름에는 날짜가 없다(세션 id 뿐). "오래됨" 을 재는 쪽(생애주기 압축)이 쓰는 날짜는
    **첫 활성 조각의 첫 기록 시각**이다 — 파일명에 날짜를 넣던 옛 방식과 같은 값이다.
    """
    out = {}
    if not os.path.isdir(hist_dir):
        return out
    for name in sorted(os.listdir(hist_dir)):
        path = os.path.join(hist_dir, name)
        if not os.path.isdir(path):
            continue
        frags = active_fragments(hist_dir, name)
        if not frags:
            continue
        date = _first_timestamp(frags[0])
        if date is not None:
            out[name] = (date, path)
    return out


def _first_timestamp(path: str):
    try:
        with open(path, encoding="utf-8") as fh:
            stamp = json.loads(fh.readline() or "{}").get("timestamp") or ""
        return datetime.fromisoformat(stamp[:19]) if stamp else None
    except (OSError, ValueError, json.JSONDecodeError, AttributeError):
        return None


def count_active_lines(session_path: str) -> int:
    """조각 폴더의 대체되지 않은 줄 수."""
    total = 0
    for frag in active_fragments(os.path.dirname(session_path), os.path.basename(session_path)):
        try:
            with open(frag, encoding="utf-8") as fh:
                total += sum(1 for line in fh if line.strip())
        except OSError:
            pass
    return total
