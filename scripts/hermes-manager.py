#!/usr/bin/env python3
"""헤르메스 매니저 에이전트 프롬프트 조립.

cron 이 hermes-cron-run.sh 래퍼를 통해 호출한다 (H1/H2).
claude CLI 에는 --bg 플래그가 없으므로 비대화형 실행은
`nohup claude -p "<프롬프트>" >> 로그 2>&1 &` 패턴을 사용한다.
매니저는 서브에이전트들을 배분하고 messages 테이블로 결과를 수집한다.

사용법:
  # 업무 시작 (오전 cron)
  python3 hermes-manager.py --db PATH --action start --projects proj1,proj2

  # 점심 체크인 (선택, 낮 cron)
  python3 hermes-manager.py --db PATH --action check

  # 업무 종료 (오후 cron)
  python3 hermes-manager.py --db PATH --action end

  # 출력 파일로 저장 후 claude -p 백그라운드 실행에 전달
  python3 hermes-manager.py --db PATH --action start --output /tmp/manager.txt
  nohup claude -p "$(cat /tmp/manager.txt)" >> /tmp/hermes-manager.log 2>&1 &

  # 권장: cron 래퍼 사용 (위 과정을 한 줄로)
  scripts/hermes-cron-run.sh <project-dir> start proj1,proj2
"""

import argparse
import os
import sqlite3
import sys
from datetime import datetime


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


START_TEMPLATE = """\
# 헤르메스 매니저 에이전트 — 업무 시작

실행 시각: {timestamp}
DB 경로: {db_path}
프로젝트 목록: {projects}

## 역할

당신은 헤르메스 매니저 에이전트다.
각 프로젝트에 서브에이전트를 배분하고, 결과를 수집해 정리한다.
업무 시작 시 각 프로젝트의 진행 상황을 파악한 뒤 오늘 할 작업을 배분한다.

## 미읽은 메시지 (이전 에이전트 결과)
{unread_section}

## 작업 순서

### 1단계 — 각 프로젝트 상황 파악 (배분 전)

각 프로젝트 디렉토리에서 다음을 읽는다:
- `docs/exec-plans/active/` — 진행 중인 작업 계획
- `git status` — 미커밋 변경사항

### 2단계 — 서브에이전트 배분

각 프로젝트별로 `claude -p` 를 nohup 백그라운드로 호출한다
(claude CLI 에 --bg 플래그는 없다).
서브에이전트 프롬프트는 반드시 아래 보고 프로토콜을 포함해야 한다:

```bash
nohup claude -p "프로젝트 디렉토리: {proj_dir}/<PROJECT>

작업:
1. docs/exec-plans/active/ 에서 오늘 처리할 항목 1~2개 선택
2. 선택한 항목 처리 (파괴적 작업 금지)
3. 완료 후 반드시 아래 명령으로 결과 보고:

python3 {scripts_dir}/hermes-message.py \\
  --db {db_path} send \\
  --from <PROJECT> \\
  --to manager \\
  --content 'STATUS:done TASK:<처리한 작업 한 줄> NOTE:<특이사항 또는 없음>'

작업 중 블로커 발생 시:
python3 {scripts_dir}/hermes-message.py \\
  --db {db_path} send \\
  --from <PROJECT> \\
  --to manager \\
  --content 'STATUS:blocked TASK:<작업명> NOTE:<블로커 이유>'" \\
  >> /tmp/hermes-subagent-<PROJECT>.log 2>&1 &
```

### 3단계 — 배분 목록 (각각 위 패턴으로 실행)
{project_list}

### 4단계 — 시작 기록

```bash
python3 {scripts_dir}/hermes-message.py \\
  --db {db_path} send \\
  --from manager --to manager \\
  --content 'STATUS:started PROJECTS:{project_count} TIME:{timestamp}'
```

## 주의사항

- 서브에이전트는 `nohup claude -p ... &` 로 독립 실행 (현재 세션과 별개, 직접 통신 불가).
- 결과는 messages 테이블을 통해 비동기 수집 — 즉시 확인 불가.
- 파괴적 작업(파일 삭제, force push, DB drop)은 절대 자동 실행하지 않는다.
- exec-plan 이 없는 프로젝트는 배분을 건너뛴다.
"""


CHECK_TEMPLATE = """\
# 헤르메스 매니저 에이전트 — 점심 체크인

실행 시각: {timestamp}
DB 경로: {db_path}

## 역할

오전에 배분한 서브에이전트 결과를 중간 점검한다.
완료된 것은 수신 처리, 블로커는 확인 후 필요 시 재배분한다.

## 오전 이후 수신된 메시지
{unread_section}

## 작업 순서

1. **메시지 수신 처리**
   ```bash
   python3 {scripts_dir}/hermes-message.py \\
     --db {db_path} recv --to manager
   ```

2. **진행 상황 분류**
   - `STATUS:done` → 완료 목록에 기록
   - `STATUS:blocked` → 블로커 내용 확인, 필요 시 재배분
   - 메시지 없음 → 아직 진행 중 (정상)

3. **블로커가 있을 경우** — 해당 프로젝트에 재배분:
   ```bash
   nohup claude -p "프로젝트 <PROJECT> 에서 <블로커 내용> 해결 후
   python3 {scripts_dir}/hermes-message.py \\
     --db {db_path} send \\
     --from <PROJECT> --to manager \\
     --content 'STATUS:done TASK:<작업명> NOTE:재배분 후 완료'" \\
     >> /tmp/hermes-subagent-<PROJECT>.log 2>&1 &
   ```

4. **체크인 기록**
   ```bash
   python3 {scripts_dir}/hermes-message.py \\
     --db {db_path} send \\
     --from manager --to manager \\
     --content 'STATUS:checked TIME:{timestamp} DONE:<N>건 BLOCKED:<M>건'
   ```

## 주의사항

- 체크인은 선택 사항 — 오전 배분이 충분하면 생략 가능.
- 파괴적 작업은 절대 자동 실행하지 않는다.
"""

END_TEMPLATE = """\
# 헤르메스 매니저 에이전트 — 업무 종료

실행 시각: {timestamp}
DB 경로: {db_path}

## 역할

오늘 하루 작업을 아카이브하고 내일을 준비한다.

## 오늘 수신된 메시지 (서브에이전트 결과)
{unread_section}

## 작업 순서

1. **메시지 전체 수신**
   ```bash
   python3 {scripts_dir}/hermes-message.py \\
     --db {db_path} recv --to manager
   ```

2. **결과 분류 및 요약 작성**
   - `STATUS:done` 항목 → 완료 목록
   - `STATUS:blocked` 항목 → 미완료 목록 (내일 이월)
   - 메시지 없는 프로젝트 → 응답 없음으로 기록

3. **일일 아카이브 저장**
   ```bash
   python3 {scripts_dir}/hermes-message.py \\
     --db {db_path} send \\
     --from manager --to archive \\
     --content '일일요약 {date} DONE:<완료목록> CARRY:<이월목록>'
   ```

4. **내일 이월 항목 메모** (미완료 있을 때만)
   ```bash
   python3 {scripts_dir}/hermes-message.py \\
     --db {db_path} send \\
     --from manager --to manager \\
     --content '이월 {date}: <미완료 항목 목록>'
   ```

## 주의사항

- 파괴적 작업(파일 삭제, force push 등)은 절대 자동 실행하지 않는다.
- 요약은 간결하게 (불필요한 설명 금지).
- 이월 항목은 내일 START 시 unread 메시지로 자동 반영된다.
"""


def get_unread_messages(db_path, to_agent="manager"):
    try:
        con = connect_db(db_path)
        rows = con.execute(
            "SELECT id, from_agent, content, created_at FROM messages "
            "WHERE to_agent=? AND status='unread' ORDER BY id ASC",
            (to_agent,),
        ).fetchall()
        con.close()
        return rows
    except Exception as e:
        print(f"[hermes-manager] 메시지 조회 실패: {e}", file=sys.stderr)
        return []


def format_unread(rows):
    if not rows:
        return "  (없음)"
    lines = []
    for row in rows:
        msg_id, from_a, content, created_at = row
        snippet = content[:120].replace("\n", " ")
        lines.append(f"  #{msg_id} [{from_a}] {created_at[:16]}  {snippet}")
    return "\n".join(lines)


def build_start_prompt(db_path, projects, scripts_dir):
    unread = get_unread_messages(db_path)
    proj_dir = os.path.dirname(os.path.dirname(db_path))
    project_list = "\n".join(f"   - `{p.strip()}`" for p in projects)

    return START_TEMPLATE.format(
        timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        db_path=db_path,
        projects=", ".join(p.strip() for p in projects),
        unread_section=format_unread(unread),
        proj_dir=proj_dir,
        scripts_dir=scripts_dir,
        project_list=project_list,
        project_count=len(projects),
    )


def build_check_prompt(db_path, scripts_dir):
    unread = get_unread_messages(db_path)

    return CHECK_TEMPLATE.format(
        timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        db_path=db_path,
        scripts_dir=scripts_dir,
        unread_section=format_unread(unread),
    )


def build_end_prompt(db_path, scripts_dir):
    unread = get_unread_messages(db_path)

    return END_TEMPLATE.format(
        timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        db_path=db_path,
        scripts_dir=scripts_dir,
        unread_section=format_unread(unread),
        date=datetime.now().strftime("%Y-%m-%d"),
    )


def main():
    parser = argparse.ArgumentParser(description="헤르메스 매니저 에이전트 프롬프트 조립")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--action", choices=["start", "check", "end"], required=True,
                        help="start: 업무 시작 / check: 점심 체크인 / end: 업무 종료")
    parser.add_argument("--projects", default="",
                        help="프로젝트 목록 (콤마 구분, start 시 사용)")
    parser.add_argument("--output", default="",
                        help="출력 파일 경로 (없으면 stdout)")
    args = parser.parse_args()

    if not os.path.isfile(args.db):
        print(f"[hermes-manager] DB not found: {args.db}", file=sys.stderr)
        sys.exit(1)

    scripts_dir = os.path.dirname(os.path.abspath(__file__))

    if args.action == "start":
        projects = [p for p in args.projects.split(",") if p.strip()]
        if not projects:
            print("[hermes-manager] --projects 가 비어 있습니다.", file=sys.stderr)
            sys.exit(1)
        prompt = build_start_prompt(args.db, projects, scripts_dir)
    elif args.action == "check":
        prompt = build_check_prompt(args.db, scripts_dir)
    else:
        prompt = build_end_prompt(args.db, scripts_dir)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(prompt)
        print(f"[hermes-manager] prompt saved: {args.output}")
    else:
        print(prompt)


if __name__ == "__main__":
    main()
