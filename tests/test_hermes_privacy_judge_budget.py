"""올리기 전 판정의 재시도 상한 — 호출이 계속 실패해도 몇 번 · 몇 초 안에 끝난다.

R-iface-waiver: 공개 심볼은 전부 pytest 수집 대상 테스트 함수다. 지는 책임은 하나 —
hermes_privacy_judge.judge_and_mark 의 재시도 상한 계약.

왜: 2026-11-20 drh-cloth-shop 에서 판정 대기 153문장(3묶음)을 내보내기가 두 번 연속 200초 넘게 붙잡았다.
실패한 묶음을 반으로 나눠 다시 묻는 구조라, 호출이 계속 실패하면 303번(한 번 60초 → 최악 303분)을 부른다(모델 0 으로 셈).
모델은 부르지 않는다 — _ask 를 바꿔 끼운다.
"""

import importlib.util
import sqlite3
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))
_spec = importlib.util.spec_from_file_location("_privacy_judge_under_test", SCRIPTS / "hermes_privacy_judge.py")
j = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = j
_spec.loader.exec_module(j)
from hermes_privacy_pending import ensure_table, status_of  # noqa: E402


@pytest.fixture
def con():
    c = sqlite3.connect(":memory:")
    ensure_table(c)
    return c


def items(n, size=60):
    """n 문장 — size 글자씩. 6000 자 묶음 상한으로 여러 묶음이 된다."""
    return [("summary", f"r{i}", f"{i:04d} " + "가" * size) for i in range(n)]


class FakeAsk:
    """매 호출의 답을 정한다. answer(texts) → (번호 집합 | None, 이유)."""

    def __init__(self, answer, clock=None, cost=0.0):
        self.answer, self.calls, self.clock, self.cost = answer, 0, clock, cost

    def __call__(self, texts):
        self.calls += 1
        if self.clock is not None:
            self.clock["now"] += self.cost
        return self.answer(texts)


def test_timeouts_do_not_split_and_stop_within_the_call_cap(con, monkeypatch):
    ask = FakeAsk(lambda texts: (None, "timeout"))
    monkeypatch.setattr(j, "_ask", ask)
    judged = j.judge_and_mark(con, items(153, size=75))   # drh 와 같은 규모: 3 묶음
    assert judged == 0
    assert ask.calls <= len(j._batches([(None, None, t) for _, _, t in items(153, size=75)]))
    assert ask.calls <= j._MAX_CALLS


def test_parse_failures_split_but_never_pass_the_call_cap(con, monkeypatch):
    ask = FakeAsk(lambda texts: (None, "parse"))
    monkeypatch.setattr(j, "_ask", ask)
    assert j.judge_and_mark(con, items(153, size=75)) == 0
    assert ask.calls == j._MAX_CALLS


def test_the_time_budget_stops_further_calls(con, monkeypatch):
    clock = {"now": 0.0}
    monkeypatch.setattr(j.time, "monotonic", lambda: clock["now"])
    ask = FakeAsk(lambda texts: (None, "exit"), clock=clock, cost=j._MAX_SECONDS / 2 + 1)
    monkeypatch.setattr(j, "_ask", ask)
    j.judge_and_mark(con, items(153, size=75))
    assert ask.calls == 2   # 두 번째 호출이 끝난 뒤 예산을 넘겼다 — 세 번째는 부르지 않는다


def test_success_judges_everything_one_call_per_batch(con, monkeypatch):
    ask = FakeAsk(lambda texts: ({0}, "ok"))
    monkeypatch.setattr(j, "_ask", ask)
    given = items(153, size=75)
    assert j.judge_and_mark(con, given) == 153
    assert ask.calls == 3
    assert status_of(con, given[0][2]) == "pending" and status_of(con, given[1][2]) == "clean"


def test_a_parse_failure_still_splits_and_recovers(con, monkeypatch):
    """옛 동작(반으로 나눠 다시)은 형식 오류에 한해 남는다 — 115문장이 통째로 대기로 쌓인 2026-09-28 사례."""
    answers = iter([(None, "parse"), (set(), "ok"), (set(), "ok")])
    monkeypatch.setattr(j, "_ask", FakeAsk(lambda texts: next(answers)))
    assert j.judge_and_mark(con, items(4)) == 4


def test_the_reasons_are_reported(con, monkeypatch, capsys):
    monkeypatch.setattr(j, "_ask", FakeAsk(lambda texts: (None, "timeout")))
    j.judge_and_mark(con, items(10))
    err = capsys.readouterr().err
    assert "timeout" in err and "남김 10" in err
