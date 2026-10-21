# 기획(PM) 스킬 저장소 4곳 검토

> 작성일: 2026-10-21
> 목적: 쇼츠 「2026년 개발자들이 선택한 오픈소스 TOP4」(MINDUNG) 가 소개한 저장소 4곳 중 공장에 들일 스킬을 가린다.

## 개요

- 4곳 모두 2026-10-15 ~ 10-20 에 커밋이 있는 활발한 저장소다. SKILL.md 합계 289개.
- **통설치(플러그인·setup)는 4곳 모두 하지 않는다.** 스킬 수십 개가 한꺼번에 들어와 우리 스킬과 발동을 다투고, 일부는 훅·자동 업데이트·텔레메트리를 함께 깐다.
- 들일 것은 **폴더 단위로 골라 한국어로 고쳐 `assets/skills/` 에 넣는다.** 후보 3개 + 기존 에이전트 보강 1건.
- 조사 방법: 각 저장소를 얕게 복제(실행 없음) → 저장소별 조사 에이전트 → 결론을 좌우하는 주장(라이선스·훅·네트워크)을 grep 으로 직접 재확인.

## 저장소별 판정

| 순위 | 저장소 | 라이선스 | 스킬 수 | 위험 요소 (직접 확인) | 판정 |
|---|---|---|---|---|---|
| 1 | `phuryn/pm-skills` | MIT | 69 | 훅·스크립트 없음. 명령 `ship-check` 가 CLAUDE.md 를 고침 | 3개 골라 들임 |
| 2 | `product-on-purpose/pm-skills` | Apache-2.0 | 68 | `hooks/hooks.json` 에 PreToolUse(편집 시 긴 대시 차단)·SessionStart(스킬 추천 주입) 훅. `utility-update-pm-skills` 가 curl·wget 으로 받아 덮어씀 | 1개 일부만 차용 |
| 3 | `deanpeters/Product-Manager-Skills` | **CC BY-NC-SA 4.0** | 77 | 실행 위험 없음 | **들이지 않음** — 비영리·동일조건이라 MIT 공장에 섞을 수 없음 |
| 4 | `garrytan/gstack` | MIT | 60 | setup 이 전역 `~/.claude/settings.json` 에 훅 등록, 매시간 GitHub 업데이트 확인, 동의 시 Supabase(`frugpmstpnojnhfyimgv.supabase.co`)로 사용 기록 전송, 리뷰 내용을 OpenAI codex 로 보냄, 스킬마다 약 400줄 공통 서두 | openclaw판 1개만 고쳐 들임 |

## 들일 후보

| 후보 | 출처 | 하는 일 | 우리 흐름에서 자리 |
|---|---|---|---|
| office-hours | gstack `openclaw/skills/gstack-openclaw-office-hours/SKILL.md` (373줄, 런타임 참조 0) | 만들기 전에 "누가 이 문제를 겪나·지금은 어떻게 버티나·가장 좁은 시작점" 등 6문항으로 몰아붙이고 대안 2~3개를 강제 | brainstorming 앞. superpowers brainstorming 은 아이디어를 넓히는 쪽이라 겹치지 않음 |
| PRD 작성 | phuryn `pm-execution/skills/create-prd/` (97줄) 바탕 + product-on-purpose `deliver-prd` 의 "Agent Execution Contract" 칸 | 질문 최대 3개, 모르는 것은 지어내지 않고 「가정·열린 질문」 칸으로 보냄. 요구사항마다 검증 방법을 적음 | ui-prototype 의 입력 문서. 지금은 이 앞 단계가 비어 있음 |
| intended-vs-implemented | phuryn `pm-ai-shipping/skills/intended-vs-implemented/` (42줄) | 문서의 의도를 인용하고 코드 위치를 대며 어긋남을 찾음. "적혀만 있고 강제 안 됨" 도 결함으로 셈 | 구현 뒤 검증. exec-plan §2 목표 대조(R-acc)와 맞물림 |
| (에이전트 보강) strategy-red-team | phuryn `pm-execution/skills/strategy-red-team/` (72줄) | 핵심 주장마다 "이러면 무너진다" 를 적고 가장 싼 시험·중단 기준을 정함 | 새 스킬이 아니라 devil-advocate 에이전트에 절차로 흡수 |

차용 시 지킬 것:
- office-hours 끝의 Y Combinator 지원 권유 문구(360~364줄)를 지운다. 설계 문서는 `~/.gstack/` 대신 저장소 `docs/` 에 저장한다.
- Apache-2.0 차용분은 출처 주석을 남긴다. MIT 차용분은 저작권 줄을 남긴다.
- phuryn 스킬 끝의 뉴스레터 「Further Reading」 링크와 다른 스킬 이름 참조는 뺀다.

## 들이지 않는 것과 이유

- **영상이 3위로 소개한 `prioritization-advisor` (deanpeters):** 라이선스가 맞지 않는다. 게다가 백로그에 점수를 매기는 스킬이 아니라 "어느 틀(RICE·ICE…)을 쓸지" 고르는 462줄짜리 안내이고, 팀·조직을 전제로 한다.
- **영상이 2위로 소개한 Discover→Define→Deliver 묶음:** PRD 칸 하나만 차용한다. 나머지 75줄짜리 정의 스킬은 템플릿을 감싼 틀이다.
- **전략·시장·마케팅 틀 (SWOT·PESTLE·Porter·Ansoff·캔버스류):** 절차 없이 칸만 채우는 양식이다. 1인 개발 흐름에서 쓸 자리가 없다.
- **팀 의식 (회고·스프린트·회의·이해관계자·OKR·디자인 스프린트):** 팀을 전제로 한다.
- **우리와 겹치는 것:** 코드 리뷰(code-reviewer·/code-review), 디버깅(systematic-debugging), 스킬 제작(skill-creator), 학습·기억(헤르메스), 브라우저 QA(webapp-testing·playwright), 디자인(impeccable·ui-prototype), 위험 명령 보호(우리 훅).
- **gstack 본체 전부:** 전역 훅·자동 업데이트·외부 전송·Chromium 빌드는 12개 프로젝트에 까는 공장과 맞지 않는다. 스킬 한 번 부를 때마다 공통 서두에만 약 8k 토큰이 든다.

## 원본 위치

검토용 복제본은 작업 임시 폴더에 있었고 작업이 끝나면 지워진다. 다시 볼 때는 각 저장소를 `git clone --depth 1` 한다.
