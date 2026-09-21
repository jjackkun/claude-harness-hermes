# 사실 대조 — PDF 주장과 확인 상태

> 작성일: 2026-09-21
> 목적: 기획서가 기대는 숫자마다 출처와 확인 상태를 붙여, 확인된 것과 챗봇의 말을 구분한다.

## 개요

출처는 넷으로 나눈다.

| 표시 | 뜻 |
|---|---|
| **공식** | 2026-09-21 에 `typesafe.ai` · `docs.typesafe.ai` · `github.com/typesafe-ai/skills` 에서 직접 확인 |
| **사용자 화면** | 사용자가 자기 콘솔에서 본 화면(PDF 19쪽 캡처). 캡처가 썸네일이라 글자는 챗봇 판독(20쪽)에 기댄다 |
| **저장소 실측** | 2026-09-21 에 이 저장소의 기록을 세어 얻은 값 |
| **미확인** | PDF 의 챗봇이 한 말. 아무도 확인하지 않았다 |

## Jev 자체

| 주장 | 값 | 출처 |
|---|---|---|
| 제품·모델 이름 | TypeSafe AI 의 **Jev**, "first System One Model, optimized for automation" | 공식 |
| 모델 버전 | `jev-1.13` | 공식 (docs 색인) |
| 입력 가격 | **$42 / 10억 입력 토큰** (= $0.042 / 100만) | 공식 |
| 가격 비교 | "238x Lower input price than Claude Fable 5.1" | 공식 — 42 × 238 = $9,996, 즉 Fable 5.1 입력가를 약 $10/1M 으로 잡은 셈 |
| 속도 | "193.6x Faster", 예시 0.114 s 대 8.566 s (System One 작업 기준) | 공식 |
| 작업당 비용 예시 | $0.000081 대 $0.013880 | 공식 |
| 접근 상태 | early access | 공식 |
| 질문 종류 | **Choice**(목록에서 고르기 → `choice`·`probabilities`·`confidence`), **Score**(루브릭 점수 → `score`·`probabilities`·`confidence`), **Noul**(참인가 → 0–1) | 공식 |
| 요청 모양 | "state and typed questions" 를 한 요청에 | 공식 (필드 이름 미상) |
| 엔드포인트 · 인증 헤더 · 키 환경변수 | 문서 색인에 없음. `docs.typesafe.ai/api.md` 에 있다고 가리킨다 | **미확인** — 기획서 P0 에서 확인 |
| 입력 한도 · 호출 한도 | 문서에 없음 | **미확인** |
| 입력 형태 | 텍스트 전용(이미지 불가) | **미확인** — 공식 문서에 명시 없음 |
| 출력 토큰 | **무료** | PDF 챗봇(7쪽). 공식 가격표에는 출력 요금 항목 자체가 없다 — 입력만 적혀 있다는 점은 무료 주장과 어긋나지 않는다 |
| 무료 크레딧 | **매달 $5** (`Monthly credit`, Sep 20, 2026 지급 → Oct 20, 2026 만료) | **사용자 화면** — 공식 사이트·문서에는 언급 없음 |
| 크레딧 차감 순서 | 만료가 가까운 것부터 ("Credits closest to expiring are used first") | 사용자 화면 |
| 자동 결제 | `Auto-recharge: Off`, 카드 미등록 → 소진 시 호출 정지 | 사용자 화면 |
| 입력의 학습 사용 | "We will not train or fine tune any artificial intelligence or machine learning models on your prompts or other Input." | 공식 (`typesafe.ai/privacy`, 2026-09-21) |
| 입력 보관 기간 | "for as long as reasonably necessary to provide you with the Services, **or otherwise in support of our business or commercial purposes**" — 기한 없음 | 공식 (같은 문서) |
| 입력의 제3자 제공 | "We will not disclose any Input to a third party other than our service providers." | 공식 (같은 문서) |
| 저장 위치 | 미국 | 공식 (같은 문서) |
| 보관하지 않는 옵션 | 언급 없음 | 공식 (같은 문서) |
| 보관 안 함 (ZDR) | "zero data retention (ZDR) for enterprise customers" — **기업 고객만.** 조건·절차 비공개 | 공식 (`docs.typesafe.ai/models`, 2026-09-21) |
| 데이터 처리 부속서 (DPA) | 서비스 계약에 포함. 유출 시 "within 72 hours" 통지, EU SCC(Module 2)·UK Addendum. 보관은 "as long as necessary taking into account the purpose" — 기한 없음 | 공식 (`typesafe.ai/legal/data-processing`) |
| 보안 인증 (SOC 2 · ISO 27001) | Trust Center(`trust.typesafe.ai`)가 스크립트로 그려져 읽지 못함 | **미확인** |
| 제3자 평가 | Opper(2026-09-18 확인): 미국 경로 ZDR "Not established", 이전 방식 "unknown". GitHub `fdsimms/todo#2781`: "US-hosted, with zero data retention available on the enterprise tier only" 를 이유로 도입 거절 | 제3자 — 원문 확인 |
| 사용권 조항 | 무제한·영구·취소 불가 사용권은 **Feedback**(사용자 의견)에 대한 것, API 입력이 아님. API 전용 약관이 따로 있는지는 미확인 | 공식 (`typesafe.ai/terms`) |
| $5 로 쓸 수 있는 양 | 5 ÷ 0.042 = **약 1억 1,900만 입력 토큰 / 월** | 위 두 값으로 계산 |

## 스킬 저장소

| 주장 | 값 | 출처 |
|---|---|---|
| 라이선스 | MIT | 공식 |
| 설치 | `claude plugin marketplace add typesafe-ai/skills` → `claude plugin install typesafe@typesafe-ai`, 또는 `npx skills add typesafe-ai/skills --skill typesafe-ai` | 공식 |
| 호출 | Claude Code 에서 `/typesafe:typesafe-ai` | 공식 |
| 역할 | "Agent skills for building with TypeSafe" — 사용자 코드에 Jev 를 붙이는 가이드. Claude Code 자체 비용을 줄이는 도구가 아니다 | 공식 (PDF 11쪽 설명과 일치) |

## 확인하지 않은 주장

| 주장 | 쪽 | 왜 조심하나 |
|---|---|---|
| Claude 모델별 단가 표(Opus $5 · Sonnet $3 · Haiku $1) | 2–3 | 이 저장소에서 대조하지 않았다. 사용자는 구독(Max)이라 토큰 단가로 청구되지 않는다 |
| 10단계 브라우징 비교표의 "Claude 3.7 Sonnet" | 22 | 옛 모델 이름이다. 표 전체가 최신 가격 기준인지 알 수 없다 |
| OpenJev · mini-jev · jevlike · vLLM PR #57250 | 4 | 저장소·PR 존재를 확인하지 않았다 |
| OpenRouter `typesafe/jev-latest` · `jev-1.13` | 8 | 모델 버전 이름은 공식 문서와 같지만 OpenRouter 등재는 미확인 |
| Vercel AI Gateway $5 프로모션 | 9, 19 | 미확인 |
| "앞단 게이트웨이로 30~50% 이상 절감" | 9 | 근거 없이 제시된 범위. 이 저장소 실측은 [proposal.md](proposal.md) §2 참고 |
| 사례별 효과(크롤러 10배, TTFT 1초 이상 단축 등) | 16–26 | "Threads 에 공유됐다" 는 전언. 원 게시물 링크가 없다 |

## 저장소 실측 (2026-09-21)

| 무엇 | 값 | 어떻게 셌나 |
|---|---|---|
| 이 프로젝트 사용자 프롬프트 | 994건 (대화 기록 430개) | `~/.claude/projects/-home-jjackkun-PROJECT-claude-harness-hermes/*.jsonl` 의 사용자 메시지 중 도구 결과·메타·`<` 로 시작하는 주입 제외 |
| 그중 짧은 명령형 (40자 이하 + 테스트·린트·빌드·포맷·커밋 등 키워드) | 87건 | 같은 파일, 정규식 |
| 그중 커밋 요청을 뺀 것 | **3건 (0.3%)** — 셋 다 결과 해석을 요구("정상적이야?") | 커밋은 메시지 작성·게이트 처리가 필요해 걸러낼 대상이 아니다 |
| 스킬 검색 훅 호출 | 818회 — 주입 703회, **결과 없음 115회 (14.1%)** | `.hermes/hooks.log` 의 `[hermes-search-hook]` 줄 |
| 스킬 검색 뉘앙스 폴백 | **운영에서 꺼져 있음** — 배포 훅이 `--no-fallback` 을 넘긴다 | `scripts/hermes-search.py:407-411` |
| 루프 헛바퀴 차단 | 이미 있음 — `NO_PROGRESS_LIMIT = 3` 결정론적 카운터 | `scripts/hermes_loop.py:23` |
| `claude -p` 를 쓰는 곳 | summarize · dream · crystallize · evolve-skill · search_fallback · harness-eval · summon · loop | `scripts/` grep. 대부분 **텍스트 생성**이라 Jev 로 대체할 수 없다 |

키워드 기준 계산은 표현이 다른 요청을 놓칠 수 있다. 0.3% 는 정밀한 값이 아니라 "많아야 몇 % 수준" 이라는 뜻으로만 쓴다.
