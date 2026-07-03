#!/usr/bin/env python3
"""헤르메스 루프 — 완료 HTML 보고서 생성 (G15).

루프가 종료되면 loops·loop_steps·GOAL.md·git 로그를 읽어 자체완결 HTML
(인라인 CSS, 외부 URL·CDN 없음)을 report.html 로 저장한다. 사용자가 이를
열어 머지 여부를 판단한다. 저장된 마스킹 데이터(G12)만 렌더하므로 비밀
재노출이 없다. 결정적 코드가 담당 — 드라이버가 종료 직후 호출한다.
"""

import html
import os
import subprocess

import hermes_loop as core

GIT_CMD_TIMEOUT = 10   # 로컬 git 로그 조회 상한(초) — 원격 접근 없음

# 종료 사유 → (사람이 읽는 라벨, 색상 클래스)
_REASON_LABEL = {
    "goal-met":    ("목표 달성", "good"),
    "max-iter":    ("최대 반복 도달 — 미완료", "warn"),
    "no-progress": ("진전 없음 — 사람 개입 필요", "warn"),
    "blocked":     ("차단됨 — 사람 개입 필요", "bad"),
    "user-stop":   ("사용자 중단", "warn"),
    "error":       ("오류 — 안전 중단", "bad"),
}

# 인라인 CSS (외부 url() 없음, 라이트/다크 테마). plain 상수 — f-string 밖.
_CSS = """
:root{--bg:#f6f8f8;--sf:#fff;--sf2:#eef2f2;--ink:#14201f;--soft:#475856;--faint:#7c8c8a;--line:#dce4e3;--acc:#0d7d87;--acck:#075f68;--good:#2f8f5b;--warn:#b7791f;--bad:#c0483c;--mono:ui-monospace,Menlo,Consolas,monospace;--sans:system-ui,-apple-system,"Noto Sans KR",sans-serif}
@media(prefers-color-scheme:dark){:root{--bg:#0d1413;--sf:#141d1c;--sf2:#1b2726;--ink:#e6efee;--soft:#a3b3b1;--faint:#6f807e;--line:#24312f;--acc:#35bcc7;--acck:#6fd6df;--good:#4fbe82;--warn:#d9a441;--bad:#e0776b}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);line-height:1.6}
.wrap{max-width:860px;margin:0 auto;padding:2.5rem 1.4rem 5rem}
.eyebrow{font-family:var(--mono);font-size:.72rem;letter-spacing:.15em;text-transform:uppercase;color:var(--acck);margin:0 0 .6rem}
h1{font-size:1.8rem;line-height:1.15;letter-spacing:-.02em;margin:0 0 .7rem}
.meta{font-family:var(--mono);font-size:.8rem;color:var(--faint)}
.reason{display:inline-flex;align-items:center;gap:.4rem;font-weight:640;font-size:.85rem;padding:.32rem .7rem;border-radius:999px;margin-top:1rem}
.reason.good{background:color-mix(in srgb,var(--good) 15%,transparent);color:var(--good)}
.reason.warn{background:color-mix(in srgb,var(--warn) 15%,transparent);color:var(--warn)}
.reason.bad{background:color-mix(in srgb,var(--bad) 15%,transparent);color:var(--bad)}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:1px;background:var(--line);border:1px solid var(--line);border-radius:12px;overflow:hidden;margin:1.8rem 0 .5rem}
.stat{background:var(--sf);padding:1rem}
.stat .n{font-family:var(--mono);font-size:1.5rem;font-weight:640;font-variant-numeric:tabular-nums;display:block;line-height:1}
.stat .k{font-size:.76rem;color:var(--faint);margin-top:.45rem}
h2{font-size:1.1rem;margin:2.4rem 0 .9rem;letter-spacing:-.01em}
.goal{background:var(--sf);border:1px solid var(--line);border-radius:12px;padding:1.1rem 1.3rem}
.goal p{margin:0 0 1rem;color:var(--soft);white-space:pre-wrap}
.goal p:last-child{margin:0}
ul.cond{margin:0;padding:0;list-style:none;display:grid;gap:.45rem}
ul.cond li{display:grid;grid-template-columns:auto 1fr;gap:.55rem;font-size:.9rem}
ul.cond .box{font-family:var(--mono);font-weight:700}
ul.cond .done{color:var(--good)}ul.cond .todo{color:var(--faint)}
.tw{overflow-x:auto;border:1px solid var(--line);border-radius:12px}
table{width:100%;border-collapse:collapse;font-size:.85rem;min-width:520px}
th{text-align:left;font-size:.72rem;letter-spacing:.03em;text-transform:uppercase;color:var(--faint);background:var(--sf2);padding:.6rem .8rem;border-bottom:1px solid var(--line)}
td{padding:.55rem .8rem;border-bottom:1px solid var(--line);background:var(--sf);vertical-align:top}
tr:last-child td{border-bottom:none}
.v{font-family:var(--mono);font-size:.76rem;font-weight:600;padding:.12rem .45rem;border-radius:5px;white-space:nowrap}
.v.continue{background:var(--sf2);color:var(--soft)}
.v.goalmet{background:color-mix(in srgb,var(--good) 15%,transparent);color:var(--good)}
.v.blocked{background:color-mix(in srgb,var(--bad) 15%,transparent);color:var(--bad)}
.sig{font-family:var(--mono);font-size:.76rem;color:var(--faint)}.sig.pass{color:var(--good)}.sig.fail{color:var(--bad)}
.num{font-family:var(--mono);color:var(--faint);font-variant-numeric:tabular-nums}
.sha{font-family:var(--mono);font-size:.8rem;color:var(--acck);font-weight:600}
.empty{color:var(--faint);font-size:.88rem}
footer{margin-top:3rem;padding-top:1.2rem;border-top:1px solid var(--line);font-family:var(--mono);font-size:.76rem;color:var(--faint)}
"""


def _esc(v):
    return html.escape(str(v if v is not None else ""))


def _git_commits(project_dir, branch):
    """loop 브랜치가 main 대비 추가한 커밋 [(sha, subject)] — git 아니면 []."""
    if not branch:
        return []
    try:
        proc = subprocess.run(
            ["git", "log", "--oneline", "--no-decorate", f"main..{branch}"],
            cwd=project_dir, capture_output=True, text=True,
            timeout=GIT_CMD_TIMEOUT)
        if proc.returncode != 0:
            return []
        commits = []
        for line in proc.stdout.splitlines():
            parts = line.split(" ", 1)
            if len(parts) == 2:
                commits.append((parts[0], parts[1]))
        return commits
    except (subprocess.TimeoutExpired, OSError):
        return []


def _cond_rows(conditions):
    if not conditions:
        return '<li class="empty">완료 조건이 기록되지 않았습니다</li>'
    out = []
    for done, text in conditions:
        cls, box = ("done", "[x]") if done else ("todo", "[ ]")
        out.append(f'<li><span class="box {cls}">{box}</span>'
                   f'<span>{_esc(text)}</span></li>')
    return "".join(out)


def _step_rows(db_path, loop_id):
    con = core.connect_db(db_path)
    rows = con.execute(
        "SELECT iteration, verdict, objective_signal, progressed, action_summary"
        " FROM loop_steps WHERE loop_id=? ORDER BY iteration", (loop_id,)).fetchall()
    con.close()
    if not rows:
        return '<tr><td colspan="5" class="empty">반복 기록 없음</td></tr>'
    vcls = {"continue": "continue", "goal-met": "goalmet", "blocked": "blocked"}
    out = []
    for it, verdict, sig, prog, action in rows:
        vc = vcls.get(verdict, "continue")
        sc = sig if sig in ("pass", "fail") else ""
        mark = "●" if prog else "○"
        out.append(
            f'<tr><td class="num">{it}</td>'
            f'<td><span class="v {vc}">{_esc(verdict)}</span></td>'
            f'<td><span class="sig {sc}">{_esc(sig)}</span></td>'
            f'<td class="num">{mark}</td><td>{_esc(action)}</td></tr>')
    return "".join(out)


def _commit_block(commits):
    if not commits:
        return ('<div class="goal"><p class="empty">루프 브랜치에 커밋이 없습니다 '
                '(또는 git 저장소 아님)</p></div>')
    rows = "".join(f'<tr><td class="sha">{_esc(s)}</td><td>{_esc(m)}</td></tr>'
                   for s, m in commits)
    return ('<div class="tw"><table><thead><tr><th>SHA</th><th>메시지</th></tr>'
            f'</thead><tbody>{rows}</tbody></table></div>')


def render(db_path, project_dir, loop_id):
    """루프 상태를 자체완결 HTML 문자열로 렌더 (외부 URL 없음)."""
    loop = core.get_loop(db_path, loop_id)
    if not loop:
        raise ValueError(f"루프 없음: {loop_id}")
    goal = (core.read_goal_md(loop["goal_md_path"])
            if os.path.isfile(loop["goal_md_path"])
            else {"goal": "", "conditions": []})
    conds = goal.get("conditions", [])
    commits = _git_commits(project_dir, loop["branch"])
    reason = loop["finish_reason"] or "-"
    label, cls = _REASON_LABEL.get(reason, (reason, "warn"))
    goal_text = _esc(goal.get("goal", "")) or "(목표 서술 없음)"

    return f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>루프 보고서 · {_esc(loop['title'])}</title>
<style>{_CSS}</style></head><body><div class="wrap">
<p class="eyebrow">Hermes Loop · 완료 보고서</p>
<h1>{_esc(loop['title'])}</h1>
<div class="meta">{_esc(loop_id)} · {_esc(loop['created_at'])} → {_esc(loop['finished_at'] or '-')}</div>
<div class="reason {cls}">{_esc(label)}</div>
<div class="stats">
<div class="stat"><span class="n">{loop['iterations_used']}/{loop['max_iterations']}</span><div class="k">반복 / 최대</div></div>
<div class="stat"><span class="n">{core.checked_count(conds)}/{len(conds)}</span><div class="k">완료 조건</div></div>
<div class="stat"><span class="n">{len(commits)}</span><div class="k">루프 브랜치 커밋</div></div>
<div class="stat"><span class="n">{loop['no_progress_count']}</span><div class="k">무진전 연속</div></div>
</div>
<h2>목표</h2>
<div class="goal"><p>{goal_text}</p>
<ul class="cond">{_cond_rows(conds)}</ul></div>
<h2>반복 기록</h2>
<div class="tw"><table><thead><tr><th>#</th><th>판정</th><th>신호</th><th>진전</th><th>한 일</th></tr></thead>
<tbody>{_step_rows(db_path, loop_id)}</tbody></table></div>
<h2>루프 브랜치 커밋</h2>
{_commit_block(commits)}
<footer>브랜치 {_esc(loop['branch'] or '(없음)')} · 자체완결 HTML (외부 연결 없음)</footer>
</div></body></html>"""


def write_report(db_path, project_dir, loop_id):
    """report.html 을 loop 디렉토리에 저장하고 경로 반환."""
    loop = core.get_loop(db_path, loop_id)
    if not loop:
        raise ValueError(f"루프 없음: {loop_id}")
    path = os.path.join(os.path.dirname(loop["goal_md_path"]), "report.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(render(db_path, project_dir, loop_id))
    return path
