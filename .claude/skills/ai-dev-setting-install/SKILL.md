---
name: ai-dev-setting-install
description: Use when modifying assets (rules, skills, agents, hooks) in ai-dev-setting and deciding whether changes need reinstallation across projects, or when running setup/update-all commands.
---

# ai-dev-setting 설치 메커니즘

## 핵심 원칙

Linux/macOS: `assets/` 하위 파일은 **symlink**로 각 프로젝트에 연결된다.
`assets/rules/common/coding-style.md`를 수정하면 재설치 없이 즉시 반영된다.

Windows: **copy** 방식. 수정 후 반드시 재설치 필요.

## 파일 수정 후 반영 여부

| 수정 내용 | Linux | Windows |
|-----------|-------|---------|
| `assets/rules/**` | 즉시 반영 (symlink) | update-all 필요 |
| `assets/skills/**` | 즉시 반영 (symlink) | update-all 필요 |
| `assets/agents/**` | 즉시 반영 (symlink) | update-all 필요 |
| `assets/hooks/**` | 즉시 반영 (symlink) | update-all 필요 |
| `presets/*.conf` 추가 | setup으로 신규 설치 필요 | 동일 |
| 신규 프로젝트 등록 | `setup.sh` 실행 필요 | 동일 |

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
# symlink 연결 확인
ls -la /path/to/project/.claude/rules/common
# → lrwxrwxrwx ... -> /home/.../ai-dev-setting/assets/rules/common
```

## 언제 update-all이 필요한가

- Windows 환경의 모든 파일 수정 후
- 신규 preset/rule/skill 추가 후 기존 프로젝트에도 적용하려 할 때
- symlink가 깨진 경우 (경로 이동 등)
