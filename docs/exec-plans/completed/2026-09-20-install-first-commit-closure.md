# 2026-09-20-install-first-commit-closure — "설치 직후 커밋이 그 프로젝트의 게이트를 통과한다" 를 테스트로 못 박는다 (완료)

> 백로그에서 바로 진행(사용자 "진행하자" 2026-09-20). 새 파일 없음 — 기존 폐로 테스트·템플릿·프리셋 문구 수정.

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

## 한 일 (2026-09-20)

- `tests/install-closure-test.sh` [6]: 픽스처에 설치 → `git add -A` → **첫 커밋 rc 0** 을 네 조합으로 단언 — `harness` · `harness hermes` · 공장 자기 설치 조합(`+adhd mcp skill-dev`) · 기존 `core-beliefs.md` 가 있는 프로젝트. 막히면 게이트 메시지를 그대로 보인다.
  자기 검사: 같은 픽스처에 비밀값 파일을 넣으면 커밋이 막힌다 — 훅이 안 깔려 통과하는 헛통과를 막는다.
- [7]: 설치기가 생성·복사한 문서(스킬·에이전트·룰·역할 템플릿 제외)가 prettier 규격인지 본다. prettier 가 없으면 **SKIP 을 찍고 통과로 세지 않는다**(`HARNESS_PRETTIER_BIN` 으로 지정).
- 원인 정정: ai-create 의 R-fmt 위반은 하네스 블록이 아니라 **공장 문서 템플릿의 강조 표기**(`*…*` → prettier 는 `_…_`)였다. 실측으로 새 설치의 위반 3개 파일을 찾아 고쳤다 —
  `ARCHITECTURE.md.tmpl`(강조·표 정렬) · `CLAUDE.md.tmpl`(강조) · `promotion.md.tmpl`(이중 공백), 그리고 프리셋(`harness.conf`·`hermes.conf`)의 CLAUDE.md 절에서 `**제목:**` 뒤 목록 앞 빈 줄 9곳.
  블록 자체는 기본 설정·ai-create 설정 모두에서 위반이 없었다(재현 실측).
- 영수증 안내 한 줄: 갈라진 소우주는 설치물을 병합하지 말고 병합 뒤 재설치로 재정렬 → doctor 깨끗 확인.
- 정리: 오늘 넣은 `HARNESS_REGISTER=0` 은 기존 `HERMES_NO_REGISTER=1`(+임시 경로 자동 생략, `lib/registry.sh`)과 **중복**이었다 — 걷어내고 테스트·러너를 기존 변수로 바꿨다.

## 검증

- install-closure 16(prettier 지정) / 14 + SKIP 1(미지정). role-templates 61 · doctor 35 · harness-eval 26 · dep-contract 21. 공장 doctor 깨끗, R-doc 일치, 등록부 3줄 유지.
- 오늘 앞서 같은 픽스처 첫 커밋이 P9 에 두 번 막힌 것을 직접 봤다(역할 템플릿 면제 전 · 훅 변수 이름) — [6] 은 그 두 사고를 그대로 재현하는 자리다.

## 8. 회고

- 잘된 것: "깔아 보고 커밋해 본다" 한 줄이 오늘의 세 사고를 모두 덮는다. 위반 원인을 추측(하네스 블록)으로 적었다가 재현이 안 되자 실측으로 정정했다.
- 잘못된 것: 백로그에 원인을 실측 없이 적었다(블록 탓). 기존 옵트아웃 변수가 있는지 찾지 않고 새 변수를 만들었다 — 그 결과 자기 설치가 공장을 등록부에 넣었고 손으로 되돌렸다.
- 다음 룰 후보: 설치기에 환경변수·옵션을 더하기 전에 `lib/` 에서 같은 뜻의 기존 것을 grep 한다. 백로그의 "원인" 칸은 재현 명령이 없으면 "추정" 이라고 적는다.
