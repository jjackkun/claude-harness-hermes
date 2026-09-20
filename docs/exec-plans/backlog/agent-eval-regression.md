# agent-eval-regression — 하네스 행동 회귀 테스트

> **완료 → `docs/exec-plans/completed/2026-09-20-agent-eval-regression.md`** (2026-09-20). 후속: backlog `identity-files-edit-guard`.

## 배경

YouTube 영상 「Anthropic 제안한 코드 짜기 전에 무조건 쓰라는 파일 | AI 네이티브 SDLC 도입 정리」
(`docs/videos/2026-09-05-intent-md-ai-native-sdlc/`) 13:17~14:15 에서 소개된
"agent evals" 패턴. 대화로 검토한 결과를 남긴다.

## 무엇을 하려는 것인가

현재 `tests/`(pre-commit 4단 검사, 훅 스모크 테스트)는 **코드가 규칙을 어겼는지**를 검사한다
(정적 분석 — AST, grep, lint). 이 후보가 채우려는 공백은 **Claude가 규칙을 실제로 어기는 행동을
하는지**를 검사하는 것 — 대상이 코드가 아니라 에이전트 자신이다.

예: `rules.md`의 R1 설명 문구가 순화돼도 `test_r1_boundary.py`(정적 검사)는 코드가 안 바뀌었으니
계속 통과한다. 하지만 그 뒤로 Claude에게 "once/에서 scheduled/ 걸 가져다 써줘"라고 시켰을 때
실제로 거부하는지는 별도로 검증해야 알 수 있다.

## 왜 지금 만들지 않는가

1. **비용이 실재한다.** 현재 `ci.yml`은 순수 결정론적 검사라 무료다. agent eval은 PR마다 +
   매일 새벽 실행 시 실제 Claude 호출이 필요해 API 비용이 든다.
2. **R3 룰과의 관계를 먼저 풀어야 한다.** 영상 예시는 `ANTHROPIC_API_KEY` 로 CI 에서 직접
   API를 호출한다. `assets/rules/harness/rules.md` R3(anthropic SDK/API 직접 호출 금지,
   구독 CLI 어댑터 경유)는 애플리케이션 코드를 겨냥한 것이지만, 하네스 자체 평가에서
   API 키 경로를 쓰는 게 이 프로젝트의 원칙과 모순되는지 판단이 안 됐다.
3. **영구 유지보수 비용이 생긴다.** 과제 파일(20~50개) + 채점 스크립트를 한 번 만들면
   끝이 아니라, 룰을 하나 바꿀 때마다 관련 eval 케이스를 같이 갱신해야 한다.

## 착수 조건 (제안)

아래 중 하나가 실제로 발생하면 exec-plan으로 승격 검토:

- 룰/스킬 변경 후 Claude 행동이 실제로 퇴행한 사례가 1건 이상 관측됨
- R3와 CI 내 LLM 호출의 관계에 대한 판단이 `docs/design-docs/`에 먼저 정리됨
- 이 리포를 프리셋으로 설치한 다른 프로젝트(팀 규모)에서 필요성이 제기됨

## 착수 조건 점검 (2026-09-18 실측)

| 조건 | 실측 | 판정 |
|---|---|---|
| ① 룰/스킬 변경 뒤 행동 퇴행 관측 | 저장소 전체에서 "퇴행" 언급 1건(`completed/2026-09-14-adhd-output-rule.md`) — 원본 프로젝트(i-have-adhd)의 자체 평가 수치이지 이 하네스에서 관측된 퇴행이 아님 | 미충족 |
| ② R3 와 CI 내 LLM 호출 관계의 설계 판단 | `docs/design-docs/agent-eval-llm-path.md` 작성 — 로컬·수동·구독 CLI(haiku)·어휘 채점, CI·API 키·야간 자동 실행 금지 | **충족** |
| ③ 다른 프로젝트의 필요 제기 | 소우주 backlog 어디에도 없음 | 미충족 |

결론: 만들지 않는다. ①·③ 중 하나가 생기면 위 설계 경로로 `assets/skills/skill-creator/scripts/run_eval.py` 를 본떠 착수한다.
비용 근거: `claude -p` 는 2026-06-15 부터 월간 크레딧(Max 20x ≈ 2,200회) — 과제 20~50개 야간 실행은 월 600~1,500회로
요약·드림 몫과 경쟁한다.

## 참고

- 원본 논의: 2026-09-07 대화 (intent.md 영상 검토 중 파생)
- 관련 문서: `docs/videos/2026-09-05-intent-md-ai-native-sdlc/intent-md-ai-native-sdlc.md` §3 Test 단계

## ECC 대조 (2026-09-19) — skill-comply · eval-harness/pass@k 를 이 계획의 구현 형태로

> 출처: `docs/audits/2026-09-19-ecc-gap-list.md` (ECC v2.2.1 대비 결핍 목록, 사용자 "다 필요한 것들" 확정 2026-09-19) — #2·#3 (가치 상, 사용자 확정)

- **skill-comply**(`skills/skill-comply/`): 엄격도 3단계 프롬프트로 시나리오를 자동 생성 → 에이전트 실행 → 툴콜 타임라인을 분류해
  규칙 준수율을 낸다. 우리 "행동 회귀 테스트" 의 시나리오 생성·채점 방식으로 그대로 쓸 수 있다.
- **eval-harness + harness-optimizer**(`skills/eval-harness/`, `agents/harness-optimizer.md`): 같은 시나리오를 k 회 돌려 pass@k · pass^k 로
  훅·룰 구성을 채점. 훅 추가·룰 승격(`harness-promote-rule`) 전후를 이 수치로 비교하면 "이 훅이 값을 하는가" 에 답한다.
- 우리 제약: 모델 호출은 구독 CLI(haiku) 경로만(설계 결정 2026-09-18 `855aa18`), CI·야간 자동 실행 금지, 로컬·수동. 시나리오는 `tests/` 에 고정 픽스처.
- `.harness/gate-events.jsonl` 발화율(gate_report) 과 합쳐 "발화했는데 안 지켜진 비율" 을 첫 지표로.
