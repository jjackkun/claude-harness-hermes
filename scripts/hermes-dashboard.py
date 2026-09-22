#!/usr/bin/env python3
"""소우주·우주 대시보드 CLI (계획 2026-09-18-hermes-dashboard 목표 1·6).

  --project-dir <소우주>     .hermes/dashboards/dashboard.html 을 쓴다
  --universe [--registry F]  공장의 .installed-projects 를 훑어 .hermes/dashboards/universe-dashboard.html 을 쓴다

정적 HTML 한 파일, 외부 자원 0, 모델 호출 0. 데이터는 hermes_dashboard_data, 렌더는 hermes_dashboard_html.
"""
import argparse
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_dashboard_data import collect, collect_universe  # noqa: E402
from hermes_dashboard_html import render_project, render_universe  # noqa: E402


# 대시보드는 .hermes/ 의 DB·로그·마커와 섞이지 않게 한 폴더에 둔다(계획 2026-09-22-rule-candidates-dashboard).
DASHBOARD_DIR = os.path.join(".hermes", "dashboards")


def _write(root: str, name: str, text: str, out: str = None) -> str:
    """<root>/.hermes/dashboards/<name> 에 쓰고, 옛 경로(<root>/.hermes/<name>)의 낡은 페이지는 지운다 —
    남겨 두면 갱신이 멈춘 페이지를 최신으로 오인한다. out 을 주면 그 경로에만 쓴다(시험·미리보기용)."""
    path = out or os.path.join(root, DASHBOARD_DIR, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)
    legacy = os.path.join(root, ".hermes", name)
    if not out and os.path.isfile(legacy):
        os.remove(legacy)
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description="헤르메스 대시보드")
    ap.add_argument("--project-dir", default=None, help="소우주 경로 (기본: 현재 디렉터리)")
    ap.add_argument("--universe", action="store_true", help="공장의 설치 레지스트리로 우주 페이지를 쓴다")
    ap.add_argument("--registry", default=None, help="레지스트리 파일(기본 <공장>/.installed-projects)")
    ap.add_argument("--factory", default=None, help="공장 경로(기본: 이 스크립트의 저장소)")
    ap.add_argument("--out", default=None, help="출력 파일 경로(기본: <대상>/.hermes/dashboards/…). 시험은 임시 경로를 준다")
    args = ap.parse_args()
    if args.universe:
        factory = os.path.abspath(args.factory or os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
        rows = collect_universe(factory, args.registry)
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        out = _write(factory, "universe-dashboard.html", render_universe(rows, os.path.basename(factory), now), args.out)
        print(f"우주 대시보드 → {out} (소우주 {len(rows)}곳)")
        return 0
    project = os.path.abspath(args.project_dir or os.getcwd())
    data = collect(project)
    out = _write(project, "dashboard.html", render_project(data), args.out)
    print(f"대시보드 → {out}" + (" (state.db 없음 — 판이 비어 있음)" if data["db_missing"] else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
