# R-out 의 `path` 머리가 인터프리터 둘째 단어를 아무거나 붙인다

> 작성일: 2026-10-01
> 목적: 훅의 `head_of` 가 `cmd:<머리>` 에 둘째 단어를 검증 없이 붙여, 토큰 모양의 인자가 `gate-events.jsonl` 의 `path` 칸에 남는다.

## 무엇

`assets/hooks/claude-posttooluse-output-budget.sh` 안의 `head_of` 는 첫 단어가 인터프리터 목록(`python3 bash git make sudo timeout …`)이면 둘째 단어를
`[A-Za-z0-9_.+-]` 필터 없이 그대로 붙인다(`-` 로 시작하거나 `=` 를 품으면 제외). 실제로 `python3 <토큰 모양 단어>` · `git <토큰 모양 단어>` · `sudo <토큰 모양 단어> ls` 는 그 단어까지 `cmd:` 뒤에 붙어 `path` 칸에 남는다.

2026-10-01 `out-shape-agent-fields` 구현 리뷰에서 발견했다. 새 `heads`(`out_shape.py`)는 알려진 부명령·스크립트 이름만 붙이도록 더 엄격하게 만들었지만,
`path` 칸의 머리는 그 계획이 **건드리지 않기로** 했다(기존 `out_report` 표의 분포와의 연속성).

## 왜 문제인가

- `.harness/gate-events.jsonl` 은 git 무시 파일이라 밖으로 나가진 않지만, 비밀값이 로컬 파일에 평문으로 남는다.
- `out_report.py` 의 머리별 표가 토큰 모양의 단어마다 행을 만든다(분포 오염).

## 후보

1. `head_of` 를 `out_shape` 의 같은 규칙으로 바꾼다 — `path` 의 머리가 `git status` · `python3 x.py` 처럼 알려진 것만 남고 나머지는 첫 단어만. 기존 분포와 한 번 어긋난다(옛 레코드와 비교할 때 표시 필요).
2. 또는 `head_of` 를 `out_shape.heads[0]` 로 대체해 규칙을 하나로 한다(DRY — 지금은 훅 안과 모듈에 둘).

## 착수 조건

- 위 1·2 는 `out_report` 의 머리별 분포를 바꾸므로, 바꾸기 전 `--by head` 표를 저장해 전후를 대조한다.

근거: `docs/exec-plans/completed/2026-10-01-out-shape-agent-fields.md` §7 (구현 리뷰).

## 결과 (2026-10-03)

- [x] 후보 1+2 를 합쳤다 — 훅의 `head_of` 는 `cd X &&`·`VAR=값` 걷기는 그대로 두고, 둘째 단어 판정만 `out_shape.second_word`(알려진 부명령 · 스크립트 파일 이름) 하나로 쓴다. 모듈을 못 불러오면 첫 단어만(EXTRA 는 지금처럼 `shape=err`).
- [x] `out_shape._second` → 공개 `second_word`. git 부명령에 `check-ignore`·`reflog` 추가(재생 대조에서 잃던 머리). 둘째 단어 끝 `;` 는 떼고 판정.

### 착수 조건 — 바꾸기 전 `--by head` 표 (30일, 1,143건, 상위)

`(머리 없음)` 341 · `sed` 83 · `grep` 112 · `for` 31 · `{` 29 · `git show` 8 · `echo` 67 · `cat` 42 · `python3` 123 · … · `timeout 540` 4 · `-d);` 16

옛 레코드의 `path` 는 다시 쓰지 않는다 — 이날 이후 `timeout <수>`·`sudo <x>`·토큰 모양 둘째 단어 행이 사라진다(분포 비교 때 2026-10-03 경계 표시).

### 실측

- 재생 대조: 이 프로젝트 대화 기록의 Bash 명령 1,097건을 옛·새 `head_of` 에 넣음 → 바뀐 것 25건(전부 `timeout <수>` → `timeout` 23 · `bash x.sh;` → `bash x.sh` 2) · 머리 종류 102 → 93. 쓸모 있는 머리 손실 0.
- 시험: `output-budget-test` 32/32(새 5건, 수정 전 4 빨강) · `out-shape-test` 65/65.

## 회고

- 잘된 것: 실제 명령 재생으로 "잃는 머리" 3개(`git check-ignore`·`git reflog`·`;` 꼬리)를 커밋 전에 찾았다 — 시험 픽스처로는 안 보였다.
- 다음 룰 후보: 없음.
