# bash-execution-intent-check
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
Bash 도구 호출 시 권한 프롬프트 판정이 불확실하여 분류기가 12건의 추가 케이스를 검증해야 했음. 명령어를 '다루기만' 하는 경우(grep, cat, git 등)와 '실제로 실행'하는 경우(python, bash 직접 실행)의 판정이 혼재됨.

## 규칙
- [ ] "다루기만" 하는 명령어는 권한 프롬프트 불필요: grep, cat, head, tail, find, sed, awk, sort, uniq, git log/status/show, ls 등
- [ ] "실행/수정"하는 명령어는 권한 필수: python 스크립트 실행, bash -c 또는 sh -m 직접 실행, npm/pip/uv 설치, 파일 쓰기(>, >>)
- [ ] 제어 구문 벗기기: then/do/else/{/} 다음의 실제 명령어만 판정
- [ ] 래퍼 제거 후 판정: uv run, sudo, nice, xargs, bash -lc 등을 먼저 벗겨내고 내부 명령어 확인
- [ ] 동적 값 추적: $(), 백틱, 변수 대입 내 명령어까지 재귀적으로 추적
- [ ] 옵션 값 무시: -W, -X 등 옵션 뒤의 경로·값은 명령 판정에 포함하지 않음

## 근거
- 감지 횟수: 3회 (분류기 보강 2회, 시험 실패 B신호 3건)
- 패턴 키: bash
- 영향: 권한 프롬프트 피로도 감소, 자동 모드 안전성 향상
