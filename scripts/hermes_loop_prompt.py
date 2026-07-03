#!/usr/bin/env python3
"""헤르메스 루프 — 반복 프롬프트 템플릿 + REPORT 계약 파서.

프롬프트 지시와 파서가 같은 REPORT 필드(ACTION/VERDICT/VERIFY/NEXT)를 쓰는
하나의 계약이므로 한 파일에 함께 둔다 (hermes-manager.py 템플릿 상수 방식 계승).
"""

import re

from hermes_loop import RECENT_LOG_COUNT, VERDICTS

ITER_TEMPLATE = """\
# 헤르메스 루프 에이전트 — 반복 {iteration}/{max_iterations}

프로젝트 디렉토리: {project_dir}
GOAL.md 경로: {goal_md_path}
루프 브랜치: {branch_label}

## 목표
{goal}

## 완료 조건 (Definition of Done)
{conditions}

## 최근 진행 로그 (최신 {recent_count}개)
{recent_log}

## 직전 객관 신호
{last_signal}

## 이번 반복에서 할 일

1. 완료 조건이 비어 있으면 GOAL.md 의 '## 완료 조건' 섹션에 검증 가능한
   체크박스(`- [ ] ...`)를 먼저 작성한다.
2. 아직 미완료인 조건 하나를 골라 작업한다.
3. 작업 결과를 스스로 검증한다 (테스트/빌드/실행).
4. 조건을 달성했으면 GOAL.md 의 해당 체크박스를 `- [x]` 로 갱신한다.

## 금지 사항 (반드시 준수)

- 파괴적 작업 절대 금지: 파일/디렉토리 삭제, git push --force,
  git reset --hard, 배포, 외부 API 쓰기, DB drop.
- git 커밋은 루프 브랜치({branch_label}) 안에서만 허용한다.
- 브랜치 전환, main 직접 커밋, 머지, git push 절대 금지 —
  머지는 종료 후 사용자가 검토하고 직접 수행한다.
- GOAL.md 의 '## 진행 로그' 섹션은 드라이버가 기록한다 — 직접 수정 금지.

## 보고 계약 (응답 맨 마지막에 아래 블록을 반드시 출력)

=== HERMES-LOOP REPORT ===
ACTION: <이번 반복에서 한 일 한 줄 요약>
VERDICT: <continue | goal-met | blocked 중 하나>
VERIFY: <드라이버가 실행할 검증 셸 명령 1줄, 없으면 none>
NEXT: <다음 반복 제안 한 줄>
=== END REPORT ===

- VERDICT 기준: 모든 완료 조건 충족 → goal-met / 사람 개입 필요 → blocked /
  그 외 → continue.
- goal-met 이라도 VERIFY 명령이 실패하면 드라이버가 continue 로 강등한다.
"""


def _format_conditions(conditions):
    if not conditions:
        return "(아직 없음 — 이번 반복에서 먼저 작성할 것)"
    return "\n".join(f"- [{'x' if done else ' '}] {text}"
                     for done, text in conditions)


def build_iteration_prompt(project_dir, goal_md_path, goal, conditions,
                           log_lines, last_signal, iteration, max_iterations,
                           branch_label):
    recent = "\n".join(log_lines[-RECENT_LOG_COUNT:]) or "(없음)"
    return ITER_TEMPLATE.format(
        iteration=iteration, max_iterations=max_iterations,
        project_dir=project_dir, goal_md_path=goal_md_path, goal=goal,
        conditions=_format_conditions(conditions),
        recent_count=RECENT_LOG_COUNT, recent_log=recent,
        last_signal=last_signal, branch_label=branch_label)


# ── REPORT 파서 (드라이버 측) ────────────────────────────────────────────────

_REPORT_RE = re.compile(
    r"=== HERMES-LOOP REPORT ===\s*(.*?)\s*=== END REPORT ===", re.S)
_FIELD_RE = re.compile(r"^(ACTION|VERDICT|VERIFY|NEXT):\s*(.*)$", re.M)


def parse_report(text):
    """응답에서 마지막 REPORT 블록을 파싱 — 블록 부재/verdict 불량이면 None."""
    blocks = _REPORT_RE.findall(text or "")
    if not blocks:
        return None
    fields = {k.lower(): v.strip() for k, v in _FIELD_RE.findall(blocks[-1])}
    verdict = fields.get("verdict", "")
    if verdict not in VERDICTS:
        return None
    return {"action": fields.get("action", ""), "verdict": verdict,
            "verify": fields.get("verify", "none") or "none",
            "next": fields.get("next", "")}
