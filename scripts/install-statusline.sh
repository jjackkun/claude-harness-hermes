#!/usr/bin/env bash
# Install the Claude Code statusline (email | model | project) onto this machine.
#
# 다른 컴퓨터에 이 파일 하나만 복사해서 실행하면 됩니다:
#   bash install-statusline.sh
#
# 하는 일:
#   1) ~/.claude/statusline.sh 생성 (email | model | 프로젝트명 출력)
#   2) ~/.claude/settings.json 의 statusLine 항목만 추가/갱신 (기존 설정 보존)
# 멱등(idempotent): 여러 번 실행해도 결과가 같습니다.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
STATUSLINE="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# 1) statusline.sh 작성 ------------------------------------------------------
# 'EOS' 를 따옴표로 감싸 heredoc 내부 변수($input 등)가 지금 치환되지 않게 함.
cat > "$STATUSLINE" <<'EOS'
#!/usr/bin/env bash
# Claude Code statusline script
# Reads JSON from stdin and outputs a formatted status line

input=$(cat)

if command -v jq >/dev/null 2>&1; then
    model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
    # 프로젝트 루트 경로 → 프로젝트명(basename). project_dir 우선, 없으면 cwd 폴백
    project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .cwd // empty')
else
    # jq 미설치 환경 폴백: "display_name":"..." 값을 직접 추출
    model=$(echo "$input" | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    model=${model:-"Unknown Model"}
    project_dir=$(echo "$input" | sed -n 's/.*"project_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    project_dir=${project_dir:-$(echo "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')}
fi
project="${project_dir##*/}"
project="${project:-unknown}"
# 현재 로그인 계정 이메일을 ~/.claude.json 의 oauthAccount 에서 읽음
_account_file="$HOME/.claude.json"
if command -v jq >/dev/null 2>&1 && [ -f "$_account_file" ]; then
    email=$(jq -r '.oauthAccount.emailAddress // empty' "$_account_file" 2>/dev/null)
elif [ -f "$_account_file" ]; then
    email=$(python3 -c "import json; print(json.load(open('$HOME/.claude.json')).get('oauthAccount',{}).get('emailAddress',''))" 2>/dev/null)
fi
email="${email:-unknown}"

printf "%s | %s | %s" "$email" "$model" "$project"
EOS
chmod +x "$STATUSLINE"
echo "✔ statusline 설치: $STATUSLINE"

# 2) settings.json 에 statusLine 등록 (기존 키 보존) --------------------------
# command 경로는 이 머신의 $HOME 으로 동적 설정.
python3 - "$SETTINGS" "$STATUSLINE" <<'PY'
import json, os, sys

settings_path, statusline_path = sys.argv[1], sys.argv[2]

data = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        # 손상된 설정을 덮어쓰지 않고 중단 (사용자 데이터 보호)
        print(f"✗ {settings_path} 파싱 실패: {e}", file=sys.stderr)
        sys.exit(1)

data["statusLine"] = {
    "type": "command",
    "command": f"bash {statusline_path}",
}

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"✔ settings.json 갱신: {settings_path}")
PY

echo
echo "완료. 새 상태줄은 다음 프롬프트부터 다음 형식으로 표시됩니다:"
echo "  이메일 | 모델명 | 프로젝트명"
