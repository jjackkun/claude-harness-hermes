# prefer-tools-over-bash-commands
<!-- hermes:auto-generated version:1 created:2026-10-20 -->

## 문제 상황
파일 읽기·쓰기·변환을 위해 Bash 명령(cat, echo, sed, awk)을 먼저 쓰려는 경향이 반복됨. 전문 도구(Read, Edit, Write)가 있어도 셸 명령으로 해결하려다가 추가 검증이나 수정이 필요해짐.

## 규칙
- [ ] 파일 읽기 시도: `cat`, `head`, `tail` 대신 **Read 도구** 우선
- [ ] 파일 쓰기 시도: `echo`, `tee` 대신 **Write/Edit 도구** 우선
- [ ] 텍스트 변환(grep, sed, awk): Edit 도구 사용 가능한지 먼저 판단
- [ ] Bash 셸 명령은 "셸 전용 작업"(파이프, 조건문, 루프)일 때만 사용

## 근거
- 감지 횟수: 4회
- 관련 스킬: revalidate-benchmarks(주입 3) · local-tool-substitution(주입 1)
- 패턴 키: local-command-caveat
