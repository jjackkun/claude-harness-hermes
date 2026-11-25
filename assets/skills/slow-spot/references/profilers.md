# 언어별 프로파일 명령

bash 는 `scripts/bash_profile.sh` + `scripts/trace_agg.py` 를 쓴다. 다른 언어는 표준 도구를 쓴다.
"실행 확인" 은 2026-11-25 공장 컴퓨터(Python 3.12.3 · Node v24.22.1)에서 느린 함수를 심은 작은 파일로 돌려
그 함수가 1위로 나온 명령이다. "미확인" 은 적기만 했다.

출력 파일은 `.harness/out/` 처럼 git 이 무시하는 곳에 둔다.

## Python

### 함수별 누적 시간 — cProfile (실행 확인)

```bash
python3 -m cProfile -o .harness/out/run.prof <스크립트.py> [인자...]
python3 -c "import pstats; pstats.Stats('.harness/out/run.prof').sort_stats('cumulative').print_stats(20)"
```

- `cumtime`(그 함수 안에서 부른 것 포함) 으로 범인 후보를 찾고, `tottime`(자기 시간) 으로 진짜 무거운 줄을 좁힌다.
- pytest 시험 하나가 느리면: `python3 -m cProfile -o .harness/out/t.prof -m pytest -q tests/test_x.py::test_y`

### 시작이 느릴 때 — import 시간 (실행 확인)

```bash
python3 -X importtime -c "import <모듈>" 2> .harness/out/import.txt
sort -t'|' -k2 -n .harness/out/import.txt | tail -15     # 둘째 칸 = 누적 µs
```

CLI·훅이 매번 1초씩 걸리면 대개 계산이 아니라 import 다.

### 떠 있는 프로세스 — py-spy (미확인, 이 컴퓨터에 없음)

`py-spy record -o .harness/out/flame.svg --pid <PID>`. 설치는 프로젝트 가상환경에만 한다(전역 설치 금지).

## Node

### CPU 프로파일 (실행 확인)

```bash
node --cpu-prof --cpu-prof-dir=.harness/out/cpu <파일.js>
python3 - .harness/out/cpu <<'PY'
import collections, glob, json, os, sys
f = max(glob.glob(os.path.join(sys.argv[1], "*.cpuprofile")), key=os.path.getmtime)
p = json.load(open(f))
name = {n["id"]: n["callFrame"]["functionName"] or "(anonymous)" for n in p["nodes"]}
for fn, n in collections.Counter(name[s] for s in p["samples"]).most_common(15):
    print(f"{n:6d}  {fn}")
PY
```

- 숫자는 표본 수다(대략 시간에 비례). 같은 `.cpuprofile` 을 Chrome DevTools 의 Performance 탭에 열면 불꽃 그래프로 볼 수 있다.
- npm 스크립트는 `NODE_OPTIONS="--cpu-prof --cpu-prof-dir=.harness/out/cpu" npm run <이름>` (미확인).

## 공통 — 시간만 잴 때

```bash
s=$(date +%s%N); <명령>; echo "$(( ($(date +%s%N)-s)/1000000 ))ms"
```

전후 비교는 프로파일러를 붙이지 않고 이 방식으로 3번 재서 가운데 값을 쓴다 — 프로파일러는 대상을 느리게 만든다.
