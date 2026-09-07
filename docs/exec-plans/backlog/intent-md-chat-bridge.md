# intent-md-chat-bridge — 비개발자용 intent.md 생성 경로

## 배경

YouTube 영상 「Anthropic 제안한 코드 짜기 전에 무조건 쓰라는 파일 | AI 네이티브 SDLC 도입 정리」
(`docs/videos/2026-09-05-intent-md-ai-native-sdlc/`) 검토 대화에서 사용자가 원래 이 영상에서
가장 좋아 보였다고 짚은 부분 — "누구든 의견을 내면 자동으로 티켓/문서가 생기는 것" — 을
더 정확히 분해한 결과.

## 무엇을 하려는 것인가

Claude와 대화하면 `intent.md`를 자동 생성해주는 스킬 하나를 만드는 것 자체는 간단하다.
문제는 접근 경로다:

- **Claude Code/CLI에 접근 가능한 사람** (개발자 등) → 로컬에서 스킬로 바로 대화하면 됨.
  채팅앱을 거칠 이유가 없음.
- **Claude에 직접 접근할 수 없거나 익숙하지 않은 사람** (디자이너, 기획자, CS 등) →
  이미 매일 쓰는 Slack/Telegram 같은 채팅앱 안에서 `@claude` 태그만 하면 되는 경로가 필요.
  이 사람들에게 "새 도구(Claude Code) 배워서 써라"는 진입 장벽이 됨.

즉 Slack/Telegram 연동이 필요한 이유는 "여러 도구를 쓰기 위해서"가 아니라
**비개발자의 진입 장벽을 없애기 위해서**다. 영상 원본 설계(28:50, §6)도 동일한 이유로
Slack 태그 → 에이전트가 `intent.md` 초안 작성 → GitHub PR 흐름을 택했다.

## 왜 지금 만들지 않는가

1. **이 프로젝트는 단독 개발이다.** `intent-md-ai-native-sdlc.md` 431줄에 이미 기록된 대로,
   비개발자 진입 경로 자체가 필요 없는 상태 — 만들 사람이 없다.
2. **연동 인프라 비용이 든다.** Slack/Telegram 봇 등록, 웹훅 수신 서버, 인증·권한 관리 등
   실제 구현·유지보수 비용이 발생한다.
3. **intent.md 자체를 아직 이 프로젝트에 도입하지도 않았다.** 파일 생성을 자동화하기 전에,
   애초에 이 프로젝트의 `docs/exec-plans/` 체계와 intent.md가 겹치는지·필요한지부터
   결정이 안 된 상태 (2026-09-07 intent.md 논의에서 도출: exec-plan 템플릿이 이미
   intent+spec+plan 내용을 한 파일에 담고 있음).

## 착수 조건 (제안)

아래 중 하나가 실제로 발생하면 exec-plan으로 승격 검토:

- 이 프로젝트(또는 이 하네스 프리셋을 쓰는 다른 프로젝트)에 코드베이스를 모르는
  협업자(디자이너·기획자·CS 등)가 실제로 합류함
- intent.md 스타일 문서를 이 프로젝트에 도입하기로 결정됨 (별도 판단 필요)
- Claude Code/CLI 없이 의견만 내고 싶다는 실제 요청이 1건 이상 발생함

## 참고

- 원본 논의: 2026-09-07 대화 (intent.md 영상 검토 중 파생)
- 관련 문서: `docs/videos/2026-09-05-intent-md-ai-native-sdlc/intent-md-ai-native-sdlc.md`
  §6 (28:50 전체 아키텍처), 431줄 (비개발자 진입 경로 공백 기록)
- 관련 backlog: `docs/exec-plans/backlog/agent-eval-regression.md` (같은 대화에서 도출된
  별개 후보)
