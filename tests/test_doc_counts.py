"""doc_counts.py 단위 시험 — 파싱이 조용히 틀리지 않는지 본다.

R-iface-waiver: 공개 심볼 8개는 전부 pytest 수집 대상 테스트 함수이며 지는 책임은
하나다 — `doc_counts.py` 의 배열 파싱 계약. pytest 는 `test_` 로 시작하는 **공개**
함수만 수집하므로 밑줄로 감추면 시험 자체가 사라진다. 파일을 쪼개면 같은 계약이
여러 파일로 흩어져 오히려 책임이 흐려진다.
근거: docs/exec-plans/active/2026-09-08-resolve-gate-warnings.md §7

왜 pytest 인가 (2026-09-08):
  이 저장소의 `.py` 판정 모듈들은 bash 통합 시험으로만 검증돼 왔고, `tests/` 에
  파이썬 테스트가 하나도 없어 R-test 가 "수집된 테스트가 0개" 경고를 내고 있었다.
  경고를 끄려고 빈 테스트를 두면 게이트가 죽은 채 통과 표시를 낸다 — 그래서
  실제로 틀릴 수 있는 경로만 골라 단언한다.

무엇을 지키는가: `_bash_array` 는 이 게이트 전체가 딛고 선 파싱이다. 여기가 조용히
틀리면 문서 수치가 조용히 틀리고, 그 수치를 강제하는 게이트까지 함께 틀린다.
"""

import importlib.util
from pathlib import Path

import pytest

# 경로를 고정해 읽는다. `sys.path.insert` + `import doc_counts` 로 하면 모듈 이름으로
# 캐시되므로, 같은 이름의 사본(scripts/hooks/doc_counts.py)을 대상으로 하는 시험이
# 나중에 추가됐을 때 먼저 캐시된 쪽이 조용히 재사용돼 **두 사본의 드리프트를 숨긴다.**
# gate_report.py 가 이미 쓰는 방식이다.
_SRC = Path(__file__).resolve().parent.parent / "assets" / "hooks" / "doc_counts.py"
_spec = importlib.util.spec_from_file_location("_doc_counts_under_test", _SRC)
doc_counts = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doc_counts)


def test_여러_줄_배열을_읽는다():
    text = "SKILLS+=(\n  alpha\n  beta\n)\n"
    assert doc_counts._bash_array(text, "SKILLS") == ["alpha", "beta"]


def test_항목_주석의_괄호가_배열을_자르지_않는다():
    """실측 2026-09-08: 첫 `)` 로 자르면 훅 10 / 모듈 4 라는 틀린 값이 나왔다."""
    text = "SKILLS+=(\n  alpha\n  # iface-guard(생성)와 size-warn(편집)이 함께 쓴다\n  beta\n)\n"
    assert doc_counts._bash_array(text, "SKILLS") == ["alpha", "beta"]


def test_한_줄_배열이_뒤_라인을_삼키지_않는다():
    """실측 2026-09-08: `['foo', 'bar']` 를 돌려주던 자리."""
    text = "SKILLS+=(one two three)\nfoo\nbar\n)\nbaz\n"
    assert doc_counts._bash_array(text, "SKILLS") == ["one", "two", "three"]


def test_닫히지_않은_배열은_예외():
    with pytest.raises(doc_counts.DocCountsUnavailable):
        doc_counts._bash_array("SKILLS+=(\n  alpha\n", "SKILLS")


def test_빈_배열은_0_이_아니라_예외():
    """0 을 사실로 보고하면 문서가 '0종' 이라고 말하고도 통과한다."""
    with pytest.raises(doc_counts.DocCountsUnavailable):
        doc_counts._bash_array("SKILLS+=(\n)\n", "SKILLS")


def test_없는_배열은_예외():
    with pytest.raises(doc_counts.DocCountsUnavailable):
        doc_counts._bash_array("OTHER+=(\n  alpha\n)\n", "SKILLS")


def test_실제_소스에서_산출한_수치가_모두_양수():
    """산출 근거가 사라지면 0 이 아니라 예외여야 한다는 계약의 반대편."""
    c = doc_counts.counts()
    for key in ("hooks", "modules", "gates", "gates_block", "gates_warn", "skills", "agents", "tests"):
        assert c[key] > 0, f"{key} 가 0 이다 — 소스를 못 읽고 있을 가능성"
    assert c["gates"] == c["gates_block"] + c["gates_warn"]


def test_render_가_마커_본문을_만든다():
    body = doc_counts.render()
    assert "실행 훅" in body and "게이트" in body
    assert doc_counts.BEGIN not in body, "본문에 마커가 섞이면 갱신이 중첩된다"


def test_배포_사본이_원본과_같다():
    """assets/hooks 와 scripts/hooks 의 사본이 갈라지면 설치본이 다른 코드를 쓴다.

    경로를 고정해 읽는 것만으로는 드리프트를 *막지* 못하고 숨기지만 않을 뿐이다.
    갈라졌는지 자체를 여기서 단언한다.
    """
    copy = Path(__file__).resolve().parent.parent / "scripts" / "hooks" / "doc_counts.py"
    if not copy.is_file():
        pytest.skip("scripts/hooks 사본이 없다 — 설치 전 상태")
    assert copy.read_text(encoding="utf-8") == _SRC.read_text(encoding="utf-8"), (
        "assets/hooks 와 scripts/hooks 의 doc_counts.py 가 다르다 — 재설치로 동기화할 것"
    )
