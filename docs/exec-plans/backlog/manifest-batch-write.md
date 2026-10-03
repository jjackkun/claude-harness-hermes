# manifest-batch-write — 설치 목록을 모았다가 한 번에 쓴다 (한 번 시도했다가 되돌림)

## 동기

설치 한 번이 `manifest_add` 를 항목마다(263개) 부르고, 그때마다 **python3 를 띄워 JSON 전체를
읽고 다시 쓴다**(`lib/factory_manifest.sh`) — O(n²) 에 프로세스 263개.

## 2026-09-23 에 한 시도와 실측

- 방식: `manifest_add` 는 탭 구분 한 줄을 버퍼 파일에 적기만 하고, 읽는 함수 5개(`manifest_read ·
  prune · field · mark · verify`) 첫 줄과 설치기 끝에서 `manifest_flush` 가 python3 **한 번**으로 반영.
- **이득**: 같은 트리·같은 조건에서 설치 1회 **10.45초 → 4.97초(2.1배)**, 매니페스트 263항목 **완전 동일**.
  (pyenv shim 우회를 넣은 뒤의 수치다 — 우회 전이라면 이득이 더 컸다.)
- **깨짐**: `tests/install-coexist-test.sh` **12건 실패** → 되돌렸다(되돌린 뒤 96/0 복구 확인).
  실패 예: `ⓔ 존재하지 않는 커밋 → 세움 (expected=e actual=x)` · `폴백 출처 = installed_version
  (expected=installed_version actual=manifest)` · `manifest 에 base(=공장판) sha 기록, 하류 sha 아님`.

## 기각된 가설 (둘 다 고쳐 봤으나 12건 그대로)

1. **커밋 해시 캐시** — 한 프로세스가 가짜 공장을 여러 개 만드는 시험에서 첫 해시를 물려받는다고 봤다.
   캐시를 지워도 12건. (`git rev-parse` 95번이 0.09초라 캐시할 이유도 없었다.)
2. **버퍼 경로 해싱** — `$(dirname "$dir")` 와 `$claude_dir` 표기가 달라 다른 버퍼가 된다고 봤다.
   버퍼를 매니페스트 옆으로 옮겨도 12건.

## 착수할 때 먼저 볼 것

- 실패 단언들은 전부 **공존 설치(`lib/factory_coexist.sh`)가 base 를 복원하는 경로**다.
  coexist 는 `manifest_field` 로 **이전 설치의 값**을 읽고 나서 `manifest_add` 로 새 값을 쓴다.
  버퍼 + lazy flush 에서 **같은 설치 안의 다른 항목이 먼저 flush 를 부르면** 이전 값 대신 이번 값을
  읽게 되는지 — 읽기·쓰기 순서를 한 항목 단위로 추적한다.
- 시험 하나(`install-coexist-test.sh`, 단독 2분 남짓)만 반복하며 고친다. 전체 묶음은 마지막에 한 번.

## 지금 얼마나 값어치가 있나

pyenv 우회 뒤 설치 1회 약 10초 중 약 5초. 시험 묶음은 병렬이라 벽시계 이득은 더 작다.
pyenv 없는 기계·CI 에서는 python3 호출 비용 자체가 이득이라 거기서 더 크다.

## 관련

- `docs/exec-plans/completed/2026-09-23-test-suite-parallel.md` §7
- 커밋 `09b6cca` 메시지의 "되돌린 것"

## 가설 (2026-10-03, 코드 읽기 — 미검증)

09-23 시도의 버퍼는 **파일**(프로세스를 넘어 남는다)이었다. 공존 시험은 설치 **사이에** 매니페스트 JSON 을 손으로 고친다
(예: `factory_commit` 을 없는 커밋으로 → ⓔ). 앞 설치가 남긴 미반영 버퍼가 있으면 다음 `manifest_field` 의 첫 flush 가
그 손편집을 **옛 값으로 덮는다** → ⓔ·`installed_version` 폴백·base sha 단언이 이번 값/옛 값을 읽는다. 12건 모두 "이전 설치 값을 읽는 경로" 라는 관찰과 맞는다.
기각된 두 가설(해시 캐시·버퍼 경로)이 둘 다 "버퍼가 남아 있다" 는 전제를 건드리지 않은 것도 맞는다.

### 다시 할 때의 설계 조건

1. 버퍼는 **프로세스 안**(bash 배열)에만 — 파일로 남기지 않는다.
2. `manifest_add` 를 부르는 **모든 설치 경로**가 끝에서 반영해야 한다 — 빠지면 설치 목록이 조용히 사라진다. 진입점 목록(harness_installers · factory_coexist · codex · uninstall …)을 먼저 grep 으로 세고 시험 하나씩.
3. 라이브러리가 `trap EXIT` 를 걸지 않는다(설치기의 trap 을 덮는다).

### 착수 보류 (2026-10-03)

이득(설치 1회 약 5초)에 비해 2번의 조용한 손실 위험이 크고, 같은 날 CI 를 30회 연속 빨강에서 막 되돌렸다 — 설치기 공용 코드는 CI 가 며칠 초록인 뒤에.
