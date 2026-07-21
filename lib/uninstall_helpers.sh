#!/usr/bin/env bash
# dev-setting/lib/uninstall_helpers.sh
# Responsibility: uninstall.sh 전용 제거 헬퍼 — 설치물별 안전 제거 (사용자 자산 보존).
# Sourced by uninstall.sh. 전역 의존: DEV_SETTING_DIR, DRY_RUN, GREEN/YELLOW/RESET.

# ── 공통 ──────────────────────────────────────────────────────────────────────

# _known_hooks: assets/hooks/ 기준 알려진 harness hook 파일명 목록
_known_hooks() {
  local hooks_dir="$DEV_SETTING_DIR/assets/hooks"
  if [[ -d "$hooks_dir" ]]; then
    find "$hooks_dir" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.json" \) 2>/dev/null \
      | xargs -I{} basename {}
  fi
}

# _rm_path <file|dir> <path> <label>: dry-run 인지 처리 후 삭제 + 메시지
_rm_path() {
  local kind="$1" path="$2" label="$3"
  [[ -e "$path" || -L "$path" ]] || return 0
  if [[ $DRY_RUN -eq 1 ]]; then
    echo -e "  ${YELLOW}[dry]${RESET} 삭제: $label"
  else
    if [[ "$kind" == "dir" ]]; then rm -rf "$path"; else rm -f "$path"; fi
    echo -e "  ${GREEN}✔${RESET} 삭제: $label"
  fi
}

# _remove_marker_block <file> <begin> <end>: 마커 블록만 제거 (마커 밖 내용 보존)
_remove_marker_block() {
  local file="$1" begin="$2" end="$3"
  [[ -f "$file" ]] || return 0
  grep -qxF "$begin" "$file" || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip=1; next }
    skip && $0 == e { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp"
  # 연속 빈 줄 정리
  awk 'NF > 0 { blank=0 } NF == 0 { blank++ } blank <= 1' "$tmp" > "$file"
  rm -f "$tmp"
}

# _remove_registry_entry <registry_file> <path>
_remove_registry_entry() {
  local registry="$1" path="$2"
  [[ -f "$registry" ]] || return 0
  grep -qxF "$path" "$registry" || return 0
  local tmp
  tmp="$(mktemp)"
  grep -vxF "$path" "$registry" > "$tmp" || true
  mv "$tmp" "$registry"
}

# ── settings.json 하네스 hooks 정리 ──────────────────────────────────────────
# .claude/settings.json 의 hooks 중 scripts/hooks/<known-hook> 을 가리키는
# 항목만 제거한다. 사용자가 직접 등록한 hook / 기타 키는 전부 보존.
uninstall_settings_hooks() {
  local project_path="$1"
  local settings="$project_path/.claude/settings.json"
  [[ -f "$settings" ]] || return 0
  command -v python3 >/dev/null 2>&1 || {
    echo -e "  ${YELLOW}⚠${RESET}  python3 없음 — settings.json hooks 정리 건너뜀 (수동 확인 필요)"
    return 0
  }

  local -a known=()
  while IFS= read -r h; do
    [[ -n "$h" ]] && known+=("$h")
  done < <(_known_hooks)
  [[ ${#known[@]} -eq 0 ]] && return 0

  local removed
  removed=$(python3 - "$settings" "$DRY_RUN" "${known[@]}" <<'PYEOF'
import json
import sys

settings_path, dry_run, *known = sys.argv[1:]
dry = dry_run == "1"
try:
    with open(settings_path) as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    print(0)
    sys.exit(0)

hooks = data.get("hooks")
if not isinstance(hooks, dict):
    print(0)
    sys.exit(0)


def is_harness_cmd(cmd: str) -> bool:
    return any(f"scripts/hooks/{name}" in cmd for name in known)


removed = 0
new_hooks = {}
for event, entries in hooks.items():
    if not isinstance(entries, list):
        new_hooks[event] = entries
        continue
    kept_entries = []
    for entry in entries:
        if not isinstance(entry, dict):
            kept_entries.append(entry)
            continue
        inner = entry.get("hooks")
        if not isinstance(inner, list):
            kept_entries.append(entry)
            continue
        kept_inner = []
        for h in inner:
            cmd = h.get("command", "") if isinstance(h, dict) else ""
            if is_harness_cmd(cmd):
                removed += 1
            else:
                kept_inner.append(h)
        if kept_inner:
            entry = dict(entry, hooks=kept_inner)
            kept_entries.append(entry)
    if kept_entries:
        new_hooks[event] = kept_entries

if removed and not dry:
    if new_hooks:
        data["hooks"] = new_hooks
    else:
        data.pop("hooks", None)
    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
print(removed)
PYEOF
  ) || removed=0

  if [[ "${removed:-0}" -gt 0 ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo -e "  ${YELLOW}[dry]${RESET} .claude/settings.json 하네스 hooks ${removed}개 제거 (사용자 항목 보존)"
    else
      echo -e "  ${GREEN}✔${RESET} .claude/settings.json 하네스 hooks ${removed}개 제거 (사용자 항목 보존)"
    fi
  fi
}

# ── .claude/{skills,agents,rules} 하네스 symlink 정리 ────────────────────────
# ai-dev-setting/assets 를 가리키는 symlink 만 제거. 사용자 실파일/타 symlink 보존.
uninstall_asset_symlinks() {
  local project_path="$1"
  local assets_dir="$DEV_SETTING_DIR/assets"
  local sub dir entry target
  for sub in skills agents rules; do
    dir="$project_path/.claude/$sub"
    [[ -d "$dir" ]] || continue
    for entry in "$dir"/*; do
      [[ -L "$entry" ]] || continue
      target="$(readlink "$entry")"
      [[ "$target" == "$assets_dir"* ]] || continue
      _rm_path file "$entry" ".claude/$sub/$(basename "$entry") (symlink)"
    done
    # 비었으면 디렉터리 제거
    if [[ $DRY_RUN -eq 0 && -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
      rmdir "$dir"
      echo -e "  ${GREEN}✔${RESET} 삭제: .claude/$sub/ (비어있어 제거)"
    fi
  done
}

# ── .git/hooks/pre-commit + check-component-structure.mjs ───────────────────
# 하네스가 설치한 것인지 내용 마커("4단 검사")로 확인 후 제거. 사용자 훅 보존.
uninstall_pre_commit() {
  local project_path="$1"
  local pre_commit="$project_path/.git/hooks/pre-commit"
  if [[ -f "$pre_commit" ]]; then
    if grep -qF "4단 검사" "$pre_commit"; then
      _rm_path file "$pre_commit" ".git/hooks/pre-commit (하네스 4단 검사)"
    else
      echo -e "  ${YELLOW}⚠${RESET}  .git/hooks/pre-commit 은 하네스 마커가 없어 보존합니다"
    fi
  fi
  _rm_path file "$project_path/.git/hooks/check-component-structure.mjs" ".git/hooks/check-component-structure.mjs"
  _rm_path file "$project_path/scripts/check-component-structure.mjs" "scripts/check-component-structure.mjs"
}

# ── lint-configs/harness-*.config.js ─────────────────────────────────────────
uninstall_lint_configs() {
  local project_path="$1"
  local dir="$project_path/lint-configs"
  [[ -d "$dir" ]] || return 0
  local f
  for f in "$dir"/harness-*.config.js; do
    [[ -e "$f" ]] || continue
    _rm_path file "$f" "lint-configs/$(basename "$f")"
  done
  if [[ $DRY_RUN -eq 0 && -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
    rmdir "$dir"
    echo -e "  ${GREEN}✔${RESET} 삭제: lint-configs/ (비어있어 제거)"
  fi
}

# ── GC 워크플로 (weekly-doc-gardening) ───────────────────────────────────────
# 자산 템플릿과 동일할 때만 삭제 — 사용자가 수정했으면 보존 + 경고.
uninstall_gc_workflows() {
  local project_path="$1"
  local gh_dest="$project_path/.github/workflows/weekly-doc-gardening.yml"
  local gh_src="$DEV_SETTING_DIR/assets/cron-templates/github-actions/weekly-doc-gardening.yml"
  if [[ -f "$gh_dest" ]]; then
    if [[ -f "$gh_src" ]] && cmp -s "$gh_dest" "$gh_src"; then
      _rm_path file "$gh_dest" ".github/workflows/weekly-doc-gardening.yml"
    else
      echo -e "  ${YELLOW}⚠${RESET}  .github/workflows/weekly-doc-gardening.yml 이 템플릿과 달라 보존합니다 (수동 확인)"
    fi
  fi
  local gl_dest="$project_path/.gitlab/doc-gardening.yml"
  local gl_src="$DEV_SETTING_DIR/assets/cron-templates/gitlab-ci/weekly-doc-gardening.gitlab-ci.yml"
  if [[ -f "$gl_dest" ]]; then
    if [[ -f "$gl_src" ]] && cmp -s "$gl_dest" "$gl_src"; then
      _rm_path file "$gl_dest" ".gitlab/doc-gardening.yml"
    else
      echo -e "  ${YELLOW}⚠${RESET}  .gitlab/doc-gardening.yml 이 템플릿과 달라 보존합니다 (수동 확인)"
    fi
  fi
}

# ── package.json scripts.serena 제거 ─────────────────────────────────────────
uninstall_pkg_serena() {
  local project_path="$1"
  local pkg="$project_path/package.json"
  [[ -f "$pkg" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local removed
  removed=$(python3 - "$pkg" "$DRY_RUN" <<'PYEOF'
import json
import sys

pkg_path, dry_run = sys.argv[1], sys.argv[2]
try:
    with open(pkg_path) as f:
        pkg = json.load(f)
except (OSError, json.JSONDecodeError):
    print(0)
    sys.exit(0)

scripts = pkg.get("scripts")
cmd = scripts.get("serena", "") if isinstance(scripts, dict) else ""
# 하네스가 주입한 항목만 제거 (bin/serena-dash 경로 마커)
if isinstance(cmd, str) and "serena-dash" in cmd:
    if dry_run != "1":
        del scripts["serena"]
        if not scripts:
            pkg.pop("scripts", None)
        with open(pkg_path, "w") as f:
            json.dump(pkg, f, indent=2, ensure_ascii=False)
            f.write("\n")
    print(1)
else:
    print(0)
PYEOF
  ) || removed=0
  if [[ "${removed:-0}" -gt 0 ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo -e "  ${YELLOW}[dry]${RESET} package.json scripts.serena 제거"
    else
      echo -e "  ${GREEN}✔${RESET} package.json scripts.serena 제거"
    fi
  fi
}

# ── Codex 설치물 제거 ─────────────────────────────────────────────────────────
# .codex/ + AGENTS.md 관리 블록 + scripts/codex-hooks/ + codex 보조 스크립트 +
# plugins/ai-dev-setting 번들 + .agents/plugins/marketplace.json + 레지스트리 항목
uninstall_codex() {
  local project_path="$1"
  local codex_begin="<!--===DS-CODEX:BEGIN===-->"   # lib/codex_md_gen.sh 마커
  local codex_end="<!--===DS-CODEX:END===-->"

  _rm_path dir "$project_path/.codex" ".codex/"
  _rm_path dir "$project_path/scripts/codex-hooks" "scripts/codex-hooks/"

  # assets/codex/scripts/*.sh 가 scripts/ 로 복사됨 (예: codex-review.sh)
  local src_dir="$DEV_SETTING_DIR/assets/codex/scripts"
  if [[ -d "$src_dir" ]]; then
    local f
    for f in "$src_dir"/*.sh; do
      [[ -f "$f" ]] || continue
      _rm_path file "$project_path/scripts/$(basename "$f")" "scripts/$(basename "$f")"
    done
  fi

  # project-codex.sh 가 생성하는 로컬 플러그인 번들 + 마켓플레이스 등록
  _rm_path dir "$project_path/plugins/ai-dev-setting" "plugins/ai-dev-setting/"
  local market="$project_path/.agents/plugins/marketplace.json"
  if [[ -f "$market" ]] && grep -qF '"ai-dev-setting-local"' "$market"; then
    _rm_path file "$market" ".agents/plugins/marketplace.json"
  fi

  # AGENTS.md 관리 블록
  local agents_md="$project_path/AGENTS.md"
  if [[ -f "$agents_md" ]] && grep -qxF "$codex_begin" "$agents_md"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo -e "  ${YELLOW}[dry]${RESET} AGENTS.md 관리 블록 제거"
    else
      _remove_marker_block "$agents_md" "$codex_begin" "$codex_end"
      echo -e "  ${GREEN}✔${RESET} AGENTS.md 관리 블록 제거"
    fi
  fi

  # Codex 레지스트리 항목
  local codex_registry="$DEV_SETTING_DIR/.installed-projects.codex"
  if [[ -f "$codex_registry" ]] && grep -qxF "$project_path" "$codex_registry"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo -e "  ${YELLOW}[dry]${RESET} .installed-projects.codex 에서 제거"
    else
      _remove_registry_entry "$codex_registry" "$project_path"
      echo -e "  ${GREEN}✔${RESET} .installed-projects.codex 에서 제거"
    fi
  fi
}

# ── 네이티브 메모리 심링크 복원 ──────────────────────────────────────────────
# 언인스톨 후에도 Claude Code 메모리 보존: 우리(→<project>/.claude/memory) 심링크면
# 실디렉터리로 복사 복원. 저장소 원본(.claude/memory, git)은 건드리지 않는다. 멱등·dry-run 존중.
restore_memory_symlink() {
  local project_path="$1"
  local repo_mem="$project_path/.claude/memory"
  local key native
  key="$(printf '%s' "$project_path" | sed 's/[^a-zA-Z0-9]/-/g')"
  native="$HOME/.claude/projects/$key/memory"

  # 우리 저장소를 가리키는 심링크일 때만 복원(사용자 실파일/타 링크 보존)
  [[ -L "$native" && "$(readlink "$native")" == "$repo_mem" ]] || return 0

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo -e "  ${YELLOW:-}[dry]${RESET:-} 메모리 심링크 복원: $native (심링크 → 실디렉터리)"
    return 0
  fi
  rm -f "$native"
  mkdir -p "$native"
  [[ -d "$repo_mem" ]] && cp -rn "$repo_mem/." "$native/" 2>/dev/null || true
  echo -e "  ${GREEN:-}✔${RESET:-} 메모리 심링크 복원: $native (실디렉터리, 내용 보존)"
}
