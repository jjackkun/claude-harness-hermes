# 현재 상태 실측 — 2026-09-15

> 작성일: 2026-09-15
> 목적: 설계 결정의 근거가 된 실측 사실을 확인 방법과 함께 남긴다.

## 개요

- 모든 수치는 2026-09-15 설계 논의 중 이 컴퓨터(WSL2, Python 3.10.12)에서 직접 실행해 얻었다.
- 비밀값이 출력되지 않도록 원문 DB는 행 수·분포만 조회했다.
- 시간이 지나면 값이 바뀐다. 구현 계획을 쓸 때 다시 측정한다.

## 1. 스킬 저장 위치 (claude-harness-hermes)

| 위치 | 개수 | 성격 |
|---|---|---|
| `assets/skills/` | 39 | 공장 원본 |
| `.claude/skills/` | 13 | 설치본 |
| `.hermes/skills/` | 16 | 결정화 |
| `~/.hermes/skills/` | 0 | — |
| `~/.hermes/mesh/skills/` | 0 | 전역 그물망(비어 있음) |

- `skill_index`: 칸은 `skill_path`(UNIQUE), `keywords`, `scope`, `version`, `used_count`, `helpful_count`, `noop_count`, `state`, `demoted_at` 등. **소우주 칸 없음.** 설치본은 `scope='harness'`, 결정화는 `scope='local'`.
- 확인: `python3 -c "import sqlite3; ..."`로 `sqlite_master`와 `skill_index` 조회.

## 2. zeroday-frontend 스킬

| 항목 | 값 |
|---|---|
| `.hermes/skills/` 파일 | 1088 |
| `.claude/skills/` 항목 | 50 (색인 `harness` 50) |
| 색인 `local` | 1088, 전부 `active` |
| 주입 0회 | 813 |
| 주입 1회 이상 | 275 |
| 도움 1회 이상 | 262 |
| 강등 | 0 |
| 상위 도움 스킬 | `jira-comment-approval-gate.md`(주입 26/도움 24), `jira-issue-context-first.md`(21/18), `aggregates-8-screen-sync.md`(18/18) |
| 파일 이름 예 | `active.md`, `agg_xxx.md`, `aftereach.md`, `added_lines.md` — 패턴 키 기반. 본문은 정상 규칙 |
| git 추적 `.hermes/` | `history` 235, `skills` 1088 |

## 3. 전역 DB `~/.hermes/global.db`

| 테이블 | 행 |
|---|---|
| `harness_rules` | **1142** (`scope` 전부 `local`) |
| 그 외(`session_history`, `skill_index`, `messages` 등) | 0 |

`harness_rules` 본문 접두어별 분포:

| 소우주 | 행 |
|---|---|
| zeroday-frontend | 940 (서로 다른 스킬 경로 934) |
| novel-bc | 105 |
| terminal-shipping | 80 |
| claude-harness-hermes | 16 |
| ai-create | 1 |

- 기간: 2026-06-16 ~ 2026-09-15.
- 쓰는 곳: `scripts/hermes-crystallize.py:369-387` (`record_global_summary`).
- **읽는 코드 없음:** `grep -rn harness_rules scripts assets/hooks` 결과는 init 정의와 crystallize INSERT뿐.

## 4. 프로젝트 id

| 위치 | 방식 |
|---|---|
| `scripts/hermes-save-session.py:57` | `args.project_id` 또는 `basename(dirname(db))` |
| `scripts/hermes-crystallize.py:393` | `basename(abspath(project_dir))` |
| `scripts/hermes-summarize.py:248` | `args.project_id` 또는 `basename(dirname(db))` |
| 실제 저장값(claude-harness-hermes) | `session_summary` 8행, `session_history` 208행 모두 `claude-harness-hermes` |

## 5. 설치 방식

| 항목 | 값 |
|---|---|
| 스킬·에이전트·규칙 설치 분기 | `lib/installers.sh:61-65, 86-90, 112-116` — Windows 경로면 복사, 아니면 `ln -s` |
| zeroday-frontend `.claude/skills` | 전체 50 = 링크 22 + 실제 폴더 28 (`find -mindepth 1 -maxdepth 1 -type l/-type d`) |
| zeroday-frontend `.claude/rules` | 링크 6 |
| zeroday-frontend `.claude/agents` | 링크 14 |
| zeroday-frontend `scripts/hooks` / `scripts` | 실파일 39 / 151 |
| zeroday-frontend git 추적 링크(모드 120000) | **41**, 무시 규칙 없음 |
| 링크 대상 예 | `/home/jjackkun/PROJECT/claude-harness-hermes/assets/rules/typescript` 등 절대경로 |
| `.claude/presets.lock` (zeroday-frontend) | `node python fastapi vue mysql harness hermes mcp skill-dev terminal-paste-image prettier adhd` — 공장 위치·버전 없음 |
| 공장 원격 | `git@github.com:jjackkun/claude-harness-hermes.git` |

## 6. 대화 원문

| 항목 | 값 |
|---|---|
| `.gitignore` (두 소우주 공통) | `.hermes/*` 무시, `!.hermes/skills/**`, `!.hermes/history/**` 예외 |
| 커밋된 원문 | zeroday-frontend `history` 235, terminal-shipping `history` 31 |
| terminal-shipping 추적 스킬 | 200 |
| export 호출 | `assets/hooks/claude-stop-retrospective.sh:121` |
| 재색인 훅 | `assets/hooks/claude-sessionstart-history-reindex.sh` |
| 자동 git add/commit | 없음 |
| Claude Code 자체 기록 | zeroday-frontend 3297개, terminal-shipping 1323개 (`~/.claude/projects/-home-jjackkun-PROJECT-<이름>/*.jsonl`) |
| `.hermes/vault/` | 세션 요약 평문 마크다운(`scripts/hermes-summarize.py:210`), 이 저장소에 8개 |
| 원문을 읽는 기능 | `hermes-lifecycle.py`, `hermes_lifecycle_apply.py`, `hermes_save_session_*`, `hermes-cleanup.py`, `hermes-crystallize.py`, `hermes-recall.py`, `hermes_reuse.py` — 모두 `state.db`의 `session_history` |

## 7. 암호화·마스킹

| 항목 | 값 |
|---|---|
| 프리셋 내 암호화 코드 | **0건** (`grep -rnwE "encrypt|decrypt|cryptography|Fernet|AESGCM|pyrage|gpg|openssl"`) |
| 마스킹 모듈 | `scripts/hermes_redact.py`(129줄, 값 기반 + 형태 기반), `scripts/hermes_secret_values.py`(143줄, `.env` 값 집합), `scripts/hermes-scrub-history.py`(143줄, 소급 제거) |
| 사고 설계 문서 | `docs/superpowers/specs/2026-08-10-hermes-secret-masking-design.md` |
| 설치 도구 | `age` CLI 없음, `pyrage` 없음 |

## 8. 원격과 사용자

| 소우주 | 원격 | 작성자(커밋 수) | 원격 브랜치 |
|---|---|---|---|
| terminal-shipping | `git@gitlab.com:jjackkun/terminal-shipping.git` | jjackkun 805 | 1 |
| zeroday-frontend | `http://211.206.116.39:3000/zeroday/zeroday-frontend.git` | jjackkun 1780, choijh15 53, ahnjunwoo 8, kimjk2 7 | 17 |

## 9. 기존 기록 테이블 (claude-harness-hermes)

| 테이블 | 칸 | 행 |
|---|---|---|
| `loops` | `id`, `title`, `goal_md_path`, `mode`, `branch`, `status`, `max_iterations` … | 0 |
| `loop_steps` | `loop_id`, `iteration`, `action_summary`, `verdict`, `objective_signal`, `progressed` | 0 |
| `loop_decisions` (`scripts/hermes_loop_decisions.py`, 미커밋) | `loop_id`, `iteration`, `kind`, `text` | — |
| `messages` | `from_agent`, `to_agent`, `content`, `status` | — |

## 10. 논의 중 관측한 문제

| 문제 | 내용 |
|---|---|
| 잘못된 결정화 | `.hermes/skills/repository-isolation-principle.md`가 회사 층 폐기를 "다층 체계 금지"로 일반화 |
| 모순되는 결정화 | `.hermes/skills/unified-hook-deployment.md` "훅도 symlink로 통일" ↔ 복사 설치 결정 |
| 로테이션 규칙 충돌 | `.hermes/skills/rotate-ephemeral-work-logs.md` "jsonl 로그는 로테이션" ↔ 작업 이력 보존 |
| 회상의 옛 결정 주입 | 헤르메스 회상이 "우편함 폴더 → git 커밋"(폐기)과 "GitHub 원격 배달"(확정)을 동시에 결정사항으로 주입 |
| 미커밋 공장 수정의 즉시 전파 | 세션 시작 시점 `assets/skills/hermes-loop/SKILL.md` 미커밋 수정이 symlink로 전 소우주에 반영된 상태 |
