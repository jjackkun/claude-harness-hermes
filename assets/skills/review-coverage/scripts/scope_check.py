"""리뷰 장부 검사 — 빠진 파일, 이유 없는 건너뜀, 범위 밖 지적, 어긋난 줄 번호."""
from scope_git import changed_lines, file_length

STATUSES = ("reviewed", "skipped")


def _ledger_files(ledger, errors):
    """{경로: (status, reason)} — 형식이 틀린 항목은 errors 에 적고 뺀다."""
    seen = {}
    for i, item in enumerate(ledger.get("files") or []):
        if not isinstance(item, dict) or not isinstance(item.get("path"), str) or item.get("status") not in STATUSES:
            errors.append(f"files[{i}]: 문자열 path 와 status(reviewed|skipped)가 필요합니다")
            continue
        reason = str(item.get("reason") or "").strip()
        if item["status"] == "skipped" and not reason:
            errors.append(f"{item['path']}: skipped 인데 reason 이 없습니다")
        seen[item["path"]] = (item["status"], reason)
    return seen


def _line_range(finding):
    """(start, end) 또는 None(줄 번호 없음). 숫자가 아니면 ValueError."""
    start = int(finding.get("start_line") or 0)
    end = int(finding.get("end_line") or start)
    return (start, end) if start else None


def _check_finding(scope, by_path, label, finding):
    """(error 또는 None, warning 또는 None)."""
    if not isinstance(finding, dict) or not isinstance(finding.get("path"), str):
        return f"{label}: 문자열 path 가 필요합니다", None
    path = finding["path"]
    if path not in by_path:
        return f"{label} {path}: 리뷰 범위에 없는 파일입니다", None
    try:
        span = _line_range(finding)
    except (TypeError, ValueError):
        return f"{label} {path}: start_line·end_line 은 정수여야 합니다", None
    if span is None:
        return None, f"{label} {path}: 줄 번호가 없습니다 — 파일을 다시 읽고 자리를 적으십시오"
    start, end = span
    length = file_length(scope, path)
    if length is None:
        return None, f"{label} {path}: 파일 길이를 알 수 없어 줄 번호를 확인하지 못했습니다"
    if start < 1 or start > end or end > length:
        return f"{label} {path}:{start}-{end}: 파일은 {length}줄입니다 — 줄 번호가 어긋났습니다", None
    if not changed_lines(scope, by_path[path]) & set(range(start, end + 1)):
        return None, f"{label} {path}:{start}-{end}: 바뀐 줄 밖입니다 — 의도한 지적인지 확인하십시오"
    return None, None


def _summary(by_path, seen):
    total = len(by_path)
    reviewed = sum(1 for p in by_path if seen.get(p, ("",))[0] == "reviewed")
    skipped = [f"{p}({seen[p][1]})" for p in by_path if seen.get(p, ("",))[0] == "skipped"]
    return {"total_files": total, "reviewed_files": reviewed, "skipped_files": len(skipped),
            "coverage_rate": round(reviewed / total, 3) if total else 1.0, "skipped": skipped}


def check_ledger(scope, ledger):
    """(errors, warnings, summary). errors 가 있으면 장부가 불완전하다.

    coverage_rate 는 실제로 읽은 파일 비율이다(건너뛴 파일은 세지 않는다).
    """
    if not isinstance(ledger, dict):
        return ['장부 맨 위는 {"files": [...], "findings": [...]} 여야 합니다'], [], {}
    errors, warnings = [], []
    by_path = {entry["path"]: entry for entry in scope["reviewable"]}
    seen = _ledger_files(ledger, errors)
    errors += [f"{p}: 장부에 없습니다 — 리뷰하거나 이유를 달아 skipped 로 적으십시오" for p in by_path if p not in seen]
    warnings += [f"{p}: 리뷰 범위 밖 파일이 장부에 있습니다 — 세 명령에 같은 방식·--exclude 를 줬는지 확인하십시오"
                 for p in seen if p not in by_path]
    for i, finding in enumerate(ledger.get("findings") or []):
        error, warning = _check_finding(scope, by_path, f"findings[{i}]", finding)
        errors += [error] if error else []
        warnings += [warning] if warning else []
    return errors, warnings, _summary(by_path, seen)
