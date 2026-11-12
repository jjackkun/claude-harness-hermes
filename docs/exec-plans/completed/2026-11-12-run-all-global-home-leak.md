# run-all 병렬 실행 중 실제 ~/.claude 에 전역 설치가 새어 나간다

> 작성일: 2026-11-02
> 출처: `docs/exec-plans/completed/2026-11-02-new-pc-restore-plan.md` §7 — run-all 151개 실행 중 발견

## 관측

- 2026-11-02 14:17:54 run-all 도중 실제 `~/.claude` 에 `.factory-manifest.json` · `CLAUDE.md` · `agents/` 9개 · `keybindings.json` 이 생겼다(factory_commit `81e705a`).
- `tests/update-all-roundtrip-test.sh:281` 의 "실제 ~/.claude 의 설치 목록을 건드리지 않음" 단언이 잡았다(전: none).
- 같은 시험을 따로 돌리면 실제 파일을 건드리지 않는다. 범인은 병렬로 함께 돈 다른 시험이거나 다른 프로세스다 — 찾지 못했다.

- 2026-11-12 **두 번째 재현.** run-all(152개, 10:11 끝) 도중 10:08:36~37 에 실제 `~/.claude/.factory-manifest.json` · `agents/` 가 다시 쓰였다(factory_commit `8175454` — run-all 을 돌린 작업 트리의 HEAD).
  같은 단언(`update-all-roundtrip-test.sh` 10절)이 잡았다(expected=1793596675 actual=1794445717). 따로 돌리면 35/35 통과(10:11 실측). 재현이 두 번이므로 우연이 아니다.
  - 이번 설치물은 그 시점 main 과 같은 커밋이라 내용 손해는 확인되지 않았다. 지우지 않았다.

## 할 일

- 전역 설치를 부르는 시험(`setup.sh` · 전역 설치 함수)을 모아, `export HOME=` 이 설치 호출보다 **앞**에 있는지 본다.
- run-all 에 "실행 전후 실제 `~/.claude` 의 mtime 이 같다" 를 러너 단위로 재는 단언을 더해, 어느 묶음에서 새는지 좁힌다.
- 이 PC 의 실제 `~/.claude` 에 생긴 파일을 둘지 지울지는 사용자가 정한다.

## 해결 (2026-11-12)

- **원인:** `tests/harness-doctor-test.sh` 4절이 `HOME` 만 가짜로 바꾼 채 `update-all.sh` 를 불렀다. `update-all.sh:218` → `public-claude.sh` 는 홈을 `$HOME` 이 아니라 `getent passwd`(`public-claude.sh:63`)로 찾는다. 그래서 실제 `~/.claude` 에 전역 설치가 들어갔다. 2026-10-06 `update-all-roundtrip-test.sh` 가 같은 길로 샌 것과 같은 원인이다(`11b1f18`).
- **실측:** `getent` 를 가짜로 바꿔 끼우고 이 시험만 돌렸다. 호출 1회가 `public-claude.sh` 에서 나왔다. 가짜 홈에 생긴 묶음(`.factory-manifest.json` 3996 B · `CLAUDE.md` 1497 B · `agents/` · `keybindings.json` · `rules/` · `skills/`)이 두 번의 누수와 같다. 실제 홈 mtime 은 바뀌지 않았다.
- **고침:** 이 시험이 `CLAUDE_CONFIG_DIR="$HOME/.claude"` 를 고정한다. "실제 ~/.claude 의 설치 목록을 건드리지 않음" · "전역 설치는 가짜 홈으로 갔다" 단언 2개를 더했다. 고친 시험 37/37, 고친 줄을 뺀 사본은 새 단언 2개가 빨갛다.
- **다른 호출자:** `update-all.sh`·`setup.sh`·`public-claude.sh` 를 실제로 실행하는 시험은 이 시험과 `mods-install-test.sh` 둘이다. `mods-install-test.sh` 는 이미 `CLAUDE_CONFIG_DIR` 을 준다.
- **하지 않은 것:** run-all 러너 단위의 mtime 단언은 더하지 않았다 — `update-all-roundtrip-test.sh` 10절이 이미 두 번 잡았다. 실제 `~/.claude` 에 생긴 파일(2026-11-02 의 `CLAUDE.md` 스텁 포함)은 지우지 않았다 — 사용자 판단.
- **룰 후보:** "전역 설치를 부르는 시험은 `HOME` 이 아니라 `CLAUDE_CONFIG_DIR` 을 바꾼다" 가 두 번(10-06 · 11-12) 나왔다. 세 번째가 나오면 R 룰로 올린다.
