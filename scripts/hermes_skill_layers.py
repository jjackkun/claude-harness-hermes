#!/usr/bin/env python3
"""스킬 4층의 값·저장 경로·소유(`unit_id`·`agent_id`)·`skill_id`·`skill_index` 마이그레이션만 담당한다.

스킬은 네 층에 산다(설계 skill-layers.md S-01~S-04):

  universe  우주(공장)      `.claude/skills/<이름>/`          설치 목록에 있음, 모두가 받음
  common    소우주 공통      `.hermes/skills/`                 기존 1088개 자리 — 옮기지 않는다(L-01)
  unit      단위(팀)        `.hermes/units/<unit_id>/skills/`  그 단위만
  agent     개인            `.hermes/agents/<agent_id>/skills/` 그 개인만

`skill_id` 는 스킬의 신원이다(RV-13). 지금은 **같은 경로를 재색인해도 바뀌지 않게** 보존한다
(색인기가 처음 훑을 때 부여, 이후 `COALESCE` 로 보존). 기존 행은 마이그레이션이 `layer='common'` 만
채우고 `skill_id` 는 NULL 로 둔다. 층 이동(경로가 바뀌는 승격)에서 옛 skill_id 를 새 경로로 **이관**하는
연산은 이 계획에 없다(승격 자체가 Step 4 이후) — 그 연산이 생길 때 함께 넣는다(§7 발견).
계획: docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 1·2

공개 함수 6개: LAYERS · ensure_layer_columns · layer_dir · all_layer_dirs · layer_of_path · new_skill_id
"""

import glob
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_uuid7 import uuid7_str  # noqa: E402

LAYERS = ("universe", "common", "unit", "agent")

# 주입 순서는 층이 먼저다 — 개인 → 단위 → 소우주 공통 → 우주 공통(skill-layers.md §2·"층 우선순위는 주입 순서").
# **뽑는 것**은 점수로, **넣는 순서**만 층으로 한다 — 층을 선별 키로 쓰면 --max 가 작을 때 관련도 높은
# 공통 스킬이 0건으로 잘린다(2026-09-17 리뷰). 큰 값이 앞이다.
LAYER_RANK = {"agent": 3, "unit": 2, "common": 1, "universe": 0}


def inject_order(selected: list, layer_of) -> list:
    """점수로 뽑힌 목록을 층 순(개인→단위→공통→우주)으로 재배열한다. 같은 층 안 순서는 유지(안정 정렬)."""
    return sorted(selected, key=lambda item: -LAYER_RANK.get(layer_of(item), 0))

# skill_index 에 더하는 층 칸 5개. layer 만 DEFAULT 'common'(기존 행 즉시 백필), 나머지는 NULL.
_NEW_COLUMNS = (
    ("universe_id", "ALTER TABLE skill_index ADD COLUMN universe_id TEXT"),
    ("layer",       "ALTER TABLE skill_index ADD COLUMN layer TEXT DEFAULT 'common'"),
    ("unit_id",     "ALTER TABLE skill_index ADD COLUMN unit_id TEXT"),
    ("agent_id",    "ALTER TABLE skill_index ADD COLUMN agent_id TEXT"),
    ("skill_id",    "ALTER TABLE skill_index ADD COLUMN skill_id TEXT"),
)


def ensure_layer_columns(con, universe_id: str = None) -> bool:
    """skill_index 에 층 칸 5개를 멱등 보강한다. 기존 행은 `layer='common'`, `universe_id` 백필.

    새 칸이 없는 구버전 DB 에서 검색기·색인기가 죽지 않게 하는 지연 마이그레이션이기도 하다(목표 16).
    붙인 칸이 있으면 True.
    """
    cols = [r[1] for r in con.execute("PRAGMA table_info(skill_index)")]
    added = False
    for col, ddl in _NEW_COLUMNS:
        if col not in cols:
            try:
                con.execute(ddl)
            except sqlite3.OperationalError:
                # 다른 세션이 먼저 같은 칸을 붙였다(동시 설치 경합, "duplicate column name").
                # ALTER 는 즉시 자체 커밋되므로 그 칸은 이미 있다 — 넘어가면 된다.
                continue
            added = True
    # ADD COLUMN DEFAULT 은 상수라 기존 행을 채우지만, 칸이 이미 NULL 로 있던 경우까지 명시 백필한다.
    con.execute("UPDATE skill_index SET layer='common' WHERE layer IS NULL")
    if universe_id:
        con.execute("UPDATE skill_index SET universe_id=? WHERE universe_id IS NULL", (universe_id,))
    return added


def layer_dir(project: str, layer: str, unit_id: str = None, agent_id: str = None) -> str:
    """그 층의 스킬 저장 폴더 경로. unit·agent 층은 소유 id 가 있어야 한다."""
    if layer == "universe":
        return os.path.join(project, ".claude", "skills")
    if layer == "common":
        return os.path.join(project, ".hermes", "skills")
    if layer == "unit":
        if not unit_id:
            raise ValueError("unit 층은 unit_id 가 필요하다")
        return os.path.join(project, ".hermes", "units", unit_id, "skills")
    if layer == "agent":
        if not agent_id:
            raise ValueError("agent 층은 agent_id 가 필요하다")
        return os.path.join(project, ".hermes", "agents", agent_id, "skills")
    raise ValueError(f"모르는 층: {layer} (허용: {', '.join(LAYERS)})")


def all_layer_dirs(project: str):
    """색인기가 훑을 네 자리를 (layer, dir, unit_id, agent_id) 로 낸다.

    unit·agent 는 여러 개일 수 있어 glob 으로 펼친다. 없는 폴더도 그대로 낸다(색인기가 건너뛴다).
    """
    dirs = [("universe", layer_dir(project, "universe"), None, None),
            ("common", layer_dir(project, "common"), None, None)]
    for unit_skills in sorted(glob.glob(os.path.join(project, ".hermes", "units", "*", "skills"))):
        dirs.append(("unit", unit_skills, os.path.basename(os.path.dirname(unit_skills)), None))
    for agent_skills in sorted(glob.glob(os.path.join(project, ".hermes", "agents", "*", "skills"))):
        dirs.append(("agent", agent_skills, None, os.path.basename(os.path.dirname(agent_skills))))
    return dirs


def layer_of_path(project: str, skill_path: str):
    """스킬 파일 경로에서 (layer, unit_id, agent_id) 를 되짚는다. 판정 못 하면 ('common', None, None).

    경로 구조: `.hermes/units/<unit_id>/skills/…` · `.hermes/agents/<agent_id>/skills/…`.
    길이·값을 먼저 확인한 뒤 소유 id 를 꺼낸다(얕은 경로가 들어와도 IndexError 없이 common).
    """
    rel = os.path.relpath(os.path.abspath(skill_path), os.path.abspath(project))
    parts = rel.split(os.sep)
    if parts[:2] == [".claude", "skills"]:
        return "universe", None, None
    if len(parts) > 3 and parts[0] == ".hermes" and parts[3] == "skills":
        if parts[1] == "units":
            return "unit", parts[2], None
        if parts[1] == "agents":
            return "agent", None, parts[2]
    return "common", None, None


def new_skill_id() -> str:
    """스킬 신원(UUIDv7). 색인기가 그 경로를 처음 볼 때 한 번 부여하고 재색인에서 보존한다."""
    return uuid7_str()


def skill_visible(layer, unit_id, agent_id, viewer_agent_id, viewer_unit_id) -> bool:
    """이 스킬(층·소유)이 지금 세션 에이전트에게 보이는가(주입 필터, RV-12).

    universe·common 은 모두에게. unit 은 같은 unit_id 에게만. agent 는 그 개인에게만.
    알 수 없는 층(구 데이터)은 막지 않는다 — 필터가 기존 주입을 조용히 끊지 않게.
    """
    if layer in (None, "", "universe", "common"):
        return True
    if layer == "unit":
        return bool(viewer_unit_id) and unit_id == viewer_unit_id
    if layer == "agent":
        return bool(agent_id) and agent_id == viewer_agent_id
    return True
