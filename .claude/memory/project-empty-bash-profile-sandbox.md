---
name: project-empty-bash-profile-sandbox
description: jj-agent-room 에이전트(bwrap 샌드박스) 첫 실행이 홈에 빈 ~/.bash_profile 등 7개를 만들어 ~/.profile·~/.bashrc 가 안 읽힘 — PATH 이상 증상의 첫 용의자
metadata:
  node_type: memory
  type: project
  originSessionId: 34a46a60-f609-4549-a831-43e4000f4335
  modified: 2026-11-12T04:54:28.397Z
---

jj-agent-room 데몬이 에이전트를 Claude 샌드박스(bwrap)로 띄우면, 홈에 **없는** 보호 파일 자리에 0바이트 파일 7개가 생긴다:
`.bash_profile` · `.bash_aliases` · `.zshrc` · `.netrc` · `.yarnrc` · `.yarnrc.yml` · `.bunfig.toml`.
발생: 2026-10-15(Nova), 2026-11-03 13:31:11(dongha 세션 시작 1.4초 전). 이미 있는 파일(.bashrc·.profile)은 건드리지 않았다.

빈 `~/.bash_profile` 이 있으면 로그인 bash 가 `~/.profile` 을 건너뛰어 `~/.local/bin`·`~/.bashrc` 가 빠진다.
2026-11-12 증상: `bw` 가 윈도우 쪽 `/mnt/c/.../npm/bw`(88초)로 잡혀 `secrets:open` 이 60초 제한에 걸려 "열쇠 없음".

**Why:** 사용자가 "원래 되던 게 왜 안 되냐" 고 물었고, 원인이 코드가 아니라 홈 파일이었다. 10-30 홈 재세팅으로 10-15 의 대응이 사라져 재발했다.

**How to apply:** PATH·명령 위치가 이상하면(`type <cmd>` 가 /mnt/c 를 가리킴, claude·bw 못 찾음) 먼저 `ls -la ~/.bash_profile` 을 본다. 2026-11-12 사용자 승인으로 `~/.bash_profile` 을 `[ -f ~/.profile ] && . ~/.profile` 한 줄로 만들었다 — 비어 있으면 다시 지워진 것.
