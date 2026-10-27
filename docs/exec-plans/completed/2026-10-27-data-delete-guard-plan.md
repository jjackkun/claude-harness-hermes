# 2026-10-27-data-delete-guard — 데이터를 지우는 명령은 사람 승인 뒤에만 (R-del)

> 작성일: 2026-10-27
> 목적: 에이전트가 작업이 만든 데이터(DB 줄·결과 파일)를 묻지 않고 지우지 못하게, 규칙 문장과 PreToolUse 훅으로 멈춰 세운다.

## 1. 동기 (Why)

- 2026-10-27 jj-agent-room 번역 M7 실측 뒤, 에이전트가 개발 DB 의 번역 건 7개 · 문장 512줄 · 번역 기록 252줄과 결과 파일을 **묻지 않고** 지웠다(`psql … DELETE FROM …` · `rm -rf …`). 개발 DB 는 백업·WAL 보관이 없어 되살릴 수 없었다. 사용자: "번역한걸 다 지웠다고?"
- 규칙이 없어서가 아니다 — 전역 규칙과 `decision-ledger.md` §1-1 에 "되돌릴 수 없거나 파괴적인 일(삭제…)은 멈추고 묻는다" 가 이미 있었다. 에이전트가 계획서의 "실측 뒤 지운다"(운영 PC 에서 옮긴 **파일 사본** 얘기)를 DB 결과까지 넓혀 읽고 스스로 승인으로 삼았다. 문장만 더하면 같은 해석 실수가 되풀이된다 → 기계가 멈춰 세운다.
- 사용자: 프로젝트 기억에만 적으면 "다른 프로젝트에서 또 동일한 오류를 범할거아냐" — 공장에서 고친다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 DB 삭제 — DB 접속 도구(`psql`·`mysql`·`mariadb`·`sqlite3`·`sqlcmd`·`mongosh`·`clickhouse-client`)가 명령에 있고 `DELETE FROM`·`TRUNCATE`·`DROP TABLE|DATABASE|SCHEMA|VIEW|INDEX|MATERIALIZED VIEW`·`deleteMany`/`drop()` 가 있으면 ask. `-f 파일` 로 넘긴 SQL 도 읽어 본다. `redis-cli` 의 `FLUSHALL`·`FLUSHDB`·`DEL`·`UNLINK` 도 ask. 이름만 다루는 명령(`grep "DELETE FROM" src/`)은 통과.
      `bash tests/data-guard-test.sh`
- [x] G2 파일 삭제 — `rm -r`(-rf · -fr · -R · --recursive)·`find … -delete`·`find … -exec rm`·`git clean -f…` 가 임시 자리(`/tmp`·`/var/tmp`·`.claude/jobs/…/tmp`·`.harness/out`·`node_modules`·`dist`·`build`·`__pycache__`·`.cache`·`coverage` 등) 밖을 지우면 ask. 변수가 든 대상(`$X/…`)도 임시 자리 이름이 없으면 ask.
      `bash tests/data-guard-test.sh`
- [x] G3 사유 — ask 의 사유 문구가 "무엇을 몇 줄·몇 개 지우는지 · 되살릴 수 있는지(백업)를 사용자에게 보이고 승인을 받으라 · 문서의 '지운다' 는 승인이 아니다" 를 담는다. 끄기 `.harnessrc` `HARNESS_DATA_GUARD=off`. 판정 결과는 `gate_event`(R-del).
      `bash tests/data-guard-test.sh`
- [x] G4 규칙 문장 — `assets/rules/harness/decision-ledger.md` §1 1번에 "작업이 만든 데이터(DB 줄·결과 파일)도, 개발 DB 여도. 계획서·문서의 '지운다' 는 승인이 아니다" 를 더한다.
- [x] G5 전파 — harness 프리셋이 훅·모듈을 복사하고 Bash PreToolUse 로 등록. jj-agent-room 에만 설치(사용자 지시), 설치 뒤 그 프로젝트에서 실제 훅이 `psql … -c "DELETE FROM x"` 에 ask 를 내는지 확인.
      `bash tests/run-all.sh` + jj-agent-room 에서 훅 직접 호출

## 3. 비목표

- `rm` 단일 파일(비재귀) — 소음이 커서(편집 중 임시 파일) 보지 않는다.
- 래퍼 스크립트 안의 삭제(`node purge.js`)·ORM 코드 — 글자로 안 보인다. 규칙 문장(G4)이 맡는다.
- 다른 프로젝트 전파(`update-all`) — 사용자가 jj-agent-room 에만 하라고 함.

## 4. 영향 영역

- `assets/hooks/data_delete.py` — 순수: 명령 문자열 → 사유 문자열 또는 None (DB 삭제 · 재귀 파일 삭제 판정)
- `assets/hooks/claude-pretooluse-data-guard.sh` — 진입 훅: 끄기 확인 · 값싼 글자 거르기 · 모듈 호출 · ask 출력 · gate_event
- `tests/data-guard-test.sh` — G1~G3 단언
- 고치는 파일: `presets/workflow/harness.conf`(복사·등록) · `tests/run-all.sh`(시험 목록) · `assets/rules/harness/decision-ledger.md`(G4) · `CLAUDE.md`·`README.md` 의 훅·모듈 개수

## 5. 단계

1. 시험 먼저(RED) → 모듈·훅 → GREEN → 변이 확인
2. 프리셋 등록 · 규칙 문장 · 개수
3. `tests/run-all.sh` → 커밋·푸시
4. `project-claude.sh ~/PROJECT/jj-agent-room <그 프로젝트 프리셋>` → 그 프로젝트에서 훅 직접 확인 → 그 프로젝트 커밋(사용자 지시 범위)

## 6. 의사결정 로그

- 2026-10-27: **deny 가 아니라 ask** — 지우기가 맞는 때도 있다(사용자가 시킨 정리). 사람이 승인 창에서 무엇을 지우는지 보고 고른다. 틀리면: 자동 모드에서 승인 창이 자주 뜸 → 임시 자리 목록을 넓힌다.
- 2026-10-27: **새 훅 하나**(bash-guard 에 더하지 않음) — bash-guard 는 268줄에 sudo·--no-verify·커밋 안내 셋을 맡고 있다. 한 파일 한 책임.

## 7. 발견·예외

- 변이 시험이 훅의 결함을 찾았다: 값싼 글자 거르기가 `(^|[^a-z])rm` 이라 JSON 의 `\n` 뒤(줄 맨 앞) rm 을 놓쳤다 — 여러 줄 명령의 둘째 줄 `rm -rf` 가 판정 없이 통과. `\n` 도 경계로 치고 여러 줄 경우 시험 둘을 더했다.
- 커밋 게이트 R-cx 가 `_file_delete`(36) · `_db_delete`(13)를 막았다 → 명령 종류별 함수로 나눔.
- 전파 때 `.claude/presets.lock` 에 `korean` 이 없어(잠금 파일은 git 밖) 처음 설치가 한국어 훅 셋을 지웠다 → `korean` 을 더해 다시 설치해 되돌림. 잠금 파일을 프리셋의 원천으로 믿으면 안 된다 — CLAUDE.md 의 룰셋 줄과 대조할 것.

## 8. 회고 (완료 시 작성)

- 목표 G1~G5 모두 달성. 시험 `tests/data-guard-test.sh` 45 · 공장 전체 149 통과. jj-agent-room 에서 사고 명령 둘(psql DELETE · rm -rf 저장소) → ask, SELECT → allow 를 실제 설치 훅으로 확인.
- 예상과 다른 점: 규칙 문장이 이미 있었다 — 사고는 규칙 부재가 아니라 "문서 문구를 승인으로 읽은" 해석이었다. 그래서 문장(G4)만으로는 부족하고 훅(G1~G3)이 본체다.
- 남은 한계: 래퍼 스크립트·ORM 안의 삭제는 못 본다(§3). 단일 파일 rm 은 보지 않는다.
