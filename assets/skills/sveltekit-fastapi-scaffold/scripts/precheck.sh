#!/usr/bin/env bash
# Report (do not install) the user-level tools the skeleton needs. Exit 1 if a required one is missing.
# Required: node >= 20, corepack (for pnpm), uv, python3 >= 3.11. Nothing here installs globally.
set -u
missing=0

report() { printf '%-10s %s\n' "$1" "$2"; }

if command -v node >/dev/null 2>&1; then
  v=$(node -v); major=${v#v}; major=${major%%.*}
  if [ "$major" -ge 20 ]; then report node "$v"; else report node "$v (need >= 20)"; missing=1; fi
else report node "MISSING"; missing=1; fi

corepack_bin=$(command -v corepack 2>/dev/null || true)
[ -z "$corepack_bin" ] && [ -x "$HOME/.local/bin/corepack" ] && corepack_bin="$HOME/.local/bin/corepack"
if [ -n "$corepack_bin" ]; then
  report pnpm "$("$corepack_bin" pnpm --version 2>/dev/null || echo 'corepack pnpm failed')"
else report pnpm "MISSING (corepack ships with node)"; missing=1; fi

uv_bin=""
for c in "$(command -v uv 2>/dev/null)" "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv"; do
  if [ -n "$c" ] && [ -x "$c" ]; then uv_bin=$c; break; fi
done
if [ -n "$uv_bin" ]; then report uv "$("$uv_bin" --version) ($uv_bin)"
else report uv "MISSING — user install: curl -LsSf https://astral.sh/uv/install.sh | sh"; missing=1; fi

if command -v python3 >/dev/null 2>&1; then
  report python3 "$(python3 -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])')"
  python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,11) else 1)' || { echo "  python3 >= 3.11 needed"; missing=1; }
else report python3 "MISSING"; missing=1; fi

report postgres "project-local via embedded-postgres (no system install needed)"
report pm2 "project-local devDependency (no global install needed)"
exit $missing
