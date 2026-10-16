# iface-width-single-definition — R-iface 공개 심볼 계수를 한 곳으로 합친다

> 작성일: 2026-10-16
> 목적: 생성 시점 차단 훅과 편집 시점 폭 증가 경고가 같은 정의로 공개 심볼을 세게 한다.

## 개요

- `assets/hooks/iface_width.py` 는 "정의를 하나로" 두려고 만든 모듈이다(README 판정 모듈 절). 편집 시점 경고(`claude-posttooluse-size-warn.sh`)가 쓴다.
- 그런데 생성 시점 차단 훅 `claude-pretooluse-iface-guard.sh` 는 파이썬 블록 안에 자기 계수기(`public_symbols_py/js/sfc` · `LINE_COUNTERS`)를 따로 갖고 있다.
- 2026-10-16 R-iface 언어 확장(커밋 8ccbdb1)은 차단 훅에만 8개 언어(java kotlin csharp php swift go rust dart)를 더했다 → 이 언어들은 편집 시점 폭 증가 경고를 받지 않는다.

## 할 일 후보

- 차단 훅이 `iface_width.py` 를 불러 쓰게 하고, `LINE_COUNTERS` 를 `iface_width.py` 로 옮긴다.
- 확인: `tests/iface-gate-test.sh` · `tests/iface-guard-lang-test.sh` 무수정 통과 + size-warn 이 새 언어에서 폭 증가를 경고하는 시험 추가.
- 설치 목록: `iface_width.py` 가 훅 옆에 깔리는지(차단 훅이 의존하게 되면 부분 설치 시 동작) 확인.
