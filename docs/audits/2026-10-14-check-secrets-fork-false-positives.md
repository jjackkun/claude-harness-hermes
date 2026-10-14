# 2026-10-14-check-secrets-fork-false-positives — 비밀값 검사가 JS 시험 폴더·빈 쿼리 값·운영 금지 기본값을 막았다

> 작성일: 2026-10-14
> 목적: 소우주 jj-agent-room 의 커밋이 R-secret 오탐으로 막힌 사실과, 검사 규칙을 넓힌 근거를 남긴다 (규율 변경은 audits 근거 후).

## 1. 종류 / 일자 / 작성자

- 종류: incident (게이트 오탐)
- 일자: 2026-10-14
- 작성자: 에이전트 (사용자 승인 — "권장안대로 공장 규칙 고치고 다시 커밋해")

## 2. 무엇이 발생했는가 (사실)

jj-agent-room(원본 Cumora 포크) 커밋이 R-secret 에 막혔다. 4개 파일 16줄, 전부 진짜 비밀이 아니다.

| 파일 | 걸린 것 | 실제 |
|---|---|---|
| `server/src/__tests__/agents-computer-engine.test.ts` (13줄), `…windows-service.test.ts` (1줄) | `API_KEY=<가짜 값>`, `TOKEN=<가짜 값>` 형태 | 원본 시험의 가짜 fixture. 포크가 같은 파일의 다른 줄(기대값)을 고쳐 파일 전체가 검사됐다 |
| `server/src/env.ts:31` | `'dev-agent-runtime-secret-do-not-use-in-prod'` | 원본이 공개한 개발용 기본값. 운영에서는 기동이 거부된다 |
| `src/components/AuthScreen.tsx:46` | 주석 `#token=<빈 값>&companyId=<빈 값>&error=...` 형태 | 주소 형식 설명. `token` 값은 비어 있고 `&` 뒤는 다음 인자다 |

## 3. 왜 그렇게 되었는가 (분석)

- 면제 경로가 루트 `tests/` 만 있다. JS/TS 관례인 `__tests__/`(Jest·node:test, 소스 옆에 둠)가 빠졌다 — 같은 이유(가짜 자격증명이 정상인 구역)인데 이름만 다르다.
- `SECRET_VALUE` 첫 글자에 `&` 를 허용해, 빈 쿼리 값 뒤의 `&next=` 를 값으로 읽었다.
- 자리표시자 어휘에 "운영 금지 표시" 가 없다. `do-not-use-in-prod` 는 그 값이 비밀이 아니라는 명시다.

## 4. 판단 (바꾼 것)

1. `EXCLUDE_RE` 에 `(^|/)__tests__/` — `tests/` 와 같은 근거의 경로 면제. 값 어휘를 넓히지 않는다.
2. `_kv_exempt`: 값이 `&` 로 시작하면 빈 쿼리 값 → 면제.
3. `PLACEHOLDER_RE` 에 `do-not-use-in-prod(uction)?` — 겹치는 구간만 면제(줄 전체 아님).

계속 걸려야 하는 줄을 면제 표(`tests/check-secrets-label-exempt-test.sh`)에 같이 넣었다: `&` 가 중간에 있는 값, 운영 금지 표시 없는 비밀 문자열, `__tests__` 가 아닌 경로의 같은 값.

## 5. 다음 행동

- [ ] 소우주 재설치 때 새 검사기가 전파된다 (jj-agent-room 은 `.git/hooks/check-secrets.py` 를 같은 내용으로 갱신)
