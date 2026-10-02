# 멀티 에이전트 협업·기억 — 가려는 방향과 Grok Bot 조사

> 작성일: 2026-10-02
> 목적: 여러 에이전트가 방을 나눠 협업하고 기억을 쌓는 방향, 그리고 Grok Bot 이 그것을 어떻게 하는지 조사한 결과를 한 문서로 모아 다른 곳(다른 세션·컴퓨터·사람)과 공유한다.
> 상태: 논의 중 — **결정된 것과 제안·미정을 구분해 적는다.** 구현 계획서가 아니다.

## 개요

사용자가 "대화 중 에이전트를 자동으로 불러 쓰게 하는 것"을 논의하다 두 가지를 물었다.

1. 한 작업에 에이전트가 여럿(예: 디자인·개발·실측)이면, 서로 대화·협업하며 기억을 쌓게 할 수 있나.
2. 그런 협업을 Claude Code 세션에서 하는 것이 맞나, 화면(UI)을 따로 뽑는 것이 맞나.

그 사이 Grok Bot 리뷰 영상 요약(`docs/temp/그록봇 리뷰영상.pdf`)을 보고, 영상이 주장하는 "멀티 에이전트 + 인피니티 메모리" 구조를 웹에서 조사했다.

## 1. 지금 우리가 가진 것 (코드·문서로 확인)

| 조각 | 상태 |
| --- | --- |
| 에이전트별 방: `claude --agent <호출명> --name <방이름>` — 방의 메인 세션이 그 에이전트 자체 | 있음 (실측) |
| 에이전트별 기억: 세션 시작에 SOUL·기억·대화 요약 주입(각 4,096B 상한) | 있음 |
| 다른 방·옛 대화 검색: `hermes-agent.py recall <호출명> "<낱말>"` (읽기 전용, 허용 목록 등록) | 있음 (2026-10-01) |
| 인계 봉투: `goal` + `done_when` 강제, 받는 쪽이 검사하고 시작, 끝나면 기계가 `done_when` 을 다시 잼 | 있음 |
| 리뷰 → 기억: 일을 끝내면 위 직급에 리뷰 봉투, 지적이 일한 에이전트 기억에 남고 3회 반복되면 개인 스킬 | 있음 |
| **한 작업을 여러 에이전트가 공유하는 기록** | **없음** |
| **큰 일을 나눠 담당에게 배정하는 자동화** (`auto-owner-summon.md` 백로그) | **없음** |

## 2. 가려는 방향 (사용자 의도 + 제안)

### 사용자가 말한 것 (결정에 가까움)
- 에이전트를 나누고, 서로 채팅·협업하며, 기억을 쌓는 구조를 원한다.
- 한 작업에 에이전트는 대부분 한 명이지만, 디자인·개발·실측처럼 여럿이 필요한 작업도 있다.
- 방 하나에 에이전트 한 명이면, 처음 비용 뒤에는 에이전트를 다시 부르지 않고 그냥 대화해도 그 에이전트와의 대화다.

### 제안 (사용자 확정 전)
1. **한 작업에 에이전트 하나**: 그 에이전트의 방에서 일한다. 자동 소환보다 이쪽이 싸다.
2. **여러 에이전트**: 실시간 자유 대화보다 먼저 **"공유 작업 기록 + 인계 봉투를 순서대로 넘기기"**. 작업마다 기록 파일 하나(예: `.hermes/tasks/<작업>.md`)에 결정·결과를 한 줄씩 남기고, 각자 기억에는 자기 몫만 쌓는다. 조율은 사람이 하고 자동 분배는 뒤에 얹는다.
3. **자동 호출**: 모델 호출 없는 **규칙 매핑**(편집 파일 경로·쓴 도구로 담당 판정)으로 시작하고, 소환보다 **"이 일은 ○○ 방에서 하는 게 맞습니다"라고 안내**하는 경로를 먼저 만든다.
4. **엔진과 화면 분리**: 일하는 곳(엔진)은 Claude Code 세션(방), 여러 에이전트를 한눈에 보는 화면은 같은 파일을 읽는 얇은 층(`hermes-dashboard` 확장)으로 따로 둔다.
5. 화면을 `terminal-shipping` 에 넣지 않는다 — 그것은 컨테이너 수출 운송사용 별개 제품이다. 공장이 12개 프로젝트에 퍼뜨리는 기능을 한 제품에 묶게 된다.

### 미정 (답이 필요한 것)
- 협업 화면을 **사용자 혼자** 보는가, **다른 사람(팀·고객)도** 보는가. 혼자면 4번의 얇은 화면으로 충분할 가능성이 크고, 여럿이면 별도 앱을 검토한다. (근거 없음 — 답을 받아야 정해진다.)
- 에이전트들이 **순서대로 넘기는 일**이 많은가, **동시에 서로 묻는 일**이 많은가. 후자면 실시간 대화를 따로 설계해야 한다.

## 3. 비용 실측 (2026-10-01, 이 환경)

| 항목 | 값 |
| --- | --- |
| 빈 폴더(하네스 없음) 첫 호출 입력 | 약 6.0만 토큰 |
| 하네스·헤르메스 설치 프로젝트 첫 호출 입력 | 약 7.0만~9.1만 토큰 |
| `recall` 1회 | +765 ~ +2,100 토큰 (낱말을 한 번에 넣으면 +947, 낱말마다 따로 4번이면 약 +4,150) |
| 매 턴 주입 백로그 구획 줄이기 | −496 ~ −502 토큰 (같은 프로젝트·같은 질문 2회씩) |

- 모델은 매 호출마다 대화 전체를 다시 읽는다. 방이 소환보다 유리한 이유는 **소환은 일마다 새 컨텍스트(기본 입력 6만~9만)를 처음부터 만들고, 방은 한 컨텍스트가 이어져 앞부분이 캐시로 재사용되기** 때문이다. 방과 소환을 같은 일로 나란히 잰 측정은 **아직 없다**(구조에서 나온 추정).
- 캐시 읽기가 구독 사용량에서 어떻게 세어지는지는 확인하지 않았다.
- 세 에이전트가 실시간으로 말을 주고받으면 말이 오갈 때마다 양쪽이 전체 컨텍스트를 다시 읽어 토큰이 가장 빨리 늘고 끝나지 않는 대화의 위험이 있다.

## 4. Grok Bot 조사

### 출처와 신뢰도
- 영상 요약 PDF의 3~4쪽 "구조 분석"(오케스트레이터 + 그룹 챗 핸드오프, 계층형 메모리, 벡터 DB)은 영상 자막이 아니라 **요약 도구의 추측**이다. 근거로 쓰지 않는다.
- 아래는 웹 검색으로 찾은 **2차 자료**(xAI 글을 인용·정리한 것)다. xAI 1차 원문과 영상은 **직접 확인하지 못했다.**

### 확인된 것
| 항목 | 내용 |
| --- | --- |
| 단위 | 지속되는 이름 붙은 **봇**. 이름·직함·대화 기록·기억·도구·컴퓨터·루틴을 가진다. 다음 날 돌아와도 같은 역할. |
| 기억 범위 | 봇마다 따로. xAI 표현: "기억과 루틴은 그 역할이 시간이 지나며 아는 것·하는 것이라서 봇 개별 소유." 사용자 기록 전체를 하나의 큰 기억으로 합치지 않는다. (한 가이드는 팀 공유 기억도 있다고 써서 자료마다 다르다.) |
| 대화 기록 | 컴퓨터 밖에 저장 (Flocker 인용). |
| 파일·로그인 | 계정 단위 가상머신 하나를 모든 봇이 공유. 화면은 봇마다 따로여서 병렬 작업 가능 (Flocker). ZenML 은 "공유 방식은 설명되지 않았다"고 해 자료 간 충돌이 있다. |
| 스킬 | 계정 단위로 여러 봇이 공유. 화면 녹화로 가르치면 반복 가능한 자동화로 저장. |
| 그룹 | 봇 2~6개, 비동기 핸드오프. 그룹 채팅이 공유 프로젝트 맥락을 주고 각 봇은 전문 기억 유지. 봇→그룹 전달은 현재 텍스트만. |

### 공개되지 않은 것 (ZenML 이 xAI 글에서 명시적으로 짚음)
- 기억을 **고르고·요약하고·갱신하고·지우는 방법**.
- 핸드오프가 **구조화된 메시지·공유 상태·도구 호출·추가 모델 호출 중 무엇인지**.
- **충돌 해결, 무한 대화 방지, 예산 제한, 권한 확인.**
- 따라서 "계층형 메모리·벡터 DB·오케스트레이터 패턴"은 확인된 사실이 아니다. "인피니티 메모리"의 구현은 공개된 적이 없다.

### 우리와의 비교
- **같은 모양**: 기억은 에이전트별, 산출물은 공유 파일, 핸드오프는 봉투 + 공유 맥락.
- **우리가 이미 설계해 둔 것** (Grok Bot 에서 공개되지 않은 부분): 4KB 주입 + `recall` 검색의 비용 상한, 봉투 `done_when` 기계 검증, 리뷰 → 기억 적립.
- **가져올 만한 것**: 대화 기록을 작업 환경 밖에 두는 분리, 스킬은 팀 공유·기억은 개인 소유 규칙 — 우리 구조와 이미 비슷하다.
- **다른 점**: Grok Bot 은 클라우드 샌드박스 + UI 를 월 200달러대 플랜으로 묶어 비개발자에게 판다. 우리는 사용자 PC 의 Claude Code 구독 위에서 파일로 기억을 둔다.

## 5. 다음 단계 (제안)

1. 위 미정 두 가지에 사용자가 답한다.
2. 답에 따라 `docs/exec-plans/backlog/auto-owner-summon.md` 에 "공유 작업 기록 + 방으로 안내"를 목표 후보로 추가하고 계획서로 승격한다.
3. 방 vs 소환 토큰을 같은 일로 나란히 재서 소환이 정말 필요한지 정한다.
4. xAI 1차 글 확인이 필요하면 별도로 한다.

## 6. Meta Muse 와 논문 비교 (2026-10-02 추가)

### 용어
하나로 부르는 말은 없고 층마다 다르다(이 용어 목록은 기억에 의한 것이며 웹으로 확인하지 않았다): 공유 기억 = shared memory·블랙보드, 층을 나눈 기억 = 계층형 메모리, 컨텍스트 안/밖 분리 = MemGPT 방식, 기억 종류 = 단기·일화·의미·절차, 위에서 일을 나눔 = 오케스트레이터-워커·슈퍼바이저, 무엇을 컨텍스트에 넣을지 설계 = 컨텍스트 엔지니어링.

### Meta Muse (Meta 의 에이전트)
- 확인된 것(블로그형 기사 1건): 에이전트가 자기 컨테이너에서 돌고 기억·문서를 저장하며, 그룹 채팅(텔레그램 시험)에 넣으면 대화가 앱의 에이전트에도 이어진다. 사용자가 기억을 보고 지우고 더할 수 있다. 계층 없이 동료처럼 보였다고 한다. 샌드박스는 코어 2개·8GB.
- **확인되지 않은 것**: 기억이 에이전트별인지 공유인지, 계층형인지, 중앙 저장소인지. 기사 저자도 "블랙박스"라 했다.
- 검색에 섞여 나온 "Spark" 공유 메모리 서비스와 MUSE-Autoskill 논문은 이름만 비슷한 별개 프로젝트로 보이며, Meta Muse 의 구조가 아니다. Muse Spark 의 "멀티 에이전트"는 한 질문을 병렬로 추론하는 방식으로 기억 구조와 다른 이야기다.

### 논문 (원문 PDF 를 직접 열어 확인. 읽기 도구의 요약은 MIRIX 기억 종류를 3개로 잘못 말해 원문으로 고쳤다)

| | MemGPT (arXiv 2310.08560) | MIRIX (arXiv 2507.07957) |
| --- | --- | --- |
| 핵심 | 컨텍스트를 램, 바깥 저장소를 디스크처럼 다룬다 | 기억 6종류 + 종류별 관리 에이전트 6개 + 작업을 나눠 주는 Meta Memory Manager |
| 구조 | 메인 컨텍스트(시스템 지시·작업 기억·최근 대화 큐) + 외부 저장소(대화 기록 검색, 임의 텍스트 읽기/쓰기 DB) | Core · Episodic · Semantic · Procedural · Resource · Knowledge Vault |
| 기억을 누가 관리 | LLM 이 함수 호출로 스스로 | 관리 에이전트들이 쓰고 대화 에이전트가 읽는다 |
| 넘칠 때 | "memory pressure" 경고 → 가득 차면 오래된 메시지 일부를 내보내고 재귀 요약으로 대체 | 의미 기억을 트리로 정리, 큰 자료는 클라우드로 |
| 꺼내기 | 모델이 검색 함수 호출 | Active Retrieval: 답하기 전에 모델이 주제를 만들고 찾은 것을 시스템 프롬프트에 넣음 |
| 보고된 성능 | 10만 토큰 이상 대화에서 품질 유지 | ScreenshotVQA 에서 RAG 보다 정확도 35%↑·저장 99.9%↓, LOCOMO 85.4% |

### 우리 구조와의 대응
| 논문 개념 | 우리 | 차이 |
| --- | --- | --- |
| 메인 컨텍스트 | 세션 시작 주입(SOUL·기억·요약 각 4,096B 상한) | 고정 상한. 넘침 경고·자동 내보내기 없음 |
| 외부 저장소 검색 | `recall` (낱말 점수, 읽기 전용) | 모델이 필요할 때 부른다 |
| Episodic / Semantic / Procedural / Core | 대화 요약 / `memory.jsonl` / 결정화 스킬 / SOUL | 대응 |
| Resource | git 파일 | 별도 기억 종류 없음 |
| Knowledge Vault | 저장하지 않음(비밀·개인 문장은 쓰기 전에 걸러냄) | 의도적으로 다름 |
| 기억을 누가 쓰나 | 훅·CLI 가 쓰고 에이전트는 `note` 로 가끔 | MemGPT 와 반대 |

### 알게 된 것
1. **MIRIX 의 "multi-agent" 는 한 사용자의 기억을 여럿이 나눠 관리하는 구조**이지, 디자인·개발·실측 같은 작업 에이전트가 기억을 공유하며 협업하는 구조가 아니다. 두 논문 모두 **작업 에이전트 간 공유 작업 기록**은 다루지 않아(읽은 범위), §2 의 "공유 작업 기록 + 봉투 릴레이"는 우리가 설계해야 한다.
2. "중앙 기억 + 작업 분배"에 가장 가까운 것은 MIRIX 의 Meta Memory Manager(라우터)이고, 우리 쪽 대응은 백로그 `auto-owner-summon.md` 의 "작업 → 담당 자동 연결"이다.

### 가져올지 판단(제안)
- MemGPT 의 압력 경고·자동 요약: 밀린 것은 `recall` 로 찾으므로 당장 불필요.
- MIRIX 의 Active Retrieval(매 단계 자동 검색): 우리가 잰 `recall` 1회가 +765~+2,100 토큰이라 매 턴이면 부담이 크다. **필요할 때만 부르는 지금 방식 유지**를 권한다. 논문 쪽 비용은 읽은 범위에서 확인하지 못했다.
- 한계: 두 논문의 본문 전체가 아니라 핵심 대목을 찾아 읽었다. MIRIX 의 충돌 처리·검색 세부는 확인하지 못했다.

## 7. cumora — 에이전트끼리 대화의 토큰을 어떻게 막았나 (2026-10-02 추가)

cumora 는 사람과 영속 에이전트가 함께 쓰는 팀 채팅이고, GitHub 에 공개돼 있으며 내 PC 의 Claude Code·Codex 등을 직접 연결(BYOA)할 수 있다. 소스 문서 `docs/COORDINATION.md` 를 직접 읽어 확인했다. 우리 저장소의 `docs/hermes-universe` 도 cumora 에서 여러 교훈(K-1~K-9)을 가져온 바 있다.

**토큰을 줄이는 한 가지 비법은 없고, 큰 모델을 깨우는 횟수를 줄이는 문지기들이었다.**

| 장치 | 하는 일 | 효과 |
| --- | --- | --- |
| 작은 모델 문지기(triage gate) | 값싼 모델(haiku급)이 "큰 모델이 답할 일이 있나"를 먼저 판정. 근거는 **메시지 문장이 아니라 DB 사실**(작업 기록의 담당, 사람의 관심 신호, 연속 대화 바닥선). 사람이 관련되었거나 기다리면 항상 실행, 열린 일 없는 에이전트끼리 잡담은 억제 | 잡담에 큰 모델을 깨우지 않음 |
| seen-cursor 신선도 문지기 | 답을 올리기 직전에 새 메시지가 있으면 답을 보류하고 새 메시지를 보여 다시 판단하게 함. 보류 후 기준선을 앞으로 옮겨 무한 반복 방지 | 낡은 맥락의 답이 연쇄를 만드는 것을 막음 |
| 원자적 일 선점 + 동일 문장 롤백 | 일은 한 명만 잡고, 직전 상대 메시지와 같은 초안은 서버가 롤백. `--send-anyway` 우회 불가 | 중복 작업·되풀이 방지 |
| 동시 실행 상한·속도 조절 | 큰 모델 동시 6개(조이려면 2~4), 작은 모델 8개, 실행 간격 500ms, 제한에 걸리면 간격 2배(최대 8초), 정체 알림 3번 거절 시 침묵, 에이전트별 60초 쿨다운 | 구독 한도 충돌 방지 |
| 비용 장부 | 모든 모델 호출을 `llm_calls` 한 곳에 기록 | 새는 곳이 보임 |

**확인하지 못한 것**: "속삭임(whisper) 방"의 구현(검색 요약은 "에이전트끼리 DM 을 바깥에서 읽는 방"이라고만 함), 에이전트별 컨텍스트 크기·요약 전략·방별 토큰 예산, 실제 절감량 수치. 소개 글 저자도 이 통제들이 "지연·비용·신뢰해야 할 정책을 더한다"고 하며, 에이전트 팀이 단일 에이전트보다 낫다는 독립 증거는 없다고 말한다.

**우리에게**: §2 에서 처음부터 설계해야 한다고 한 "누가 답할지·연속 응답 상한·예산" 중 *누가 답할지*를 cumora 는 싼 모델이 *작업 기록 같은 기계적 사실*로 판정하게 풀었다. 우리 기존 결정("요청 문장을 모델로 판별하지 않는다")과 정신이 같고(문장이 아니라 사실), 모델 호출을 아예 없애는 쪽(규칙 매핑)과 싼 모델 문지기 쪽 중 무엇을 택할지는 미정이다.


## 8. Gemini 방식 (2026-10-02 추가)

"Gemini 가 그렇게 한다"는 말이 무엇을 가리키는지(cumora 식 문지기인지, 토큰 절감인지, 에이전트 협업인지) 불분명해 세 갈래를 모두 조사했다. **cumora 식의 "작은 모델이 큰 모델 깨울지 판정" 장치를 Gemini 가 쓴다는 근거는 찾지 못했다.** 아래는 대부분 2차 자료(블로그·정리 글)이며, 1차로 직접 읽은 것은 A2A 발표 글과 Interactions API 소개 글 두 건이다.

| 갈래 | 내용 | 확인 수준 |
| --- | --- | --- |
| 토큰 절감: 컨텍스트 캐싱 | 고정된 긴 컨텍스트의 처리 결과를 저장해 두고 뒤 요청은 새로 붙는 부분만 처리. 캐시된 입력 토큰이 약 90% 싸다는 설명(Gemini 3.1 Pro 100만 토큰당 2.00달러 → 0.20달러) | 2차 블로그 |
| 토큰 절감: Interactions API | 대화 내용을 서버가 저장하고 ID 로 참조해 새 메시지만 보낸다. "암묵적 캐싱"으로 토큰·지연이 준다고 주장하나 **수치 없음**, 실험 기능 | 1차에 가까운 소개 글, 효과는 저자 주장 |
| 협업: ADK 서브에이전트 | 일꾼마다 컨텍스트를 좁혀 주고 작업 난이도로 라우팅. 파이프라인의 에이전트들이 `session.state` 를 공유. 순차·반복 실행용 오케스트레이터 에이전트 | 2차 |
| 협업: Gemini CLI 서브에이전트 | 병렬로 여러 개를 띄워 각자 컨텍스트에서 일하고 결과를 합침. "서브에이전트는 토큰·지연을 더 쓰고 대신 컨텍스트가 깨끗하고 신뢰성이 높다. 잘게 쪼개지 말고 굵게 몇 개" | 2차 |
| 프로토콜: A2A(Agent2Agent) | 에이전트끼리 말하는 열린 표준(HTTP·SSE·JSON-RPC). **Agent Card**(능력·엔드포인트·인증을 적은 JSON), **Task**(고유 ID 와 생애주기를 가진 일 단위), **Message**(Part 로 내용 전달), 산출물. 장기 작업은 상태를 서로 맞춘다 | 1차(발표 글) |
| 제품: Gemini Enterprise | 팀이 에이전트를 만들고 공유하고, 에이전트가 서로 일을 위임. Memory Bank 로 세션 간 장기 기억 | 2차 |

**A2A 가 정하지 않은 것(발표 글에 없음)**: 에이전트 간 토큰 비용 분담, 순환 의존 같은 **루프 방지**, 에이전트 간 **공유 기억**, 사용량 제한, 실패 시 대체 동작. 즉 가장 큰 협업 표준도 우리가 걱정하는 비용·루프 문제를 구현자에게 맡겼다.

**우리와의 관계**
- Gemini 의 절감은 **공급사가 제공하는 캐싱**이다. 협업 로직으로 줄이는 cumora 와 층이 다르다. Claude 에도 캐시가 있고, 이번 측정에서 첫 호출 입력 중 캐시 읽기가 이미 큰 비중이었다(예: 70,530 중 약 27,000 읽기·약 43,000 생성). 우리가 쓰는 구독 CLI 에서 이를 따로 조절할 수단이 있는지는 확인하지 못했다.
- A2A 의 **Agent Card 는 우리 명부 항목(이름·분야·직급·SOUL)과, Task 생애주기는 우리 인계 봉투(`goal`·`done_when`·되돌아오는 네 방식)와 모양이 비슷**하다. 새 표준을 따를 필요는 없지만, 나중에 다른 제품의 에이전트와 말해야 할 때의 참고 형식이다.
- 검색에 "공유 에이전트 메모리는 최고의 조율 수단이자 최대의 공격 표면"이라는 제목의 글들이 보였다(본문은 읽지 않았다). 공유 작업 기록을 설계할 때 한 에이전트가 쓴 내용을 다른 에이전트가 그대로 믿는 위험을 따로 보아야 한다는 신호로만 적어 둔다.

## 출처

- [cumora README (GitHub)](https://github.com/MaskedKM/cumora)
- [cumora docs/COORDINATION.md](https://raw.githubusercontent.com/MaskedKM/cumora/my-custom/docs/COORDINATION.md)
- [DEV — Cumora Makes Agent Coordination the Product](https://dev.to/dd8888/cumora-makes-agent-coordination-the-product-not-a-chat-feature-5h8d)
- [Script by AI — Cumora: Team Chat for Humans and Persistent AI Agents](https://www.scriptbyai.com/cumora-team-chat/)
- [Google Developers Blog — Announcing the Agent2Agent Protocol (A2A)](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)
- [Agno — Cut multi-turn token costs with Gemini's Interactions API](https://www.agno.com/articles/cut-multi-turn-token-costs-with-geminis-interactions-api)
- [Redlinesoft — Context Caching for Gemini 3 Multi-Agent Clusters](https://blog.redlinesoft.net/posts/context-caching-revolution-gemini-3/)
- [InfoQ — Subagents in Gemini CLI](https://www.infoq.com/news/2026/04/subagents-gemini-cli/)
- [Google Cloud — The new Gemini Enterprise](https://cloud.google.com/blog/products/ai-machine-learning/the-new-gemini-enterprise-one-platform-for-agent-development)
- [Stark Insider — Meta Muse: Our AI Agent Told Meta's AI About Me](https://www.starkinsider.com/2026/09/meta-muse-multi-agent-household-trust.html)
- [Tom's Hardware — Meta Muse runs agents on AMD EPYC Turin hosts](https://www.tomshardware.com/pc-components/cpus/meta-muse-runs-agents-on-amd-epyc-turin-hosts-with-two-cores-and-8gb-of-memory-ai-agent-can-pass-terminal-commands-to-ubuntu-host-system)
- [MemGPT: Towards LLMs as Operating Systems](https://arxiv.org/pdf/2310.08560)
- [MIRIX: Multi-Agent Memory System for LLM-Based Agents](https://arxiv.org/pdf/2507.07957)
- [ZenML — Designing Persistent, Multi-Agent Workflows for Grok Bot](https://www.zenml.io/llmops-database/designing-persistent-multi-agent-workflows-for-grok-bot)
- [Flocker — Grok Bot Workspaces and Specs](https://flocker.md/blog/grok-bot-roles-workspace-and-specs/)
- [mem0 — Grok Bot Guide](https://mem0.ai/blog/grok-bot-guide)
- [Composio — Guide to Grok Bot](https://composio.dev/content/guide-to-frok-bot)
- [InfoQ — SpaceXAI Launches Grok Bot](https://www.infoq.com/news/2026/08/grok-bot-agent/)
- [Superpower Daily — xAI Explains How Grok Bot Is Built](https://superpowerdaily.com/posts/xai-explains-how-grok-bot-is-built-to-keep-agents-working-between-chats)
- 내부: `docs/exec-plans/backlog/auto-owner-summon.md` · `docs/exec-plans/completed/2026-09-28-hermes-chat.md` · `docs/exec-plans/completed/2026-10-01-agent-recall.md` · `docs/exec-plans/completed/2026-10-01-per-turn-injection-trim.md`
