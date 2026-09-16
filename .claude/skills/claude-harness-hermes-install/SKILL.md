---
name: claude-harness-hermes-install
description: Use when modifying assets (rules, skills, agents, hooks) in claude-harness-hermes and deciding whether changes need reinstallation across projects, or when running setup/update-all commands.
---

# claude-harness-hermes 설치 메커니즘

## 핵심 원칙

소우주(설치 대상 프로젝트)에는 `assets/` 하위 스킬·규칙·에이전트를 **복사**로 설치한다(OS 무관).
설치 항목은 `.claude/.factory-manifest.json`(커밋 대상)에 `name · kind · factory_commit · sha256` 으로
기록되고, 정리·제거·변조 감지는 이 목록 기준이다. 공장 위치는 `.hermes/factory.json` 에 남는다.
심링크 설치는 2026-09-16 폐지 — 근거 `docs/hermes-universe/design/world/copy-install.md`.

**예외**: 공장(이 저장소) 자기 설치만 저장소 안 **상대경로 링크**(`.claude/skills/x -> ../../assets/skills/x`).
두 벌 관리를 피하고 clone 에서도 깨지지 않는다. 세션 시작 훅이 깨진 링크를 알린다.

## 파일 수정 후 반영 여부

| 수정 내용 | 반영 시점 |
|-----------|-----------|
| `assets/rules/**` · `assets/skills/**` · `assets/agents/**` | 소우주: `update-all` 필요 / 공장 자신: 즉시(상대 링크) |
| `assets/hooks/**` | `update-all` 필요 (복사) |
| `presets/*.conf` 추가 | setup 으로 신규 설치 필요 |
| 신규 프로젝트 등록 | `setup.sh` 실행 필요 |

소우주에서 공통 스킬을 직접 고치면 `[factory-tamper WARN]` 이 뜬다 — 다음 `update-all` 이 덮어쓴다.
고칠 내용은 소우주 확장(`.hermes/skills/`)으로 옮기고 우주에 제안한다.

## 설치/업데이트 명령

```bash
# 신규 프로젝트 설정 (대화형 fzf UI)
bash setup.sh                        # Claude 대상
bash setup.sh --codex                # Codex 대상
bash setup.sh --both                 # 둘 다

# 등록된 모든 프로젝트 재설치
bash update-all.sh                   # Claude 대상
bash update-all.sh --target codex    # Codex 대상
bash update-all.sh --target both     # 둘 다

# setup.sh --update-all 도 동일
bash setup.sh --update-all --target both
```

## 설치 레지스트리

- Claude: `.installed-projects`
- Codex: `.installed-projects.codex`

`update-all.sh`는 이 레지스트리를 읽어 `presets.lock`을 기준으로 재설치한다.
경로가 사라진 프로젝트는 자동으로 레지스트리에서 제거된다.

## 확인 방법

```bash
# 복사 설치 확인 — 링크 0, 설치 목록 존재
find /path/to/project/.claude/{skills,rules,agents} -type l | wc -l   # → 0
python3 -c "import json;print(len(json.load(open('/path/to/project/.claude/.factory-manifest.json'))['items']))"
```

## 언제 update-all이 필요한가

- Windows 환경의 모든 파일 수정 후
- 신규 preset/rule/skill 추가 후 기존 프로젝트에도 적용하려 할 때
- 소우주가 공장 수정을 받으려 할 때(복사 설치는 즉시 반영이 아니다)
- 공장 자기 설치의 상대 링크가 깨진 경우(`[factory-link WARN]`)
