# 개인 기억과 팀 지식 — 다른 도구는 어떻게 나누나 (조사)

> 작성일: 2026-09-28
> 목적: 헤르메스 기억 운반의 "누가 보나" 설계(C-30 후보)를 정하기 전에, Claude Code 와 다른 AI 도구가 개인 기억·팀 지식을 어떻게 나누고 누가 보게 하는지 사례로 확인한다.
> 방법: 공식 문서 조사 두 갈래(Claude Code 문서 · 웹 검색). OpenAI 도움말은 403 이라 검색 발췌에 기댄 항목을 "(발췌)" 로 표시. 확인 못 한 것은 **미확인**.

## 개요

계기(사용자, 2026-09-28): "특정 한 명이 대화한 내용은 그 사람만 보게 하고, 공통되는 것은 같이 보이게 하면 되잖아." → 결정을 미루고 업계 사례부터 본다.

**결론 한 줄:** 조사한 도구는 모두 **자동으로 쌓이는 기억 = 개인**, **공유 지식 = 사람이 명시적으로 올린 것**으로 나눈다. "누가 보나" 는 **계정 권한(ACL)** 으로 정하고, **암호화로 가르는 도구는 찾지 못했다.** Claude Code 는 개인 기억을 컴퓨터 사이로 옮기는 기능 자체가 없다.

## 1. Claude Code (공식 문서)

| 무엇 | 위치 | 팀 공유 | 다른 컴퓨터로 |
|---|---|---|---|
| 관리자 정책 CLAUDE.md · managed settings | OS 경로(`/etc/claude-code/…`) | 조직 전체에 강제 | 관리자가 배포 |
| 프로젝트 `CLAUDE.md` · `.claude/settings.json` | 저장소 | **git 커밋 = 공유** | git |
| `CLAUDE.local.md` · `.claude/settings.local.json` | 저장소(gitignore) | 개인 | 안 감 |
| `~/.claude/CLAUDE.md` · 사용자 설정 | 홈 | 개인(모든 프로젝트) | 안 감 |
| 자동 메모리 | `~/.claude/projects/<프로젝트>/memory/` | 개인(같은 저장소 워크트리끼리만) | **안 감 — 동기화 기능 없음** |
| 대화 기록 | `~/.claude/projects/<프로젝트>/<세션>.jsonl` | 개인 | **안 감**(로컬, 기본 30일 뒤 삭제) |

- "Project instructions are shared with your team through version control, so focus on project-level standards rather than personal preferences." — https://code.claude.com/docs/en/memory.md
- 자동 메모리: "Each project gets its own memory directory at `~/.claude/projects/<project>/memory/`." — 같은 문서. 서브에이전트는 부모의 자동 메모리를 받지 않는다(fork 만 예외).
- 대화 기록은 로컬에만, 컴퓨터·클라우드 사이 공유 없음 — https://code.claude.com/docs/en/sessions.md
- 저장소 밖 경로를 `@import` 하는 프로젝트 CLAUDE.md 는 처음 읽을 때 승인 창(남이 커밋한 파일 보호).

## 2. 다른 도구

| 도구 | 개인 기억 | 공유 지식 | 누가 보나(통제) | 개인 → 공유 |
|---|---|---|---|---|
| ChatGPT | 계정에 묶임, 워크스페이스 안에서도 남에게 안 옮겨짐 (발췌) | Shared Projects(서버 객체) | 프로젝트 멤버십·역할 | 공유 프로젝트는 **project-only memory 강제** — 개인 기억을 못 읽음 (발췌) |
| Cursor | User Rules(설정) · Memories(1.0, 프로젝트별 개인, 승인 후 저장 — 2.1 에서 사라졌다는 보고, 공식 공지 **미확인**) | `.cursor/rules`(git) · Team Rules(대시보드, Team 요금제) | 저장소 권한 · 팀 계정, 관리자 "Enforce" | 사람이 파일로 커밋하거나 대시보드에 등록 |
| GitHub Copilot | Memory **사용자 수준 선호**(나만, 모든 저장소) | Memory **저장소 수준 사실**(기여자 모두) · `.github/copilot-instructions.md`·AGENTS.md(git) · 조직 지시문 · Spaces | 저장소 권한 · Spaces 역할, 보는 사람이 접근 가능한 소스만 | **저장할 때 범위 표시**(2026-05-26~), 저장소 사실은 쓰기 권한자 행동으로만, 28일 미사용 삭제 |
| Windsurf | 자동 기억, 워크스페이스별 · 공유 안 됨 (로컬 경로는 제3자 글, **미확인**) | `.windsurf/rules`(git) · 시스템 규칙(Enterprise, OS 경로) | 파일시스템·git 접근 | 기억은 커밋 안 됨 — 사람이 규칙 파일로 옮겨 적어야 공유 |
| Slack AI · Notion AI · Glean | — | 따로 만들지 않음 | **원본 ACL 을 질의 시점에 적용**(권한 인지형 검색) | — |
| Gemini Gems | (조사 안 함) | Gem 공유 = Drive 기술·권한 | Drive 권한 · 관리자 켜기/끄기 | 명시적 공유 |

출처: ChatGPT https://help.openai.com/en/articles/9295112-memory-faq-business-version · https://help.openai.com/en/articles/10169521-projects-in-chatgpt ·
Cursor https://cursor.com/docs/rules · https://cursor.com/changelog/1-0 · https://forum.cursor.com/t/custom-modes-and-memories-gone-in-2-1/143744 ·
Copilot https://docs.github.com/en/copilot/concepts/agents/copilot-memory · https://github.blog/changelog/2026-05-26-copilot-memory-has-more-controls-for-deletion-scope-and-the-copilot-cli/ · https://docs.github.com/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot · https://docs.github.com/en/copilot/how-tos/provide-context/use-copilot-spaces/collaborate-with-others ·
Windsurf https://docs.devin.ai/windsurf/plugins/cascade/memories ·
Slack https://slack.com/help/articles/28310650165907-Security-for-AI-features-in-Slack · Notion https://www.notion.com/help/notion-ai-connectors · Glean https://www.glean.com/perspectives/security-permissions-aware-ai ·
Gems https://workspaceupdates.googleblog.com/2025/09/gem-sharing-gemini-app-workspace.html

## 3. 공통 패턴

1. **공유 지식은 명시적으로 둔다** — git 파일(규칙·지시문·AGENTS.md) 또는 서버 조직·워크스페이스 객체. 어느 쪽이든 **사람이 쓰고 사람이 올린다.**
2. **자동으로 쌓이는 기억은 기본이 개인** — 계정 서버 저장(ChatGPT·Copilot 선호) 또는 로컬(Windsurf·Claude Code). 예외인 Copilot 저장소 사실도 저장할 때 범위를 표시한다.
3. **"누가 보나" 는 계정 ACL** — 저장소 권한·프로젝트 멤버십·Drive 권한·원본 ACL 의 질의 시점 적용. **암호화로 가르는 사례는 못 찾았다.**
4. **개인 → 공유는 명시적이고, 공유 공간은 개인 기억을 구조적으로 못 읽는다**(ChatGPT project-only memory).
5. **관리자 층** — 조직 규칙 강제(Cursor Enforce · Windsurf 시스템 규칙), 기억 일괄 삭제·내보내기(Copilot), 공유 켜기/끄기(Gems · ChatGPT).

## 4. 헤르메스에 대입하면 (제안 — 결정 아님)

| 업계 패턴 | 헤르메스 지금 | 차이 |
|---|---|---|
| 공유 지식 = 사람이 올린 git 파일 | SOUL · 명부 · 스킬 · 공통 결정화 스킬(git) | **같다** |
| 자동 기억 = 개인 | 대화 요약·기억·이력을 운반으로 **저장소에** 올림(평문, 비공개 저장소) | 개인 기억이 **저장소 읽는 사람 모두에게** 보인다 — 업계와 다름. 단 빈틈이 아니라 **이미 정한 설계**: T-18(2026-09-20) "읽을 권리 = 저장소 접근권, 비공개 저장소는 평문 운반" |
| 통제 = 계정 ACL(서버) | 서버가 없다 — git 저장소 권한뿐 | 사람 단위 ACL 을 걸 곳이 없다 |
| 개인 → 공유는 명시적 승격 | C-26 승격(허가) | **같다** |
| 개인 기억의 기기 간 이동 | 운반(git refs) | Claude Code 에는 없는 기능. ChatGPT·Copilot 은 계정 서버라 가능 |

- 헤르메스는 **서버 없이 git 저장소만** 쓰므로, 업계처럼 "계정 ACL 로 나만 보기" 를 할 곳이 없다. 같은 효과를 내는 방법은 둘:
  - **(가) 개인 기억은 저장소에 올리지 않는다**(Claude Code·Windsurf 방식) — 가장 단순. 대신 컴퓨터를 바꾸면 개인 기억이 안 따라간다.
  - **(나) 개인 기억은 주인의 열쇠로 암호화해 올린다** — 업계엔 사례가 없지만 서버 없는 환경에서 "나만 보기 + 컴퓨터 이동" 을 둘 다 얻는 방법. 이미 있는 잠금 모드 열쇠(`hermes-keys.sh`)를 개인 조각에만 쓰는 모양. 지금 잠금 모드는 **기본이 아니라 옵션**(T-18)이고 전부를 잠근다.
  - **(다) 사람별로 운반 칸(ref)이나 원격을 나눈다** — 예: `refs/hermes/sync/<사람>` 또는 개인 비공개 저장소를 기억 전용 원격으로. 단 운반을 `refs/hermes/sync` **하나로** 모은 T-07 과 부딪힌다(기본 fetch·브랜치 목록에 끼지 않고 저장소 비대를 막으려던 결정). 또 같은 저장소 안의 ref 는 읽기 권한을 나눌 수 없어, 개인 비공개 원격이 아니면 "나만 보기" 가 되지 않는다.
- 이 셋 중 무엇이든 **T-18 을 다시 여는 결정**(C-30 후보)이 된다 — 지금 설계는 "저장소를 읽을 수 있는 사람 = 기억을 읽어도 되는 사람" 이다.
- 공통으로 가져올 것: **저장할 때 범위를 표시**(Copilot — 개인/저장소), **공유 공간은 개인 기억을 못 읽게**(ChatGPT), **주인 표시**(누구의 대화인지 — git 사용자는 이름표일 뿐 신원 증명 아님).

## 관련

- `docs/hermes-sync-guide.md` "에이전트의 지식은 어디까지 따라가나"
- `docs/hermes-universe/decision-log.md` T-07(운반 칸 하나) · T-17~T-21(운반 — T-18 이 기본을 평문으로) · C-20(기억 본문 암호화 — T-18 뒤로 잠금 모드에만 적용. 원장 C-20 행에는 이 갱신 표시가 없다) · C-26(승격) · C-29(대화 요약 에이전트별)
- 리뷰: architect-lite(2026-09-28) — 사실 오류 없음, T-18·T-07 을 미정처럼 쓴 프레이밍 2건 반영
