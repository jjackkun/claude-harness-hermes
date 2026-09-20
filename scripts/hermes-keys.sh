#!/usr/bin/env bash
# 열쇠 CLI — **AI 세션 밖에서 사람이** 부른다. 세션 안 Bash 는 키 가드 훅이 막는다(T-11).
#
#   init           마스터 열쇠 + 이 컴퓨터 자물쇠를 만들고 마스터를 감싸 등록한다
#   add-computer   다른 컴퓨터의 자물쇠로 마스터를 한 번 더 감싼다
#   lock           이 컴퓨터 자물쇠만 만들고(없으면) 보여 준다 — 두 번째 컴퓨터가 합류할 때. 마스터는 만들지 않는다
#   emergency      비상 열쇠를 만들고 24단어로 한 번만 보여 준다(옮겨 적기 → 재입력 확인)
#   revoke         자물쇠 등록을 지운다(그 열쇠로는 새로 감싸지 않는다)
#   rotate-master  마스터를 새로 만든다 — 새 조각부터 적용, 옛 마스터는 보관(G-4)
#   doctor         age 설치·열쇠 존재·권한을 점검한다
#
# 근거: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 4
# 설계: docs/hermes-universe/design/protection/encryption-keys.md

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${HERMES_PROJECT_DIR:-$(cd "$SCRIPTS_DIR/.." && pwd)}"
ASSUME_YES=0

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  echo
  echo "사용법: hermes-keys.sh <명령> [--yes] [--project <경로>]"
  exit "${1:-0}"
}

_py() { HERMES_PROJECT_DIR="$PROJECT_DIR" PYTHONPATH="$SCRIPTS_DIR" python3 - "$@"; }

_universe() {
  _py <<'PY'
import os, sys
sys.path.insert(0, os.environ["PYTHONPATH"])
from hermes_universe import universe_id
print(universe_id(os.environ["HERMES_PROJECT_DIR"]))
PY
}

_confirm() {
  [[ "$ASSUME_YES" == "1" ]] && return 0
  local answer
  read -r -p "$1 [yes/no]: " answer
  [[ "$answer" == "yes" ]]
}

cmd_doctor() {
  local uid; uid="$(_universe)"
  echo "소우주: $uid"
  if command -v age >/dev/null 2>&1 && command -v age-keygen >/dev/null 2>&1; then
    echo "  age: $(age --version)"
  else
    echo "  age: 없음 — 설치기가 깐다: 공장에서 bash update-all.sh (lib/tool_installers.sh, 핀 고정)"
  fi
  _py "$uid" <<'PY'
import os, stat, sys
sys.path.insert(0, os.environ["PYTHONPATH"])
from hermes_keys import key_path
uid = sys.argv[1]
for kind in ("master", "computer"):
    path = key_path(uid, kind)
    if not os.path.isfile(path):
        print(f"  {kind}: 없음 ({path})")
        continue
    mode = stat.S_IMODE(os.stat(path).st_mode)
    flag = "" if mode == 0o600 else f"  ⚠ 권한 {oct(mode)} — 0600 이어야 한다"
    print(f"  {kind}: 있음 ({path}){flag}")
PY
}

cmd_init() {
  local uid; uid="$(_universe)"
  _py "$uid" <<'PY'
import os, sys
sys.path.insert(0, os.environ["PYTHONPATH"])
import hermes_crypto as crypto
from hermes_keys import fingerprint, key_path, wrap_master
uid = sys.argv[1]
if not crypto.age_available():
    print("[hermes-keys] age 가 없다 — 먼저 설치하십시오", file=sys.stderr); sys.exit(1)
master = key_path(uid, "master")
if os.path.isfile(master):
    print(f"[hermes-keys] 마스터 열쇠가 이미 있다: {master} (덮어쓰지 않는다)"); sys.exit(0)
mlock = crypto.generate_identity(master)
clock = crypto.generate_identity(key_path(uid, "computer"))
wrapped = wrap_master(uid, clock)
out = os.path.join(key_path(uid), "wrapped")
os.makedirs(out, exist_ok=True)
name = fingerprint(clock)
open(os.path.join(out, f"{name}.pub"), "w", encoding="utf-8").write(clock + "\n")
open(os.path.join(out, f"master.{name}.age"), "wb").write(wrapped)
print(f"[hermes-keys] 마스터 자물쇠: {mlock}")
print(f"[hermes-keys] 이 컴퓨터 자물쇠: {clock} (지문 {name})")
print(f"[hermes-keys] 감싼 마스터: {out}/master.{name}.age")
print("[hermes-keys] 다음: hermes-keys.sh emergency 로 비상 열쇠를 만드십시오.")
PY
}

cmd_add_computer() {
  local uid lock; uid="$(_universe)"
  lock="${1:-}"
  if [[ -z "$lock" ]]; then
    read -r -p "합류할 컴퓨터의 자물쇠(age1…): " lock
  fi
  _py "$uid" "$lock" <<'PY'
import os, sys
sys.path.insert(0, os.environ["PYTHONPATH"])
from hermes_keys import fingerprint, key_path, wrap_master
uid, lock = sys.argv[1], sys.argv[2].strip()
if not lock.startswith("age1"):
    print("[hermes-keys] age1… 로 시작하는 자물쇠가 아니다", file=sys.stderr); sys.exit(2)
out = os.path.join(key_path(uid), "wrapped"); os.makedirs(out, exist_ok=True)
name = fingerprint(lock)
open(os.path.join(out, f"{name}.pub"), "w", encoding="utf-8").write(lock + "\n")
open(os.path.join(out, f"master.{name}.age"), "wb").write(wrap_master(uid, lock))
print(f"[hermes-keys] 등록됨: 지문 {name}")
print("[hermes-keys] 다음 push 에서 원격 keys/ 로 올라갑니다.")
PY
}

cmd_lock() {
  local uid; uid="$(_universe)"
  _py "$uid" <<'PY'
import os, sys
sys.path.insert(0, os.environ["PYTHONPATH"])
import hermes_crypto as crypto
from hermes_keys import fingerprint, key_path
uid = sys.argv[1]
if not crypto.age_available():
    print("[hermes-keys] age 가 없다 — 설치기가 깐다: 공장에서 bash update-all.sh", file=sys.stderr); sys.exit(1)
path = key_path(uid, "computer")
if os.path.isfile(path):
    lock = crypto.public_key(path); made = "이미 있음"
else:
    lock = crypto.generate_identity(path); made = "새로 만듦"
print(f"[hermes-keys] 이 컴퓨터 자물쇠({made}, 지문 {fingerprint(lock)}):")
print(lock)
print("[hermes-keys] 다음: 마스터가 있는 컴퓨터에서 `hermes-keys.sh add-computer <위 자물쇠>` → push, 이 컴퓨터에서 `hermes-sync.py pull`.")
PY
}

cmd_emergency() {
  local uid; uid="$(_universe)"
  cat <<'EOF'
────────────────────────────────────────────────────────────────────
비상 열쇠를 만듭니다. 컴퓨터를 모두 잃었을 때 과거 기록을 여는 유일한 수단입니다.
  · 화면에 24단어가 **한 번만** 나옵니다. 종이에 옮겨 적으십시오.
  · 이 단어를 잃으면 아무도(만든 사람 포함) 복구할 수 없습니다.
  · 사진·클라우드 메모·이 저장소 안에는 두지 마십시오.
────────────────────────────────────────────────────────────────────
EOF
  _confirm "위 내용을 이해했습니까?" || { echo "[hermes-keys] 중단"; return 1; }
  _py "$uid" "$ASSUME_YES" <<'PY'
import os, sys, tempfile
sys.path.insert(0, os.environ["PYTHONPATH"])
import hermes_crypto as crypto
from hermes_keys import fingerprint, key_path, wrap_master
from hermes_mnemonic import key_to_mnemonic, mnemonic_to_key, MnemonicError
uid, assume_yes = sys.argv[1], sys.argv[2] == "1"

tmp = tempfile.mkdtemp(prefix=".hermes-emergency-")
ident = os.path.join(tmp, "emergency.key")
lock = crypto.generate_identity(ident)
secret = [l for l in open(ident, encoding="utf-8") if l.startswith("AGE-SECRET-KEY-")][0].strip()
words = key_to_mnemonic(secret)

print("\n── 비상 열쇠 24단어 ──")
for row in range(0, 24, 4):
    print("  " + "  ".join(f"{row+i+1:2d}.{words[row+i]:<10}" for i in range(4)))
print()

if assume_yes:
    given = words                      # 테스트 경로: 사람 입력 없이 같은 단어로 확인
else:
    print("옮겨 적었으면 24단어를 그대로 입력하십시오(공백 구분).")
    given = sys.stdin.readline().split()

try:
    restored = mnemonic_to_key(given)
except MnemonicError as exc:
    print(f"[hermes-keys] 확인 실패: {exc}", file=sys.stderr); sys.exit(3)
if restored != secret:
    print("[hermes-keys] 확인 실패: 입력한 단어가 만든 열쇠와 다릅니다", file=sys.stderr); sys.exit(3)

# 시험 복호 — 단어로 되살린 열쇠가 실제로 여는지 확인한 뒤에야 등록한다
probe = crypto.encrypt_to([lock], b"hermes-emergency-probe")
if crypto.decrypt_with_secret(restored, probe) != b"hermes-emergency-probe":
    print("[hermes-keys] 시험 복호 실패 — 등록하지 않습니다", file=sys.stderr); sys.exit(3)

out = os.path.join(key_path(uid), "wrapped"); os.makedirs(out, exist_ok=True)
name = fingerprint(lock)
open(os.path.join(out, f"{name}.pub"), "w", encoding="utf-8").write(lock + "\n")
open(os.path.join(out, f"master.{name}.age"), "wb").write(wrap_master(uid, lock))

os.unlink(ident); os.rmdir(tmp)        # 비상 열쇠 평문은 남기지 않는다 — 단어가 유일본
print(f"[hermes-keys] 확인 완료 · 등록됨(지문 {name}). 비상 열쇠 파일은 남기지 않았습니다.")
PY
}

cmd_revoke() {
  local uid fp; uid="$(_universe)"; fp="${1:-}"
  [[ -z "$fp" ]] && { echo "[hermes-keys] 지문을 지정하십시오 (doctor 로 목록 확인)"; return 2; }
  _confirm "지문 $fp 등록을 지웁니다. 계속?" || { echo "[hermes-keys] 중단"; return 1; }
  _py "$uid" "$fp" <<'PY'
import os, sys
sys.path.insert(0, os.environ["PYTHONPATH"])
from hermes_keys import key_path
uid, fp = sys.argv[1], sys.argv[2]
out = os.path.join(key_path(uid), "wrapped")
removed = 0
for name in (f"{fp}.pub", f"master.{fp}.age"):
    path = os.path.join(out, name)
    if os.path.isfile(path):
        os.unlink(path); removed += 1
print(f"[hermes-keys] {removed}개 파일 제거(지문 {fp}).")
print("[hermes-keys] 주의: 이미 그 열쇠를 가진 사람은 **과거 조각**을 계속 열 수 있습니다.")
print("            새 마스터가 필요하면 rotate-master 를 쓰십시오.")
PY
}

cmd_rotate_master() {
  local uid; uid="$(_universe)"
  _confirm "마스터를 새로 만듭니다. 옛 조각은 옛 마스터로만 열립니다. 계속?" \
    || { echo "[hermes-keys] 중단"; return 1; }
  _py "$uid" <<'PY'
import os, shutil, sys
from datetime import datetime
sys.path.insert(0, os.environ["PYTHONPATH"])
import hermes_crypto as crypto
from hermes_keys import fingerprint, key_path, wrap_master
uid = sys.argv[1] if len(sys.argv) > 1 else None
uid = uid or os.environ.get("HERMES_UNIVERSE_ID")
master = key_path(uid, "master")
if not os.path.isfile(master):
    print("[hermes-keys] 마스터가 없다 — init 을 먼저", file=sys.stderr); sys.exit(1)
stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
kept = master + f".retired-{stamp}"
shutil.move(master, kept)              # 지우지 않는다 — 옛 조각을 여는 유일한 열쇠다
crypto.generate_identity(master)
clock = crypto.public_key(key_path(uid, "computer"))
out = os.path.join(key_path(uid), "wrapped"); os.makedirs(out, exist_ok=True)
name = fingerprint(clock)
open(os.path.join(out, f"master.{name}.age"), "wb").write(wrap_master(uid, clock))
print(f"[hermes-keys] 옛 마스터 보관: {kept}")
print("[hermes-keys] 새 마스터로 이 컴퓨터 자물쇠를 다시 감쌌습니다.")
print("[hermes-keys] 다른 컴퓨터·비상 열쇠는 add-computer / emergency 로 다시 등록하십시오.")
PY
}

main() {
  local cmd="${1:-}"; shift || true
  local rest=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) ASSUME_YES=1; shift ;;
      --project) PROJECT_DIR="$2"; shift 2 ;;
      -h|--help) usage 0 ;;
      *) rest+=("$1"); shift ;;
    esac
  done
  case "$cmd" in
    init)          cmd_init ;;
    add-computer)  cmd_add_computer "${rest[0]:-}" ;;
    lock)          cmd_lock ;;
    emergency)     cmd_emergency ;;
    revoke)        cmd_revoke "${rest[0]:-}" ;;
    rotate-master) HERMES_UNIVERSE_ID="$(_universe)" cmd_rotate_master ;;
    doctor)        cmd_doctor ;;
    ""|-h|--help)  usage 0 ;;
    *) echo "[hermes-keys] 모르는 명령: $cmd" >&2; usage 2 ;;
  esac
}

main "$@"
