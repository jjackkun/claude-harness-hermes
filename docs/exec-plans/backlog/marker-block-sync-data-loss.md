# marker-block-sync-data-loss — 마커 블록 갱신이 사용자 내용을 지울 수 있다

> 발견: 2026-10-21, 기획 사슬 계획(`docs/exec-plans/active/2026-10-21-planning-skill-chain-plan.md`) Step 5 의 의도 대조 평가 중 기준 실행이 보고.
> 코드 확인: `lib/harness_installers.sh` `harness_sync_marker_block` (218~266행) 을 읽어 1번을 확인함. 2~4번은 보고 내용이며 재현 시험은 아직 없음.

## 무엇이 문제인가

1. **END 마커가 없으면 BEGIN 뒤 전부 삭제** — 257~261행 awk 가 BEGIN 에서 `skip=1`, END 에서만 `skip=0`. 프로젝트의 `docs/design-docs/core-beliefs.md` 에서 END 줄이 지워진 채 재설치하면 BEGIN 아래 사용자 R 룰이 사라진 파일로 `mv` 된다. **데이터 손실.**
2. **python3 실패 시 블록이 빈 문자열** — 232행 `block="$(... python3 ...)"` 의 실패를 확인하지 않는다. 그러면 하네스 블록이 빈 줄로 바뀐다 (보고 내용, 코드 읽기로 경로 확인).
3. **`awk -v blk=` 가 백슬래시를 해석** — 표 안의 `\|` 가 `|` 로 바뀐다 (보고 내용).
4. **CRLF 줄끝이면 마커를 못 찾는데 "갱신" 로그는 찍힘** — 조용한 실패 (보고 내용).

## 고칠 방향 (착수 시 계획서로)

- END 마커가 없으면 파일을 건드리지 않고 경고 후 반환.
- python3 실패·빈 블록이면 반환.
- 블록 교체를 python 하나로 옮겨 이스케이프·CRLF 를 함께 해결.
- 시험: END 없음·CRLF·`\|` 포함·python 실패 네 경우를 빨강 먼저.

## 관련

- `install_harness_docs_templates` 의 `find … -name "*.tmpl" -o -name "*.md"` 는 `.gitkeep` 을 복사하지 않는다 — `docs/exec-plans/{active,backlog,completed}/.gitkeep` 이 소우주에 가지 않는다. 의도인지 확인 필요.
- **보안 — 산술 비교가 환경변수 값을 실행한다 (2026-10-21 재현):** `[[ ${HARNESS_DOCS_TEMPLATES:-0} -eq 1 ]]` (`lib/harness_installers.sh:410`) 에
  `HARNESS_DOCS_TEMPLATES='a[$(touch PWNED)]'` 를 주면 `PWNED` 가 만들어졌다(판정은 skip 인데도 명령은 실행됨). `01` 도 참.
  같은 모양(`-eq 1 ]]`)이 `lib/*.sh` 에 19곳. 위험은 그 변수 값을 남이 정할 수 있을 때 — 소우주 `.harnessrc` 값이 이 비교로 흘러드는지 먼저 확인.
  고칠 방향: `[[ "${VAR:-0}" == 1 ]]` 문자열 비교로 일괄 교체 + 주입 값으로 PWNED 가 안 생기는 시험.
