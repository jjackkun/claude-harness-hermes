# env-secrets — WSL 에서 윈도우 쪽 bw 를 건너뛴다

## 왜

2026-11-12 jj-agent-room `secrets:open` 이 60초 뒤 "bw 상태 알 수 없음" 으로 끝났다. PATH 에서 `~/.local/bin` 이 빠지자(빈 `~/.bash_profile`) `bw` 가 윈도우 npm 의 `/mnt/c/Users/<사용자>/AppData/Roaming/npm/bw` 로 잡혔고, 9p 로 읽혀 `--version` 하나에 88초가 걸렸다(`VAULT_BW_TIMEOUT_SECONDS=60`). 리눅스 `~/.local/bin/bw` 는 같은 때 `status` 2.9초.
홈 파일은 고쳤지만(사용자 승인, 한 줄 `~/.bash_profile`), PATH 가 다시 꼬이면 도구가 같은 모양으로 멈춘다.

## 할 일 후보

- `assets/env-secrets/lib/env-secrets-vault.sh` 의 `${BW_BIN:-bw}` 를 고르는 함수로: `BW_BIN` 이 없으면 `type -a -P bw` 중 `/mnt/*` 가 아닌 첫 번째, 없으면 `$(npm prefix -g)/bin/bw`, 그래도 없으면 `/mnt/*` 것.
- 시험 먼저: PATH 앞에 `/mnt` 흉내 경로 대신 "느린 bw" 를 두는 방식은 경로 판정을 못 잰다 → 판정 함수를 따로 source 해 경로 목록으로 단언.
- `/mnt/*` bw 만 있을 때 "윈도우 bw 는 WSL 에서 느립니다 — npm i -g @bitwarden/cli 로 리눅스 쪽에 설치" 안내.

근거: `completed/2026-10-16-env-secrets-preset.md` §7 (2026-11-12 실측 중 멈춤)
