# 설치 doctor / repair — 소우주 설치 상태 진단·복구 명령

> 출처: `docs/audits/2026-09-19-ecc-gap-list.md` (ECC v2.2.1 대비 결핍 목록, 사용자 "다 필요한 것들" 확정 2026-09-19) — #1 (가치 상)

## 문제

복사 설치(`.claude/.factory-manifest.json`)는 설치·갱신만 있고 **진단·복구가 없다**. 어긋남은 세션 시작 훅의
`[factory-link WARN]`·`[factory-tamper WARN]` 경고로만 드러나고, 고치는 길은 `update-all`(12곳 전부) 또는 사람 손이다.
실측: 2026-09-19 terminal-shipping 재설치에서 `adhd-output.md` 가 lock 에 없다는 이유로 조용히 제거됐다(설치 로그 `removed → adhd`).
공장 자기 설치 상태도 `chore(harness): 자기 설치 상태 갱신` 수작업 커밋으로 맞춰 왔다.

## ECC 의 실체

`scripts/doctor.js` — 매니페스트 대비 drift(변조·누락·고아) 진단, `--json`. `scripts/repair.js` — `--dry-run` 뒤 복구.
2.2.0 에서 선택 재설치가 이전 소유권 원장을 병합해 고아 파일을 막도록 고쳐졌다.

## 고칠 때 후보

- `scripts/harness-doctor.py <소우주>`: 매니페스트 sha256 대조 → 변조/누락/고아/lock 과 설치본 불일치 네 종류 보고. 읽기 전용, `--json`.
- `--repair --dry-run` → 무엇을 덮어쓸지 목록만, `--repair` 는 사람 확인 뒤. 소우주 확장(`.hermes/skills/`)은 절대 건드리지 않는다.
- `update-all` 앞단에 doctor 를 붙여 "재설치로 사라질 파일" 을 먼저 보여준다(오늘의 adhd 사례 예방).
- 우주 대시보드(계획 hermes-dashboard 목표 6) 의 "factory_commit 일치 여부" 열이 이 진단을 재사용한다.

## 착수 조건

hermes-dashboard 계획과 같은 시기. 매니페스트가 이미 있어 하루 작업.
