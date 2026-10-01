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

근거: `docs/exec-plans/active/2026-10-01-out-shape-agent-fields.md` §7 (구현 리뷰).
