# update-all 왕복 시험이 실제 ~/.claude 에 전역 설치를 돌린다

> 작성일: 2026-10-06
> 목적: 공장 전체 시험을 돌려도 실제 전역 설정 폴더가 바뀌지 않게 한다.

## 개요

`tests/update-all-roundtrip-test.sh:22` 는 `export HOME="$TMP/fakehome"` 으로 실제 `~/.claude` 를 보호하려 한다.
그런데 `public-claude.sh:63` 은 홈 폴더를 `HOME` 이 아니라 `getent passwd` 에서 찾는다. 그래서 격리가 통하지 않는다.
`update-all.sh:218` 이 `public-claude.sh` 를 인자 없이 부르므로, `tests/run-all.sh` 를 돌릴 때마다 실제 `~/.claude` 에
전역 설치(에이전트·규칙·스킬, 그리고 `presets.global.lock` 에 적힌 선택 프리셋)가 한 번 실행된다.

## 근거 (2026-10-06 실측)

- `tests/run-all.sh` 가 16:09:08 에 끝났다.
- 실제 `~/.claude/.factory-manifest.json` 이 16:07:57 에 다시 쓰였다(항목 15개, 공장 커밋 `0807975`).
- 그 시각에 전역 설치를 부른 것은 이 시험뿐이다(`public-claude.sh`·`update-all.sh` 를 부르는 시험 4개 중 나머지는 격리하거나 실행하지 않는다).

## 영향

- 커밋하지 않은 `assets/` 수정이 시험만 돌려도 실제 전역 설정에 깔린다.
- 설치기가 "로컬에서 수정됨" 으로 보는 전역 파일은 시험 때마다 백업되고 덮인다.

## 고치는 길

- 시험이 `CLAUDE_CONFIG_DIR` 를 임시 폴더로 둔다. `detect_claude_config_dir` 가 이 값을 먼저 본다(`tests/mods-install-test.sh` 가 쓰는 방식).
- 시험 앞뒤로 실제 `~/.claude/.factory-manifest.json` 의 수정 시각이 같은지 단언한다. 고치기 전에는 이 단언이 실패해야 한다.

## 출처

`docs/exec-plans/completed/2026-10-06-mods-factory-install.md` §7 · §8.
