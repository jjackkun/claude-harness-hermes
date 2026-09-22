#!/usr/bin/env python3
"""대시보드 dict → HTML 문자열. 데이터 로직 없음. 외부 자원 0(인라인 CSS·시스템 글꼴), 스크립트 0.
루프 보고서(hermes_loop_report.py)와 같은 색·글꼴 토큰을 써 한 결로 보인다. 다크 모드는 토큰이 담당.
공개 함수 2개: render_project · render_universe
"""
import html

_CSS = """
:root{--bg:#f6f8f8;--sf:#fff;--sf2:#eef2f2;--ink:#14201f;--soft:#475856;--faint:#7c8c8a;--line:#dce4e3;--acc:#0d7d87;--acck:#075f68;--good:#2f8f5b;--warn:#b7791f;--bad:#c0483c;--mono:ui-monospace,Menlo,Consolas,monospace;--sans:system-ui,-apple-system,"Noto Sans KR",sans-serif}
@media(prefers-color-scheme:dark){:root{--bg:#0d1413;--sf:#141d1c;--sf2:#1b2726;--ink:#e6efee;--soft:#a3b3b1;--faint:#6f807e;--line:#24312f;--acc:#35bcc7;--acck:#6fd6df;--good:#4fbe82;--warn:#d9a441;--bad:#e0776b}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);line-height:1.6}
.wrap{max-width:960px;margin:0 auto;padding:2.5rem 1.4rem 5rem}
.eyebrow{font-family:var(--mono);font-size:.72rem;letter-spacing:.15em;text-transform:uppercase;color:var(--acck);margin:0 0 .6rem}
h1{font-size:1.8rem;line-height:1.15;letter-spacing:-.02em;margin:0 0 .4rem}
.meta{font-family:var(--mono);font-size:.8rem;color:var(--faint)}
h2{font-size:1.1rem;margin:2.6rem 0 .3rem;letter-spacing:-.01em}
h2 + .lead{margin:0 0 1rem;color:var(--soft);font-size:.9rem}
.row{display:flex;flex-wrap:wrap;gap:.4rem 1.6rem;margin:0 0 1rem;font-size:.9rem}
.row b{font-family:var(--mono);font-variant-numeric:tabular-nums;font-weight:640}
.row .k{color:var(--faint)}
h3{font-size:.8rem;letter-spacing:.06em;text-transform:uppercase;color:var(--faint);margin:1.4rem 0 .5rem;font-weight:600}
.tw{overflow-x:auto;border:1px solid var(--line);border-radius:12px}
table{width:100%;border-collapse:collapse;font-size:.85rem;min-width:520px}
th{text-align:left;font-size:.72rem;letter-spacing:.03em;text-transform:uppercase;color:var(--faint);background:var(--sf2);padding:.6rem .8rem;border-bottom:1px solid var(--line)}
td{padding:.55rem .8rem;border-bottom:1px solid var(--line);background:var(--sf);vertical-align:top}
tr:last-child td{border-bottom:none}
td.n,th.n{text-align:right;font-family:var(--mono);font-variant-numeric:tabular-nums;white-space:nowrap}
.tag{font-family:var(--mono);font-size:.74rem;font-weight:600;padding:.1rem .45rem;border-radius:5px;white-space:nowrap}
.tag.ok{background:color-mix(in srgb,var(--good) 15%,transparent);color:var(--good)}
.tag.warn{background:color-mix(in srgb,var(--warn) 15%,transparent);color:var(--warn)}
.tag.bad{background:color-mix(in srgb,var(--bad) 15%,transparent);color:var(--bad)}
.tag.dim{background:var(--sf2);color:var(--soft)}
.mono{font-family:var(--mono);font-size:.8rem}
.empty{color:var(--faint);font-size:.88rem;margin:.4rem 0 0}
.note{color:var(--bad);font-weight:600;margin:.6rem 0 0}
footer{margin-top:3rem;padding-top:1.2rem;border-top:1px solid var(--line);font-family:var(--mono);font-size:.76rem;color:var(--faint)}
"""


def _e(v) -> str:
    return html.escape("" if v is None else str(v))


def _table(headers, rows, numeric=()) -> str:
    """헤더 목록·행 목록(셀은 이미 HTML) → 표. 행이 없으면 빈 안내."""
    if not rows:
        return '<p class="empty">없음</p>'
    th = "".join(f'<th class="n">{_e(h)}</th>' if i in numeric else f"<th>{_e(h)}</th>" for i, h in enumerate(headers))
    body = "".join("<tr>" + "".join(f'<td class="n">{c}</td>' if i in numeric else f"<td>{c}</td>"
                                     for i, c in enumerate(r)) + "</tr>" for r in rows)
    return f'<div class="tw"><table><thead><tr>{th}</tr></thead><tbody>{body}</tbody></table></div>'


def _tag(text, kind) -> str:
    return f'<span class="tag {kind}">{_e(text)}</span>'


def _pct(rate) -> str:
    return "—" if rate is None else f"{100 * rate:.1f}%"


def _roster_rows(roster: list) -> list:
    kind = {"retired": "dim", "active": "ok"}
    return [[_e(r["name"]), _tag(r["status"], kind.get(r["status"], "warn")),
             _e("/".join(x or "-" for x in (r["discipline"], r["rank"], r["unit"])))] for r in roster]


def _handoff_rows(items: list) -> list:
    def who(to):
        return to.replace("agent:", "")[:8] if to.startswith("agent:") else to
    return [[_e(who(h["to"])), _e(h["kind"]), _e(h["goal"]), _tag("막힘", "bad") if h["blocked"] else _tag("열림", "ok"),
             f'<span class="mono">{_e((h["ts"] or "")[:16])}</span>'] for h in items]


def _summons_rows(items: list) -> list:
    return [[_e(s["name"]), _e(s["requested_by"]), f'<span class="mono">{_e((s["issued_at"] or "")[:16])}</span>',
             _tag("사용", "dim") if s["used_at"] else _tag("대기", "warn")] for s in items]


def _correction_rows(items: list) -> list:
    return [[_e(c["name"]), f'<span class="mono">{_e(c["about"])}</span>', _e(c["count"]),
             _tag("결정화 임계", "warn") if c["count"] >= 3 else ""] for c in items]


def _agents(a: dict) -> str:
    active = sum(1 for r in a["roster"] if r["status"] != "retired")
    blocked = sum(1 for h in a["open_handoffs"] if h["blocked"])
    stats = ((active, "현역"), (len(a["roster"]) - active, "은퇴"), (len(a["open_handoffs"]), "열린 인계"),
             (blocked, "막힘"), (a["owner_proposals"], "담당 없음 제안"))
    row = "".join(f'<span><b>{n}</b> <span class="k">{k}</span></span>' for n, k in stats)
    return (f'<h2 id="agents">에이전트</h2><p class="lead">누가 있고, 무엇이 열려 있고, 누가 무엇을 지적받았나.</p><div class="row">{row}</div>'
            f"<h3>명부</h3>{_table(['이름', '상태', '분야/직급/조직'], _roster_rows(a['roster']))}"
            f"<h3>열린 인계</h3>{_table(['받는 쪽', '종류', '목표', '상태', '시각'], _handoff_rows(a['open_handoffs']))}"
            f"<h3>최근 소환 10</h3>{_table(['에이전트', '요청', '발급', '상태'], _summons_rows(a['summons_recent']))}"
            f"<h3>리뷰 지적 누적 (about 별)</h3>{_table(['에이전트', 'about', '횟수', ''], _correction_rows(a['corrections']), numeric=(2,))}")


def _skills(s: dict) -> str:
    layers = "".join(f'<span><b>{n}</b> <span class="k">{_e(k)}</span></span>' for k, n in s["by_layer"].items())
    top = [[f'<span class="mono">{_e(i["skill_path"].rsplit("/", 1)[-1])}</span>', _e(i["injected"]), _e(i["helpful"]), _e(_pct(i["rate"]))]
           for i in s["top_injected"]]
    demote = [[f'<span class="mono">{_e(d["skill_path"].rsplit("/", 1)[-1])}</span>', _e(d["injected"]), _e(d["helpful"]), _e(_pct(d["rate"]))]
              for d in s["demote_candidates"]]
    pend = [[_e(p["key"]), _e(p["count"])] for p in s["pending_crystallize"]]
    return (f'<h2 id="skills">스킬</h2><p class="lead">네 층에 몇 개, 무엇이 자주 들어가고, 무엇이 도움이 안 되나.</p>'
            f'<div class="row">{layers}</div>'
            f"<h3>주입 상위 10 · 도움률</h3>{_table(['스킬', '주입', '도움', '도움률'], top, numeric=(1, 2, 3))}"
            f"<h3>강등 후보 (hermes-cleanup 과 같은 기준)</h3>{_table(['스킬', '주입', '도움', '도움률'], demote, numeric=(1, 2, 3))}"
            f"<h3>결정화 대기 (3회 이상, 미결정화)</h3>{_table(['패턴 키', '횟수'], pend, numeric=(1,))}")


def _learning(l: dict) -> str:
    return (f'<h2 id="learning">학습 루프</h2><p class="lead">요약이 쌓이고, 드림이 돌고, 스킬이 진화한 흔적.</p>'
            f'<div class="row"><span><b>{l["summaries"]}</b> <span class="k">세션 요약</span></span><span><b>{l["dream_runs"]}</b> <span class="k">드림 실행</span></span>'
            f'<span><b>{l["evolved"]}</b> <span class="k">진화</span></span><span><b>{l["crystallized"]}</b> <span class="k">결정화</span></span></div>'
            f'<p class="mono">마지막 드림 {_e(l["last_dream"] or "없음")} · 다음 가능 {_e(l["next_dream_at"] or "지금")}</p>')


def _health(h: dict) -> str:
    gates = [[_e(g["rule"]), _e(g["chance"]), _e(g["warn"]), _e(g["block"]), _e(g["rate"])] for g in h["gates_top"]]
    debt = [[f'<span class="mono">{_e(f)}</span>'] for f in h["review_debt"]]
    plans = [[f'<span class="mono">{_e(p)}</span>'] for p in h["active_plans"]]
    return (f'<h2 id="health">건강</h2><p class="lead">게이트가 얼마나 걸리고, 리뷰 빚이 얼마고, 무엇이 진행 중인가.</p>'
            f"<h3>게이트 발화율 상위 5</h3>{_table(['규칙', '기회', '경고', '차단', '발화율'], gates, numeric=(1, 2, 3, 4))}"
            f"<h3>리뷰 빚 ({len(h['review_debt'])})</h3>{_table(['파일'], debt)}"
            f"<h3>활성 계획 ({len(h['active_plans'])})</h3>{_table(['계획'], plans)}"
            f"{_fixed_context(h.get('fixed_context') or {})}")


_RULE_SHOW_PENDING = 10   # 보류는 최근 것만 — 전부는 완료 계획서 회고에 있다


def _rule_rows(items: list) -> list:
    return [[_e(i["count"]), _e(i["text"]), _e(i["latest"]),
             '<span class="mono">' + _e(", ".join(f for f, _d in i["sources"][-2:])) + "</span>"] for i in items]


def _rules(items: list) -> str:
    """승격 후보 — 완료 계획서 회고의 "다음 룰 후보"(계획 2026-09-22-rule-candidates-dashboard)."""
    by = {k: [i for i in items if i["status"] == k] for k in ("review", "pending", "promoted", "dropped")}
    head = ["반복", "후보", "최근", "출처"]
    rest = len(by["pending"]) - _RULE_SHOW_PENDING
    more = f'<p class="lead">외 {rest}건 — docs/exec-plans/completed/ 회고의 "다음 룰 후보"</p>' if rest > 0 else ""
    return (f'<h2 id="rules">승격 후보</h2><p class="lead">완료 계획서 회고의 "다음 룰 후보". 두 번 이상 나온 교훈은 '
            f'{_tag("검토 필요", "warn")} — <span class="mono">harness-promote-rule</span> 스킬로 R 룰 승격을 검토한다.</p>'
            f'<p>검토 필요 {len(by["review"])} · 보류 {len(by["pending"])} · 승격됨 {len(by["promoted"])} · 폐기 {len(by["dropped"])}</p>'
            f"<h3>검토 필요 ({len(by['review'])})</h3>{_table(head, _rule_rows(by['review']), numeric=(0,))}"
            f"<h3>보류 — 최근 {min(len(by['pending']), _RULE_SHOW_PENDING)}</h3>"
            f"{_table(head, _rule_rows(by['pending'][:_RULE_SHOW_PENDING]), numeric=(0,))}{more}")


def _fixed_context(fx: dict) -> str:
    """세션 고정 비용 한 줄 — 무엇이 매 세션 컨텍스트를 먹는가(계획 context-budget)."""
    if not fx.get("bytes"):
        return ""
    top = " · ".join(f"{_e(k)} {_e(v)}B" for k, v in fx.get("top", []))
    return (f"<h3>세션 고정 비용</h3><p>{_e(fx['bytes'])} B ≈ {_e(fx['tokens'])} 토큰 "
            f"<span class=\"mono\">({top})</span></p>"
            f"<p class=\"lead\">토큰은 바이트÷3 근사. 스킬·에이전트 본문은 호출 때만 들어오므로 빠져 있다.</p>")


def render_project(d: dict) -> str:
    missing = '<p class="note">state.db 가 없다 — hermes 미설치이거나 초기화 전. 판이 비어 있다.</p>' if d.get("db_missing") else ""
    nav = " · ".join(f'<a href="#{k}">{v}</a>' for k, v in (("agents", "에이전트"), ("skills", "스킬"), ("learning", "학습"), ("health", "건강"), ("rules", "승격 후보")))
    return (f'<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{_e(d["project"])} — 소우주 대시보드</title><style>{_CSS}</style></head><body><div class="wrap">'
            f'<p class="eyebrow">Hermes · 소우주</p><h1>{_e(d["project"])}</h1><p class="meta">{_e(d["generated_at"])} · {nav}</p>{missing}'
            f'{_agents(d["agents"])}{_skills(d["skills"])}{_learning(d["learning"])}{_health(d["health"])}{_rules(d.get("rules", []))}'
            f'<footer>python3 scripts/hermes-dashboard.py --project-dir . · 보기 전용 · 외부 자원 0</footer></div></body></html>\n')


def render_universe(rows: list, factory: str, generated_at: str) -> str:
    body = []
    for r in rows:
        if not r["installed"]:
            body.append([_e(r["project"]), _tag("미설치", "dim"), "", "", "", "", "", ""])
            continue
        match = {True: _tag("일치", "ok"), False: _tag("뒤처짐", "warn"), None: _tag("미상", "dim")}[r.get("factory_match")]
        body.append([_e(r["project"]), _tag("설치", "ok"), _e(r["agents"]), _e(r["skills"]), _e(_pct(r["helpful_rate"])),
                     _e(r["demote_candidates"]), f'<span class="mono">{_e((r["last_dream"] or "없음")[:16])}</span>', match])
    table = _table(["소우주", "상태", "에이전트", "스킬", "도움률", "강등 후보", "마지막 드림", "factory"], body, numeric=(2, 3, 4, 5))
    return (f'<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>우주 대시보드</title><style>{_CSS}</style></head><body><div class="wrap">'
            f'<p class="eyebrow">Hermes · 우주</p><h1>소우주 {len(rows)}곳</h1><p class="meta">{_e(generated_at)} · 공장 {_e(factory)}</p>'
            f'<h2>한눈에</h2><p class="lead">소우주별 에이전트·스킬·도움률·강등 후보·드림·공장 일치 여부.</p>{table}'
            f'<footer>python3 scripts/hermes-dashboard.py --universe · 읽기 전용(mode=ro)</footer></div></body></html>\n')
