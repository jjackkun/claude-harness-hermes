"""스킬 파일을 쓰는 유일한 길 — 지금 마스킹 규칙으로 가린 뒤 원자적으로 쓴다.

스킬은 사람의 대화에서 굳은 것이라 비밀·개인정보가 섞일 수 있다. 결정화·진화가 모델의 출력을 그대로 쓰던 자리를
이 함수로 바꿔, 파일에 쓰이는 본문은 언제나 가려진 값이 되게 한다(멱등 — 이미 가린 본문은 그대로).
같은 규칙으로 R-privacy 게이트가 다시 검사한다.
계획: docs/exec-plans/completed/2026-09-29-privacy-gate-hardening.md 목표 8

공개: write_skill_file
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_privacy_pending import scrub  # noqa: E402


def write_skill_file(path: str, content: str, project=None) -> str:
    """가린 본문을 임시 파일에 쓰고 바꿔 넣는다. 쓴(가린) 본문을 돌려준다."""
    text = scrub(content, project)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(path + ".tmp", path)
    return text
