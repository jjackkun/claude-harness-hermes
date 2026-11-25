#!/usr/bin/env bash
# lib/factory_manifest.sh
# Responsibility: 설치 목록(.claude/.factory-manifest.json) 의 기록·읽기·정리·해시 대조만 담당.
# 설계: docs/hermes-universe/design/world/copy-install.md §4 #2·#3, 결정 I-02.
#
# 목록 항목: {name, kind(skills|agents|rules), factory_commit, sha256}
# 목록은 git 에 커밋된다 — 다른 컴퓨터의 clone 도 어느 파일이 공장 것인지 알아야
# 변조 감지·정리가 동작한다. (.dev-setting-manifest.json 과 다른 점)
#
# 공개 함수 9개: manifest_batch_begin · manifest_batch_end · manifest_add · manifest_read · manifest_prune · manifest_drop · manifest_field · manifest_mark · manifest_verify

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

# ── 모아 쓰기 (2026-11-25, 계획 2026-11-25-manifest-batch-write) ──
# manifest_add 는 기록을 <목록>.pending 에 덧붙이고, _manifest_flush 가 python 한 번으로 목록에 반영한다.
# 묶음 모드가 아니면 덧붙인 즉시 비운다 — 예전(부를 때마다 반영)과 같은 동작이다.
# 묶음 모드(manifest_batch_begin ~ manifest_batch_end)면 설치 끝에 한 번만 비운다. 설치 1회에 python 347번 → 1번.
# 기록을 셸 변수가 아니라 파일에 두는 이유: 서브셸에서 부른 manifest_add 도 잃지 않고, 도중에 죽어도
# 다음 manifest_* 호출이 먼저 반영한다. 목록을 읽는 함수는 모두 읽기 전에 비운다.
_MANIFEST_BATCH_REG="${_MANIFEST_BATCH_REG:-}"      # (다시 source 해도 지키는 값) 묶음 모드면 이번 묶음에서 쓴 claude_dir 를 적는 임시 파일 경로
_MANIFEST_BATCH_COMMIT="${_MANIFEST_BATCH_COMMIT:-}"   # 묶음 안에서 한 번만 읽는 공장 커밋(설치 중에는 바뀌지 않는다)

_manifest_commit() {
  if [[ -n "$_MANIFEST_BATCH_REG" && -n "$_MANIFEST_BATCH_COMMIT" ]]; then
    printf '%s' "$_MANIFEST_BATCH_COMMIT"; return 0
  fi
  local c
  c="$(git -C "${DEV_SETTING_DIR:-$ASSETS_DIR/..}" rev-parse HEAD 2>/dev/null || echo unknown)"
  [[ -n "$_MANIFEST_BATCH_REG" ]] && _MANIFEST_BATCH_COMMIT="$c"
  printf '%s' "$c"
}

# _manifest_flush <claude_dir> — 모아 둔 기록을 순서대로 목록에 반영하고 .pending 을 지운다. 없으면 아무것도 안 한다.
_manifest_flush() {
  local p; p="$(_manifest_path "$1")"
  [[ -f "$p.pending" ]] || return 0
  python3 - "$p" <<'PYEOF'
import json, os, sys
p = sys.argv[1]
pending = p + ".pending"
os.makedirs(os.path.dirname(p) or ".", exist_ok=True)   # Codex 전용 프로젝트엔 .claude/ 가 없다 — 2026-09-17 실측 13회 FileNotFoundError
items = []
if os.path.isfile(p):
    try:
        items = json.load(open(p, encoding="utf-8")).get("items", [])
    except (json.JSONDecodeError, AttributeError):
        print("[factory-manifest WARN] 설치 목록이 손상돼 새로 만든다: " + p, file=sys.stderr)
        items = []
fields = open(pending, "rb").read().decode("utf-8", "surrogateescape").split("\0")
# 기록 하나 = kind, name, sha, commit, src, mode 여섯 칸(각 칸 뒤에 NUL). 마지막 조각은 NUL 로 끝나지 않은 나머지다
# (정상이면 빈 문자열, 쓰다 죽었으면 잘린 칸) — 버리고, 여섯 칸이 다 찬 기록만 반영한다.
complete = (len(fields) - 1) // 6 * 6
for r in range(0, complete, 6):
    k, n, sha, commit, src, mode = fields[r:r + 6]
    items = [i for i in items if not (i.get("kind") == k and i.get("name") == n)]
    item = {"name": n, "kind": k, "factory_commit": commit, "sha256": sha}
    # 선택 필드 — 값이 있을 때만 적는다. 없으면 옛 항목과 같은 모양이라 읽는 쪽이 구분할 일이 없다.
    if src:
        item["src"] = src
    if mode:
        item["mode"] = mode
    items.append(item)
items.sort(key=lambda i: (i["kind"], i["name"]))
tmp = p + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"version": 1, "items": items}, f, ensure_ascii=False, indent=2)
os.replace(tmp, p)   # 원자적 교체 — 도중에 죽어도 목록이 잘린 채 남지 않는다
os.remove(pending)   # 반영 뒤에 지운다 — 사이에서 죽으면 다음 비우기가 같은 기록을 다시 반영한다(같은 결과)
PYEOF
}

# manifest_batch_begin — 이 셸(과 서브셸)의 manifest_add 를 모아 두기 시작한다. 진입 스크립트만 부른다.
manifest_batch_begin() {
  [[ -n "$_MANIFEST_BATCH_REG" ]] && return 0
  _MANIFEST_BATCH_REG="$(mktemp "${TMPDIR:-/tmp}/factory-manifest-batch.XXXXXX")" || _MANIFEST_BATCH_REG=""
  _MANIFEST_BATCH_COMMIT=""
}

# manifest_batch_end — 이번 묶음에서 쓴 목록을 모두 비우고 묶음 모드를 끈다. 여러 번 불러도 된다(EXIT trap 겸용).
manifest_batch_end() {
  [[ -n "$_MANIFEST_BATCH_REG" ]] || return 0
  local reg="$_MANIFEST_BATCH_REG" d rc=0
  _MANIFEST_BATCH_REG=""; _MANIFEST_BATCH_COMMIT=""
  if [[ -f "$reg" ]]; then
    # 한 목록이 실패해도 나머지를 비우고 등록 파일을 지운 뒤 실패를 알린다. 실패한 목록의 .pending 은 남아
    # 다음 manifest_* 호출이 다시 반영한다.
    while IFS= read -r d; do
      [[ -n "$d" ]] || continue
      _manifest_flush "$d" || { rc=1; echo "[factory-manifest WARN] 설치 목록을 쓰지 못했습니다(기록은 $d/$_MANIFEST_NAME.pending 에 남음)" >&2; }
    done < <(LC_ALL=C sort -u "$reg")
    rm -f "$reg"
  fi
  return "$rc"
}

# manifest_add <claude_dir> <kind> <name> <installed_path>
# 항목을 추가하거나(같은 kind+name 이면) 교체한다.
manifest_add() {
  # $5 src  — 공장 상대 원본 경로(선택). 공존 설치가 base 내용을 `git show <commit>:<src>` 로 복원할 때 쓴다.
  # $6 mode — 설치된 파일의 8진 모드(선택). 둘 다 없던 옛 항목도 그대로 읽힌다(계획 2026-09-17-install-coexistence 목표 4).
  local claude_dir="$1" kind="$2" name="$3" path="$4" src_rel="${5:-}" mode="${6:-}"
  local sha commit p
  sha="$(_manifest_sha "$path")"
  commit="$(_manifest_commit)"
  p="$(_manifest_path "$claude_dir")"
  mkdir -p "$claude_dir" 2>/dev/null || return 1
  printf '%s\0' "$kind" "$name" "$sha" "$commit" "$src_rel" "$mode" >> "$p.pending" || return 1
  if [[ -n "$_MANIFEST_BATCH_REG" ]]; then
    printf '%s\n' "$claude_dir" >> "$_MANIFEST_BATCH_REG"
    return 0
  fi
  _manifest_flush "$claude_dir"
}

# manifest_read <claude_dir> <kind>  → 그 kind 의 이름을 한 줄씩 출력
manifest_read() {
  _manifest_flush "$1"
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
  _manifest_flush "$claude_dir"
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

# manifest_drop <claude_dir> <name...>
# 걷은 파일(이름 = 설치 목록의 name, 예 scripts/hermes-reindex.py)의 항목을 뺀다. 없으면 아무것도 안 한다.
# 파일만 지우고 항목을 남기면 설치 진단이 "파일 없음" 으로 잡는다(2026-09-29 전파 실측).
manifest_drop() {
  local claude_dir="$1"; shift
  _manifest_flush "$claude_dir"
  local p; p="$(_manifest_path "$claude_dir")"
  [[ -f "$p" && $# -gt 0 ]] || return 0
  M_DROP="$(printf '%s\n' "$@")" python3 - "$p" <<'PYEOF'
import json, os, sys
p = sys.argv[1]
try:
    data = json.load(open(p, encoding="utf-8"))
except json.JSONDecodeError:
    sys.exit(0)
drop = set(l for l in os.environ["M_DROP"].split("\n") if l)
items = data.get("items", [])
data["items"] = [i for i in items if i.get("name") not in drop]
if len(data["items"]) != len(items):
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, p)
PYEOF
}

# manifest_field <claude_dir> <kind> <name> <field>  → 그 항목의 필드 값 한 줄(없으면 빈 줄, 종료코드 0)
# field: sha256 | factory_commit | src | mode. 공존 설치(lib/factory_coexist.sh)가 base 판정·복원에 쓴다.
manifest_field() {
  _manifest_flush "$1"
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

# manifest_mark <claude_dir> <kind> <name> <field> <value>
# 기존 항목에 필드 하나를 적는다(항목이 없으면 아무것도 하지 않는다). manifest_add 는 항목을 새로 써서 이 필드를 지운다 — 의도된 동작이다.
# 쓰는 곳: 공존 설치가 충돌로 세워 둔 공장판의 sha(parked_sha) — 사람이 해소했는지 다음 설치가 알아보는 근거(2026-09-20).
manifest_mark() {
  _manifest_flush "$1"
  local p; p="$(_manifest_path "$1")"
  [[ -f "$p" ]] || return 0
  M_KIND="$2" M_NAME="$3" M_FIELD="$4" M_VALUE="$5" python3 - "$p" <<'PYEOF'
import json, os, sys
p = sys.argv[1]
try:
    data = json.load(open(p, encoding="utf-8"))
except (json.JSONDecodeError, AttributeError):
    sys.exit(0)
hit = False
for i in data.get("items", []):
    if i.get("kind") == os.environ["M_KIND"] and i.get("name") == os.environ["M_NAME"]:
        i[os.environ["M_FIELD"]] = os.environ["M_VALUE"]; hit = True
if hit:
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, p)
PYEOF
}

# manifest_verify <claude_dir> <kind> <name> <installed_path>
# 목록의 sha256 과 현재 내용이 같으면 0, 다르면 1, 목록에 없으면 2.
manifest_verify() {
  local claude_dir="$1" kind="$2" name="$3" path="$4"
  _manifest_flush "$claude_dir"
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
