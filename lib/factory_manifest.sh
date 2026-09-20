#!/usr/bin/env bash
# lib/factory_manifest.sh
# Responsibility: 설치 목록(.claude/.factory-manifest.json) 의 기록·읽기·정리·해시 대조만 담당.
# 설계: docs/hermes-universe/design/world/copy-install.md §4 #2·#3, 결정 I-02.
#
# 목록 항목: {name, kind(skills|agents|rules), factory_commit, sha256}
# 목록은 git 에 커밋된다 — 다른 컴퓨터의 clone 도 어느 파일이 공장 것인지 알아야
# 변조 감지·정리가 동작한다. (.dev-setting-manifest.json 과 다른 점)
#
# 공개 함수 4개: manifest_add · manifest_read · manifest_prune · manifest_verify

_MANIFEST_NAME=".factory-manifest.json"

_manifest_path() { printf '%s/%s' "$1" "$_MANIFEST_NAME"; }

# 디렉터리·파일 내용 해시. 파일 순서를 고정해 컴퓨터가 달라도 같은 값.
_manifest_sha() {
  local target="$1"
  if [[ -d "$target" ]]; then
    # -print0/-z/-0: 공백·탭이 든 이름을 xargs 가 쪼개 빈 목록 해시(e3b0c4…)가 되던 결함(2026-09-20 리뷰). 개행이 든 이름은 여전히 미지원.
    (cd "$target" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum) | sha256sum | awk '{print $1}'
  else
    sha256sum "$target" | awk '{print $1}'
  fi
}

# manifest_add <claude_dir> <kind> <name> <installed_path>
# 항목을 추가하거나(같은 kind+name 이면) 교체한다.
manifest_add() {
  # $5 src  — 공장 상대 원본 경로(선택). 공존 설치가 base 내용을 `git show <commit>:<src>` 로 복원할 때 쓴다.
  # $6 mode — 설치된 파일의 8진 모드(선택). 둘 다 없던 옛 항목도 그대로 읽힌다(계획 2026-09-17-install-coexistence 목표 4).
  local claude_dir="$1" kind="$2" name="$3" path="$4" src_rel="${5:-}" mode="${6:-}"
  local sha commit
  sha="$(_manifest_sha "$path")"
  commit="$(git -C "${DEV_SETTING_DIR:-$ASSETS_DIR/..}" rev-parse HEAD 2>/dev/null || echo unknown)"
  M_KIND="$kind" M_NAME="$name" M_SHA="$sha" M_COMMIT="$commit" M_SRC="$src_rel" M_MODE="$mode" \
    python3 - "$(_manifest_path "$claude_dir")" <<'PYEOF'
import json, os, sys
p = sys.argv[1]
os.makedirs(os.path.dirname(p) or ".", exist_ok=True)   # Codex 전용 프로젝트엔 .claude/ 가 없다 — 2026-09-17 실측 13회 FileNotFoundError
items = []
if os.path.isfile(p):
    try:
        items = json.load(open(p, encoding="utf-8")).get("items", [])
    except (json.JSONDecodeError, AttributeError):
        print("[factory-manifest WARN] 설치 목록이 손상돼 새로 만든다: " + p, file=sys.stderr)
        items = []
k, n = os.environ["M_KIND"], os.environ["M_NAME"]
items = [i for i in items if not (i.get("kind") == k and i.get("name") == n)]
item = {"name": n, "kind": k,
        "factory_commit": os.environ["M_COMMIT"], "sha256": os.environ["M_SHA"]}
# 선택 필드 — 값이 있을 때만 적는다. 없으면 옛 항목과 같은 모양이라 읽는 쪽이 구분할 일이 없다.
if os.environ.get("M_SRC"):
    item["src"] = os.environ["M_SRC"]
if os.environ.get("M_MODE"):
    item["mode"] = os.environ["M_MODE"]
items.append(item)
items.sort(key=lambda i: (i["kind"], i["name"]))
tmp = p + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"version": 1, "items": items}, f, ensure_ascii=False, indent=2)
os.replace(tmp, p)   # 원자적 교체 — 도중에 죽어도 목록이 잘린 채 남지 않는다
PYEOF
}

# manifest_read <claude_dir> <kind>  → 그 kind 의 이름을 한 줄씩 출력
manifest_read() {
  local p; p="$(_manifest_path "$1")"
  [[ -f "$p" ]] || return 0
  M_KIND="$2" python3 - "$p" <<'PYEOF'
import json, os, sys
try:
    items = json.load(open(sys.argv[1], encoding="utf-8")).get("items", [])
except (json.JSONDecodeError, AttributeError):
    print("[factory-manifest WARN] 설치 목록이 손상됨: " + sys.argv[1], file=sys.stderr)
    items = []
for i in items:
    if i.get("kind") == os.environ["M_KIND"]:
        print(i["name"])
PYEOF
}

# manifest_prune <claude_dir> <kind> <keep_names...>
# 목록에 있으나 keep 에 없는 항목을 목록에서 뺀다. 뺀 이름을 한 줄씩 출력한다(호출측이 파일을 지운다).
manifest_prune() {
  local claude_dir="$1" kind="$2"; shift 2
  local p; p="$(_manifest_path "$claude_dir")"
  [[ -f "$p" ]] || return 0
  M_KIND="$kind" M_KEEP="$(printf '%s\n' "$@")" python3 - "$p" <<'PYEOF'
import json, os, sys
p = sys.argv[1]
try:
    data = json.load(open(p, encoding="utf-8"))
except json.JSONDecodeError:
    print("[factory-manifest WARN] 설치 목록이 손상돼 정리를 건너뛴다: " + p, file=sys.stderr)
    sys.exit(0)
keep = set(l for l in os.environ["M_KEEP"].split("\n") if l)
k = os.environ["M_KIND"]
kept, removed = [], []
for i in data.get("items", []):
    if i.get("kind") == k and i["name"] not in keep:
        removed.append(i["name"])
    else:
        kept.append(i)
data["items"] = kept
tmp = p + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
os.replace(tmp, p)
for n in removed:
    print(n)
PYEOF
}

# manifest_field <claude_dir> <kind> <name> <field>  → 그 항목의 필드 값 한 줄(없으면 빈 줄, 종료코드 0)
# field: sha256 | factory_commit | src | mode. 공존 설치(lib/factory_coexist.sh)가 base 판정·복원에 쓴다.
manifest_field() {
  local p; p="$(_manifest_path "$1")"
  [[ -f "$p" ]] || return 0
  M_KIND="$2" M_NAME="$3" M_FIELD="$4" python3 - "$p" <<'PYEOF'
import json, os, sys
try:
    items = json.load(open(sys.argv[1], encoding="utf-8")).get("items", [])
except (json.JSONDecodeError, AttributeError):
    items = []
for i in items:
    if i.get("kind") == os.environ["M_KIND"] and i.get("name") == os.environ["M_NAME"]:
        print(i.get(os.environ["M_FIELD"], "") or ""); break
PYEOF
}

# manifest_verify <claude_dir> <kind> <name> <installed_path>
# 목록의 sha256 과 현재 내용이 같으면 0, 다르면 1, 목록에 없으면 2.
manifest_verify() {
  local claude_dir="$1" kind="$2" name="$3" path="$4"
  local p; p="$(_manifest_path "$claude_dir")"
  [[ -f "$p" && -e "$path" ]] || return 2
  local recorded
  recorded="$(M_KIND="$kind" M_NAME="$name" python3 - "$p" <<'PYEOF'
import json, os, sys
for i in json.load(open(sys.argv[1], encoding="utf-8")).get("items", []):
    if i.get("kind") == os.environ["M_KIND"] and i.get("name") == os.environ["M_NAME"]:
        print(i.get("sha256", "")); break
PYEOF
)"
  [[ -n "$recorded" ]] || return 2
  [[ "$recorded" == "$(_manifest_sha "$path")" ]]
}
