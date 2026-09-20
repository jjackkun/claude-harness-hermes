# install-first-commit-closure — "설치 직후 커밋이 그 프로젝트의 게이트를 통과한다" 를 설치기가 보장하지 못한다

> 출처: 2026-09-20 소우주 커밋 대행(ai-create · terminal-shipping)과 harness-eval 픽스처에서 하루에 세 번 겪었다.

## 실측 (설치 직후 첫 커밋이 막힌 사례)

| 어디서 | 막은 게이트 | 원인 | 그날의 조치 |
|---|---|---|---|
| harness-eval 픽스처 · terminal-shipping | P9(비밀값) | 역할 템플릿(ECC 원문)의 가짜 예시 자격증명 | 템플릿 폴더 면제(공장 1299a6e · 하류 4c978f08) |
| harness-eval 픽스처 | P9 | 새 훅의 변수 이름에 TOKEN → ENV_SECRET 오탐 | 변수 이름 변경(backlog `check-secrets-false-positives`) |
| ai-create | R-fmt(prettier) | 설치기가 `docs/design-docs/core-beliefs.md` 에 넣는 하네스 블록이 prettier 규격이 아니다(표·빈 줄) | 그 파일만 `prettier --write` 후 커밋 |

## 같이 본 것 — 갈라진 설치 이력의 병합이 잡종을 만든다

ai-create 는 다른 컴퓨터의 옛 설치 커밋 6개와 갈라져 있었다. `merge -X ours` 는 충돌 덩어리만 로컬로 풀고, **충돌 없는 옛 판의 덩어리는 그대로 들어온다** —
`scripts/hermes-search.py` 에 공장에서 이미 옮겨진 함수가 한 번 더 들어가 최신판도 옛 판도 아닌 잡종이 됐다. 공존 설치는 이것을 "하류 수정(c)" 으로 보고 보존한다(이력에 없는 내용이므로).
doctor 가 "불일치 1" 로 잡아 공장판으로 되돌렸다. 설치물은 병합하지 말고 **재설치로 재정렬**하는 것이 맞다.

## 후보

- `tests/install-closure-test.sh` 에 "픽스처 설치 → `git add -A` → 첫 커밋이 rc 0" 을 프리셋 조합별로 추가(harness · harness+hermes · +node 의 prettier 포함). harness-eval 러너는 이미 첫 커밋 실패 사유를 보인다.
- core-beliefs 하네스 블록 템플릿을 prettier 규격으로 고쳐 넣는다(공장 문서 템플릿은 2026-09-16 에 이미 같은 일을 겪었다 — `98dc9df` "prettier 규격").
- 소우주 설치 커밋 안내(영수증 메시지)에 "갈라졌으면 병합 후 재설치 → doctor 깨끗 확인" 한 줄.
