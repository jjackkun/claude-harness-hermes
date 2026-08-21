# 스킬 호출 축 — 생성기가 스킬 자신의 발동 조건과 반대로 말한다

> 작성일: 2026-08-21
> 목적: 설치본 `CLAUDE.md` 가 스킬을 *"특별·대형 작업 시"* 로 소개해,
> 스킬 스스로 정한 발동 조건(*"코드를 쓰기 전에 항상"*)을 덮어쓰는 것을 고친다.
> 계기: 설치본(terminal-shipping)에서 실제로 발생한 위반 — §1-3
> 관련: [`2026-08-21-responsibility-over-linecount-design.md`](./2026-08-21-responsibility-over-linecount-design.md) §3.3

## 1. 동기 (Why)

### 1-1. 두 문장이 정면으로 어긋난다

전부 코드에서 확인한 사실이다.

```bash
lib/claude_md_gen.sh:48
  echo "- **스킬** (특별·대형 작업 시 직접 호출): \`$skills_dir\` — ${_skills[*]}"
```

```yaml
assets/skills/structured-file-layout/SKILL.md
  description: Use when creating new files, planning features, or writing
               exec-plans — before any code is written
```

```
생성기가 말하는 것   특별하고 큰 작업일 때만 부른다
스킬이 말하는 것     새 파일을 만들기 전에는 언제나 부른다
```

★ **생성기 쪽이 이긴다.** `CLAUDE.md` 는 매 세션 컨텍스트에 들어가고,
`SKILL.md` 본문은 **호출해야만** 로드되기 때문이다.

### 1-2. 🔴 순환 — 발동 조건을 읽으려면 이미 읽었어야 한다

```
스킬을 언제 부르나  →  그 답이 SKILL.md 안에 있다
SKILL.md 를 읽으려면 →  스킬을 불러야 한다
```

`description` frontmatter 가 이 순환을 끊으라고 있는 것인데,
**생성된 목차는 스킬 *이름만* 나열하고 description 을 안 싣는다.**

```
- **스킬** (특별·대형 작업 시 직접 호출): `.claude/skills/` —
  node-patterns typescript-patterns tdd-workflow python-patterns ...
```

이름만으로 언제 쓸지 판단하라는 것이고, 그 위에 *"특별·대형일 때만"* 이라는
잘못된 문틀까지 씌워져 있다.

### 1-3. 실제로 일어난 위반 (terminal-shipping · 2026-08-21)

웹앱 저장소 골격(파일 대여섯 개)의 파일 구조를 설계하면서
`structured-file-layout` 을 **호출하지 않았다.**

```
판단   "파일 대여섯 개짜리 작은 일이다" → CLAUDE.md 기준으로는 맞다
결과   app/models/ · app/api/ · app/adapters/  ← 타입 기준
       그런데 그 스킬 2단계가 바로 그것을 "잘못된 예" 로 든다
```

⚠️ **계획 문서(§4)에도 그 형태로 적혀 있었다.** 즉 계획 단계에서 이미 어긋났고,
사람이 *"그 엔지니어링도 잘 따르고 있느냐"* 고 물어서야 드러났다.

★ **에이전트는 스킬 *이름* 을 알고 있었고, 그것을 *내용을 안다* 로 착각했다.**
이름만 나열하는 목차가 정확히 그 착각을 만든다.

### 1-4. 사전학습이 반대쪽으로 강하다

FastAPI 예제 대부분이 `app/models/`·`app/routers/` 타입 기준이다.
**스킬을 안 읽으면 사전학습이 이긴다.** `CLAUDE.md` 가 *"기억 말고 문서 먼저"* 라고
적어 둔 바로 그 상황인데, 그 문서를 언제 열어야 하는지를 같은 파일이 좁게 말한다.

## 2. 문제 정의

```
① 문틀이 틀렸다      "특별·대형 작업 시" 가 스킬의 발동 조건을 좁힌다
② 근거가 없다        목차가 이름만 준다. description 이 있는데 안 쓴다
③ 게이트가 없다      안 부르고 파일을 만들어도 아무도 막지 않는다
```

★ ①②는 **문서 생성 문제**이고 ③은 **훅 문제**다. ③은 이미
[responsibility-over-linecount §3.3](./2026-08-21-responsibility-over-linecount-design.md)
이 다루므로 **이 문서는 ①②를 맡는다.**

## 3. 설계 결정

### 3.0 지배 원칙

```
스킬이 자기 발동 조건의 주인이다     생성기가 그것을 덮어쓰지 않는다
목차는 판단 재료를 준다             이름만 주고 판단하라고 하지 않는다
컨텍스트 예산을 존중한다             description 은 짧다. 본문은 여전히 지연 로드
```

### 3.1 문틀을 고친다 (우선순위 1)

```
지금   "- **스킬** (특별·대형 작업 시 직접 호출): `.claude/skills/` — a b c"
바꿈   "- **스킬** (아래 조건에 걸리면 호출한다. 크기와 무관하다): `.claude/skills/`"
```

- 대상: `lib/claude_md_gen.sh:48`
- 판정: 그 줄을 읽고 *"작은 일에는 안 불러도 된다"* 로 읽히지 않는다

### 3.2 이름 옆에 발동 조건을 싣는다 ★

`SKILL.md` frontmatter 의 `description` 이 이미 *"언제 쓰나"* 를 담고 있다.
**생성기가 그것을 읽어 목차에 붙인다.**

```
- **스킬**: `.claude/skills/` — 조건에 걸리면 호출한다
  - structured-file-layout — 새 파일·기능·exec-plan 작성 전, 코드를 쓰기 전에
  - tdd-workflow — ...
  - postgres-patterns — ...
```

✅ **미결 해소 (2026-08-21 구현)**

```
description 이 영어다        그대로 싣는다. 번역·요약하면 스킬 원본과 갈라진다.
                            실측: 38개 중 harness-* 3개는 이미 한글이라 혼재는 원본 상태다.
길이 상한                    SKILL_TRIGGER_MAX=120자. 근거는 아래.
description 이 없는 스킬     이름만 남긴다. 실측 결과 현재 38개 전부 보유 — 방어 분기.
SKILL.md 자체가 없는 스킬    이름만 남긴다.
```

★ **상한 120자의 근거 — 관측된 최장 발동 조건 절이 98자다.**
`structured-file-layout` 의 *"Use when creating new files, planning features, or
writing exec-plans — before any code is written"* 가 그것이다. 상한이 98보다 낮으면
**정작 호출 시점을 지정하는 절이 잘려 나간다** — 이 문서가 고치려는 바로 그 구멍이
다른 형태로 남는다. 120은 그 절을 보존하고 여유를 둔 값이다.

⚠️ **절단은 문자 단위가 아니라 단어 경계에서 한다.** `cut -c` 로 자르면 로케일이
`C` 일 때 한글이 반토막 나 깨진 바이트가 `CLAUDE.md` 에 박힌다(구현 중 실제 발생:
`대응하는` → `대응�`). 단어 사이에서만 자르면 로케일과 무관하게 안전하다.
`LC_ALL=C` / `C.UTF-8` 양쪽에서 UTF-8 무결을 검증했다.

⚠️ **컨텍스트 비용 실측.** 문서 초안의 *"20개 × 한 줄"* 추정은 낙관적이었다.
description 중앙값 171자·최대 741자이고, 프로젝트당 설치 스킬은 18~25개다.
상한을 적용해도 설치본 목차에 18~25줄이 더해진다.
**단, 100줄 규율은 이미 깨져 있다** — 설치본 `CLAUDE.md` 실측 136~191줄,
DS 관리 블록만 115~153줄이다. 이 축의 증가분(+16% 내외)은 블록의 본래 목적
(스킬을 제때 열게 하는 것)에 쓰이므로 감수한다. 규율 자체는 별도 축의 문제다.

### 3.3 `.claude/skills/` 의 목차를 별도 파일로 뺄 것인가

⚫ **대안.** `CLAUDE.md` 를 100줄로 유지하면서 조건을 싣는 길이다.

```
CLAUDE.md      "- **스킬**: 조건은 .claude/skills/INDEX.md 에 있다. 새 파일 전에 본다"
INDEX.md       이름 + description 전부
```

⚠️ **그러나 한 겹 더 들어가면 안 읽힌다.** §1-2 의 순환이 형태만 바뀌어 되살아난다.
**3.2 를 먼저 시도하고, 컨텍스트가 실제로 문제가 될 때 3.3 으로 간다.**

### 3.4 교리는 건드리지 않는다

`SKILL.md` 들의 `description` 은 이미 정확하다. **고칠 것은 그것을 옮기는 쪽이다.**

## 4. 전파

```
① lib/claude_md_gen.sh          ✅ 문틀 교체 + _skill_trigger() 로 description 싣기
② 설치본 재생성                  ⬜ 미실행 — 사람 승인 대기 (10개 저장소)
③ Codex 쪽                      ✅ 확인 완료 — 손댈 것 없음
④ tests/                        ✅ tests/claude-md-skill-index-test.sh (13 단언) + 러너 등록
```

**③ 확인 결과.** `lib/codex_md_gen.sh:36` 이 `claude_md_gen.sh` 의 (A)(B) 헬퍼를
공유하고, `AGENTS.md` 를 찍는 진입점은 `project-codex.sh` 하나뿐이며 그 파일이
`ASSETS_DIR` 를 설정한다(`setup-codex.sh`·`update-codex-all.sh` 는 생성기를 부르지
않는다). **①만 고치면 Codex 쪽이 따라온다.**

⚠️ **②가 핵심이고, 아직 남아 있다.** 옛 문장을 들고 있는 설치본을 전수 확인했다.

```
terminal-shipping  rim-office  ai-create  rim-kanban  novel-ab
upbit-ai-trading   teulankkae  kis-trading  novel-bc   zeroday-frontend
```

**보존 검증은 끝났다.** terminal-shipping 의 `CLAUDE.md` 사본에 `generate_claude_md`
를 돌려, DS 마커 **바깥 내용의 해시가 재생성 전후로 동일**함을 확인했다(옛 문구 제거,
스킬 줄 38개 삽입). 남은 것은 실제 저장소에 적용하는 일뿐이다:

```bash
bash update-all.sh --target both
```

## 5. 위험

| 위험 | 징후 | 대응 |
|---|---|---|
| **CLAUDE.md 비대화** | 100줄 규율을 넘김 | 한 줄 상한 · 넘치면 3.3 |
| **재생성이 사람 내용을 지움** | 블록 바깥 문단 소실 | ②에서 확인. DS 마커 밖은 보존 |
| **영문 description 혼재** | 한글 문서에 영어 줄 | 그대로 싣는다 — 번역하면 원본과 갈라진다. 혼재는 스킬 원본의 기존 상태다 |
| **멀티바이트 절단 깨짐** | `CLAUDE.md` 에 `대응�` 같은 바이트 | 단어 경계 절단. `LC_ALL=C`·`C.UTF-8` 양쪽 검증 |
| **조건을 실어도 안 부름** | 같은 위반 반복 | ③ 게이트가 필요하다 → responsibility 문서 §3.3 |

## 6. 발견

- ★ **이 구멍은 "무엇을 아는가" 가 아니라 "언제 여는가" 의 문제다.**
  스킬 내용은 정확했고 설치도 되어 있었다. **여는 시점만 틀렸다.**
- ⚠️ **`description` 은 이미 쓰여 있었다.** 스킬 작성자가 발동 조건을 정확히 적어
  두었는데 **생성기가 그것을 안 읽는다.** 새로 쓸 것이 없다 — 있는 것을 옮기면 된다.
  (responsibility 문서 §6 의 *"size-warn 은 이미 옳은 말을 하고 있었다"* 와 같은 형태다)
- ⚫ **하네스가 못 잡은 위반 둘이 하루에 나왔다.** 줄 수 축과 스킬 호출 축이다.
  둘 다 **사람이 물어서** 드러났지 장치가 알린 것이 아니다.
