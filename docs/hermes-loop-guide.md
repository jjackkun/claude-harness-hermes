# 헤르메스 목표 기반 자율 루프 — 사용 가이드

> 작성일: 2026-07-03
> 목적: 목표만 주면 완료(또는 안전캡)까지 스스로 반복하는 자율 루프의 설치·실행·모니터링 방법 안내
> 설계 문서: `docs/superpowers/specs/2026-07-02-hermes-loop-design.md`
> 선행 조건: `hermes` 프리셋 설치, `claude` CLI, `python3`

## 개요

```
목표 입력 (init)
    ↓  GOAL.md 생성 + loops 행 INSERT
드라이버 while-루프 (hermes-loop.py run)
    ↓  매 반복: 프롬프트 조립 → claude -p (동기) → REPORT 파싱
    ↓          → VERIFY 명령 실행(교차검증) → 진전 판정 → 기록
    ↓  goal-met(검증 통과) / blocked / 안전캡 → 종료
messages 아카이브 (from=loop, to=archive)
```

- **진실원본**: `.hermes/loops/<loop-id>/GOAL.md` — 사람이 언제든 열어 완료조건을
  수정하거나 진행을 확인할 수 있다.
- **메타·이력**: `.hermes/state.db` 의 `loops` / `loop_steps` 테이블.

## 빠른 시작 (헤드리스 — 무인 실행)

```bash
# 목표 하나로 시작 (완료 조건은 에이전트가 첫 반복에서 작성)
scripts/hermes-loop-run.sh /path/to/project "테스트 커버리지 80% 달성"

# 완료 조건·검증 명령을 직접 지정
scripts/hermes-loop-run.sh /path/to/project "로그인 버그 수정" \
  --condition "pytest tests/test_auth.py 전체 통과" \
  --condition "회귀 테스트 추가" \
  --verify "pytest -q"
```

출력의 `id=loop-...` 가 루프 ID다. 이후 터미널을 닫아도 된다 (nohup).

## 대화형 (현재 세션)

Claude Code 세션에서:

```
/hermes-loop 테스트 커버리지 80% 달성
```

세션이 직접 반복을 구동하며, 파괴적 작업은 표준 권한 프롬프트로 승인을 받는다.

## 모니터링

```bash
# 전체 루프 목록 / 특정 루프 상세 (반복별 verdict·신호)
python3 scripts/hermes-loop.py --project-dir /path/to/project status
python3 scripts/hermes-loop.py --project-dir /path/to/project status <loop-id>

# 사람이 읽는 진실원본
cat /path/to/project/.hermes/loops/<loop-id>/GOAL.md

# 드라이버 로그 실시간 확인
tail -f /path/to/project/.hermes/logs/loop-<loop-id>.log

# 완료 아카이브 확인
python3 scripts/hermes-message.py --db /path/to/project/.hermes/state.db list
```

## 중단·재개

```bash
# 사용자 강제 중단 (finish_reason=user-stop)
python3 scripts/hermes-loop.py --project-dir /path/to/project stop <loop-id>

# 재개 — 프로세스가 죽었거나 재부팅한 뒤 이어서 실행 (cold start 구조라 안전)
scripts/hermes-loop-run.sh /path/to/project --resume <loop-id>
```

## 루프 브랜치와 머지 (G14)

루프는 시작 시 대상 프로젝트에 `loop/<loop-id>` 브랜치를 만들어 체크아웃하고,
에이전트의 모든 커밋을 그 브랜치에 격리한다. **머지·push 는 절대 자동으로
하지 않는다** — 루프가 끝나면 사용자가 결과를 검토하고 직접 반영한다:

```bash
# 루프가 무엇을 했는지 검토
git -C /path/to/project log --oneline main..loop/<loop-id>
git -C /path/to/project diff main...loop/<loop-id>

# 마음에 들면 수동 머지
git -C /path/to/project checkout main
git -C /path/to/project merge loop/<loop-id>

# 마음에 안 들면 브랜치만 버리면 끝 — main 은 무결
git -C /path/to/project branch -D loop/<loop-id>
```

> **주의**: 브랜치 체크아웃은 작업 트리 전체에 적용된다.
> **루프 실행 중에는 같은 저장소에서 직접 작업하지 말 것** —
> 루프가 도는 동안 그 프로젝트는 루프에게 맡긴다.

## 무인 실행 전원 설정 (Windows + WSL2 — 클램쉘 포함)

루프는 로컬 프로세스다. **머신이 절전에 들어가면 루프도 멈춘다.**
노트북 덮개를 닫아둔 채(클램쉘) 돌리려면 아래 세 가지를 확인한다:

| # | 설정 | 값 |
|---|------|----|
| 1 | 설정 → 시스템 → 전원 및 배터리 → **덮개를 닫으면** | **아무 것도 하지 않음** |
| 2 | 설정 → 시스템 → 전원 및 배터리 → 화면, 절전 모드 시간 제한 → **절전 모드로 전환** | **안 함** (전원 연결 시) |
| 3 | **전원 어댑터 연결** | 필수 (배터리 절전 정책 회피) |

- 화면 끄기 타이머는 켜둬도 된다 — 화면 꺼짐과 시스템 절전은 별개다.
- WSL2 의 유휴 자동 종료는 내부에 실행 중인 프로세스가 없을 때만 발동한다 —
  루프 드라이버가 도는 동안은 WSL 이 유지된다.
- 절전·재부팅으로 중단됐다면 상태가 GOAL.md + DB 에 남아 있으므로
  `--resume` 으로 중단 지점부터 이어간다.

## 안전장치

| 장치 | 동작 |
|------|------|
| 최대 반복 (`max_iterations`) | 기본 `max(완료조건 수 × 3, 5)` — 초과 시 finish_reason=max-iter 로 중단 |
| 무진전 한도 (`no_progress_limit`) | 3회 연속 진전 없음 → no-progress 로 중단, 사람에게 이관 |
| blocked 판정 | 에이전트가 사람 개입 필요 선언 → 즉시 중단 |
| 교차검증 | goal-met 이라도 VERIFY 명령 실패 시 continue 로 강등 |
| 루프 브랜치 격리 (G14) | 커밋은 `loop/<loop-id>` 브랜치에만 — main 무결, 머지는 사용자 수동 |
| 파괴적 작업 차단 | 프롬프트 금지 명문화 + harness `bash-guard` 훅 + VERIFY 명령 파괴 패턴 정규식 차단. `--dangerously-skip-permissions` 미사용 |
| 마스킹 | 진행로그·DB 저장 경계에서 `hermes_redact` 적용 |

> **verify 명령에 비밀을 직접 넣지 말 것** — verify 문자열은 드라이버가
> 재실행해야 하므로 마스킹되지 않는다. 토큰 등은 환경변수로 전달한다.

## 한계

1. **반복당 cold start**: 매 반복이 독립 `claude -p` 세션 — 이전 반복의 대화
   맥락은 GOAL.md 진행 로그(최근 5개)로만 전달된다.
2. **한 번에 루프 1개**: v1 은 멀티 루프 큐/스케줄러 없음 (후속 과제).
3. **claude CLI 필요**: PATH 에서 실행 가능해야 한다.
4. **행(hang) 방지**: 반복당 제한이 필요하면 `run --iter-timeout <초>` 사용.

## 활성화 체크리스트

- [ ] `claude --version` 확인
- [ ] `python3 scripts/hermes-init.py --both <project>` 실행 (loops 테이블 마이그레이션)
- [ ] 전원 설정 3항목 확인 (무인 실행 시)
- [ ] 루프 실행 중 같은 저장소에서 직접 작업하지 않기로 인지 (브랜치 체크아웃 공유)
- [ ] `hermes-loop-run.sh <project> "<간단한 목표>"` 로 즉시 테스트
- [ ] `hermes-loop.py status` 로 진행 확인
- [ ] 종료 후 `git log main..loop/<id>` 로 결과 검토 → 수동 머지 또는 브랜치 폐기
