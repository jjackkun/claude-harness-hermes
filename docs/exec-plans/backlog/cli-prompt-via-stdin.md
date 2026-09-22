# 구독 CLI 에 프롬프트를 인자가 아니라 stdin 으로 넘긴다

> 출처: 2026-09-22 code-reviewer 리뷰(성향 추출 Step 2) — MEDIUM

## 문제

`scripts/hermes-summarize.py:174` 와 `scripts/hermes_persona_extract.py` 는 프롬프트를 `-p <프롬프트>` **인자**로 넘긴다.
프롬프트에는 (마스킹된) 사람 발화가 통째로 들어 있어, 호출이 도는 동안(요약기 60초 · 성향 추출 최대 180초)
같은 컴퓨터의 다른 계정·프로세스가 `ps -ef` · `/proc/<pid>/cmdline` 으로 전문을 볼 수 있다.
`redact()` 는 알려진 비밀 패턴만 가린다 — 일반 서술·환경 정보는 그대로 인자에 실린다.

## 고칠 때 후보

- `run([bin, "-p", "--model", ...], input=prompt, ...)` — 프롬프트를 stdin 으로.
- 착수 전 확인: 구독 CLI 가 stdin 프롬프트를 `-p` 인자와 같게 처리하는지 실측(응답·소요 시간 비교 1회씩).
- 두 곳을 **한 번에** 고친다. 다른 `claude -p` 호출 지점(`hermes-dream.py` · `hermes-crystallize.py` · `hermes-evolve-skill.py` 등)도 같은 패턴인지 함께 센다.
- 시험: 가짜 실행 파일이 인자에서 프롬프트를 찾지 못하고 stdin 에서만 읽는지.

## 우선순위

중간. 이 컴퓨터는 사용자 한 명이 쓰는 WSL 이라 당장의 노출 대상은 없다. 다중 사용자 환경에 설치될 때 올린다.
