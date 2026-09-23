# R-lock 승격 감사 — 2026-09-23

## 트리거

- 소스: [x] 반복 결함 (3건, 같은 계열)  [ ] 리뷰 지적  [ ] 시스템 신호  [x] 사용자 명령("박아")
- 참조: 사고 커밋 범위 `bbfc463`(사고 직전 커밋된 매니페스트) · 복구는 같은 세션 안에서 수행

## 무엇이 반복됐나

**로컬 전용 상태가 커밋된 산출물의 정본 노릇을 한다.** 2026-09-22~23 하루에 세 번 드러났다.

| 파일 | 상태 | 결과 | 이번 룰의 대상인가 |
| --- | --- | --- | --- |
| `.claude/presets.lock` | `.gitignore` | **커밋된 설치물 삭제** (심링크 2 · CLAUDE.md 2절) | **그렇다** |
| `.hermes/universe.id`·`agents.json` (ai-create) | 미커밋 | 컴퓨터마다 다른 신원 → `git pull` 거부 | 아니다 — 별건 백로그 |
| `.installed-projects` | `.gitignore` | 대시보드 "뒤처짐" 오보 | 아니다 — **기계의 속성이라 로컬이 맞다** |

셋을 한 룰로 묶지 않았다. 경계는 **"프로젝트의 속성인가, 기계의 속성인가"** 이고,
그 경계를 넘은 것은 `presets.lock` 하나다.

## 변경

- `docs/design-docs/core-beliefs.md` — R-lock 절 추가 (Provisional)
- `lib/harness_installers.sh` — 무시 목록에서 `.claude/presets.lock` 제거 + 사유 주석
- `lib/installers.sh` — `_cleanup_stale_assets` 가 `rm` 직전 추적 여부를 물어 `[preset-drop WARN]`;
  판정 헬퍼 `_is_tracked_asset` 신설
- `tests/preset-lock-tracked-test.sh` — 신규 14 단언, `tests/run-all.sh` 등록

## 왜 차단이 아니라 경고인가

프리셋을 빼는 것은 정당한 작업이고, `tests/copy-install-test.sh` 3절이 이미 그 동작을 단언한다.
차단하면 `--force` 류 우회 인자가 생기고 그것이 새 구멍이 된다. 사람이 **보게** 하는 데서 멈춘다.

## 회고

- 시험을 먼저 쓰면서 **내 단언이 헐거운 것**을 두 번 잡았다. ① "경고에 이름이 있다" 가 경고 없이도
  통과했다(로그의 `removed → mcp-builder` 에 걸림) → 경고 줄 안에서 찾도록 좁혔다.
  ② "미추적 제거는 조용하다" 가 빨갰는데 **제품이 옳고 시험 셋업이 틀렸다** — 앞 절의 삭제를
  커밋하지 않아 경로가 여전히 색인에 있었다. 제품을 고치지 않고 셋업을 고쳤다.
- 판정에 `git_ignore_judge`(무시되는가)를 쓰려다 멈췄다. 이 자리의 질문은 **추적되는가**이고
  그것은 `ls-files` 가 답한다. 도구가 있다고 끌어다 쓰면 질문이 뒤틀린다.
- 룰만 박고 강제 장치를 안 만들었다면 반년 뒤 같은 사고가 난다 — 오늘 그 사고가 이미
  "설계대로 동작한" 코드에서 났다는 점이 그 증거다.
