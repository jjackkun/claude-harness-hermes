# assets/

이 디렉터리는 `public-claude.sh` 와 `project-claude.sh` 가 **심볼릭 링크로 가져다 쓰는** 실제 자산 저장소입니다. 프리셋 파일(`presets/**/*.conf`) 은 단지 여기 있는 자산의 **이름**을 참조할 뿐이므로, **이 디렉터리가 비어 있으면 프리셋이 모든 항목에 대해 `WARN: ... missing in assets` 를 출력**합니다.

## 구조

```
assets/
├── skills/<skill-name>/SKILL.md       # 디렉터리 단위. progressive disclosure 가능
├── agents/<agent-name>.md             # 단일 파일
└── rules/<ruleset>/                   # 디렉터리 (rules/common, rules/python ...)
```

## 채우는 방법

크게 세 가지 경로가 있습니다.

### 1. 즉석에서 ECC(everything-claude-code) 베이스라인 cherry-pick

가장 빠른 시작.  현재 권장하는 11 개 에이전트 + Python rules + 핵심 스킬을 ECC 에서 가져옵니다.

```bash
git clone https://github.com/affaan-m/everything-claude-code.git /tmp/ecc

# 1) 에이전트 11 개
cp /tmp/ecc/agents/{architect,code-reviewer,planner,silent-failure-hunter,\
refactor-cleaner,performance-optimizer,tdd-guide,docs-lookup,doc-updater,\
python-reviewer,database-reviewer}.md \
   /home/user/PROJECT/dev-setting/assets/agents/

# 2) 공용 + Python rules
cp -r /tmp/ecc/rules/common /tmp/ecc/rules/python \
      /home/user/PROJECT/dev-setting/assets/rules/

# 3) 핵심 스킬 (디렉터리 단위)
for s in search-first strategic-compact continuous-learning-v2 \
         verification-loop coding-standards tdd-workflow; do
  cp -r /tmp/ecc/skills/$s /home/user/PROJECT/dev-setting/assets/skills/
done

rm -rf /tmp/ecc
```

> 주의: ECC 의 스킬 명칭이 변경되었거나 일부 스킬은 존재하지 않을 수 있습니다.
> 누락된 항목은 `project-claude.sh` 가 WARN 으로 알려주므로,
> 그때그때 선택해서 채우면 됩니다.

### 2. 직접 작성 (FastAPI / Svelte / Upbit / KIS 등)

ECC 에 없는 스킬은 직접 만듭니다. 형식은 매우 단순합니다.

`assets/skills/fastapi-patterns/SKILL.md`:
```markdown
---
name: fastapi-patterns
description: FastAPI 베스트 프랙티스 적용 가이드. async 엔드포인트, Depends, Pydantic v2 사용 패턴. Use when writing or reviewing FastAPI route handlers.
---

# FastAPI Patterns

## Async-first
- 모든 엔드포인트는 `async def` 가 기본 ...
```

`description` 끝에 **`Use when ...`** 트리거 문구를 명시해야 Claude 가 자동으로 인식합니다.

### 3. 기존 `~/.claude/` 자산 마이그레이션

이미 사용하던 자산이 있으면 그대로 옮겨오세요.
```bash
cp -r ~/.claude/agents/* assets/agents/ 2>/dev/null || true
cp -r ~/.claude/skills/* assets/skills/ 2>/dev/null || true
cp -r ~/.claude/rules/*  assets/rules/  2>/dev/null || true
```

## 자산 추가 후

1. 변경 사항은 반드시 git 에 커밋 (이 디렉터리는 dev-setting 저장소의 일부)
2. 새 기기에서 사용할 때는 `git clone` 만 하면 모든 자산이 함께 따라옵니다.
3. 기존 프로젝트들은 **자동으로 최신 내용을 사용** — `project-claude.sh` 를 다시 돌릴 필요 없음. (자산이 심볼릭 링크로 연결돼 있기 때문)
4. 프리셋 자체(스킬 목록 등)를 바꾼 경우에만 `project-claude.sh` 재실행 필요.
