"""open_docs.py 단위 시험 — 열린 문서 판정 규칙표(P1~P7 · D1~D2 · F1)를 줄마다 하나씩 잰다.

R-iface-waiver: 공개 심볼은 전부 pytest 수집 대상 테스트 함수다. 지는 책임은 하나 —
`open_docs.py` 의 판정 계약.

무엇을 지키는가: 이 판정이 열린 계획서를 "닫힘" 으로 읽으면 finish.sh 가 계획 중간에 worktree 를 지운다
(2026-11-25 jj-agent-room 사고).
계획: docs/exec-plans/completed/2026-11-25-worktree-finish-open-docs-plan.md (G1)
"""

import importlib.util
import sys
from pathlib import Path

_SRC = Path(__file__).resolve().parent.parent / "assets" / "hooks" / "open_docs.py"
_spec = importlib.util.spec_from_file_location("_open_docs_under_test", _SRC)
od = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = od
_spec.loader.exec_module(od)

PLAN = "docs/exec-plans/active/2026-11-25-x-plan.md"
DONE = "docs/exec-plans/completed/2026-11-25-x-plan.md"
PRD = "docs/product-specs/x/prd.md"


def plan(goals: str, after: str = "## 3. 비목표\n\n- [ ] 여긴 §2 밖\n") -> str:
    return f"# 제목\n\n## 1. 동기\n\n- [ ] 여긴 §1\n\n## 2. 목표\n\n{goals}\n{after}"


def judge(path: str, body: str | None) -> list[tuple[str, str]]:
    return od.open_docs([(path, body)])


def test_section_starts_at_h2_2_dot():
    body = plan("- [x] G1", after="## 2-bis. 사실\n\n- [ ] 표 밖 항목\n\n## 3. 비목표\n")
    assert judge(PLAN, body) == []
    assert od.open_items("## 2-bis. 사실\n- [ ] a\n") is None


def test_h3_goals_inside_section():
    body = plan("### G1\n\n- [ ] 하나\n\n### G2\n\n- [ ] 둘\n")
    assert judge(PLAN, body) == [(PLAN, "§2 미완료 2개")]


def test_open_item_regex():
    body = plan("- [ ] a\n  - [ ] 들여쓴 b\n* [ ] c\n+ [ ] d\n-[ ] 띄어쓰기 없음\n")
    assert od.open_items(body) == 4


def test_inline_code_not_counted():
    body = plan("- [x] G1 열린 항목은 `- [ ]` 로 적는다\n문장 속 `- [ ]` 도 세지 않는다\n")
    assert judge(PLAN, body) == []


def test_checked_variants():
    assert judge(PLAN, plan("- [x] a\n- [X] b\n")) == []


def test_fenced_lines_ignored():
    body = plan("- [x] a\n```text\n## 3. 가짜 끝\n- [ ] 가짜 열림\n```\n- [ ] 진짜 열림\n")
    assert judge(PLAN, body) == [(PLAN, "§2 미완료 1개")]


def test_fence_rules_from_review():
    """코드 리뷰 HIGH 2건 — 한 줄 코드 · 길이가 다른 펜스 · 닫히지 않은 펜스가 뒤의 열린 항목을 가리지 않는다."""
    assert od.open_items(plan("```x``` 한 줄 코드\n- [ ] a\n")) == 1
    assert od.open_items(plan("````md\n```\n- [ ] 펜스 안\n```\n````\n- [ ] 밖\n")) == 1
    assert od.open_items(plan("~~~\n- [ ] 펜스 안\n~~~\n- [ ] 밖\n")) == 1
    assert judge(PLAN, plan("- [x] a\n```\n- [ ] 닫히지 않음\n")) == [(PLAN, "코드 펜스가 닫히지 않음")]
    assert judge(PRD, "```\n- status: approved\n") == [(PRD, "코드 펜스가 닫히지 않음")]


def test_numbered_items_and_section_without_items():
    """리뷰 MEDIUM — 번호 목록도 항목이다. 체크 항목이 하나도 없는 §2 는 끝났는지 읽을 수 없어 열림이다(P9)."""
    assert judge(PLAN, plan("1. [ ] a\n2) [x] b\n")) == [(PLAN, "§2 미완료 1개")]
    assert judge(PLAN, plan("1. [x] a\n")) == []
    assert judge(PLAN, plan("목표는 산문으로만 썼다\n")) == [(PLAN, "§2 항목 없음")]


def test_missing_section_is_open():
    for head in ("## 2 목표", "## 2) 목표", "# 2. 목표"):
        assert judge(PLAN, f"# t\n\n{head}\n\n- [x] a\n") == [(PLAN, "§2 절 없음")]


def test_completed_with_open_items():
    assert judge(DONE, plan("- [x] a\n- [ ] b\n")) == [(DONE, "completed 인데 §2 미완료 1개")]
    assert judge(DONE, plan("- [x] a\n")) == []


def test_prd_status_bullet():
    assert judge(PRD, "# p\n\n- status: approved\n- updated: 2026-11-25\n") == []
    assert judge(PRD, "status: Approved\n") == []
    assert judge(PRD, '  * status: "APPROVED"\n') == []


def test_prd_status_open_values():
    assert judge(PRD, "- status: draft\n") == [(PRD, "status: draft")]
    assert judge(PRD, "- status: draft | approved\n") == [(PRD, "status: draft")]
    assert judge(PRD, "- status: wip\n") == [(PRD, "status: wip")]
    assert judge(PRD, "# p\n\n본문만\n") == [(PRD, "status 줄 없음")]


def test_deleted_and_non_plan_skipped():
    open_body = plan("- [ ] a\n")
    assert judge(PLAN, None) == []
    assert judge("docs/exec-plans/active/README.md", open_body) == []
    assert judge("docs/exec-plans/backlog/x.md", open_body) == []
    assert judge("docs/product-specs/x/brief.md", "- status: draft\n") == []
