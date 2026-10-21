# NOTICE — prd-writer

이 스킬은 아래 두 원본의 절차를 한국어로 옮기고 고쳤다. 스킬 폴더가 설치 단위라 출처를 폴더마다 둔다.

## 원본

- `phuryn/pm-skills` — `pm-execution/skills/create-prd/SKILL.md`
  MIT License, Copyright (c) 2026 Pawel Huryn. 가져온 것: 짧게 쓰기, 빈 곳 질문 최대 3개, 지어내지 않고 가정으로 보내기, 비범위, 기존 PRD 검토 순서.
- `product-on-purpose/pm-skills` — `skills/deliver-prd/SKILL.md` 8단계 "Agent Execution Contract"
  Apache License 2.0 (`license: Apache-2.0`). 가져온 것: 요구마다 검증 방법, 정본 문서·손대지 말 것·막힐 때 묻는 곳을 적는 실행 계약 칸.
  Apache-2.0 전문: https://www.apache.org/licenses/LICENSE-2.0

## 바꾼 점

- 8절 구성을 사슬 계약(`references/contract.md`)의 8절로 바꿨다. 시장 구간·6부분 가치 제안·연락처 절은 뺐다.
- 저장 위치 `PRD-<name>.md` → `docs/product-specs/<이름>/prd.md`, 머리 세 줄(`status`·`updated`·`contract-version`) 추가.
- 요구 표(FR 번호·검증·우선순위·상태)와 기계 검사기 `scripts/check_prd.py` 를 새로 만들었다.
- 웹 조사 단계, 뉴스레터 링크, 다른 스킬 이름 참조, Project Memory Contract 를 뺐다.
- 한국어·존댓말 보고로 바꿨다.
