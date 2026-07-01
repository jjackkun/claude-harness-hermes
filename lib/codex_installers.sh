#!/usr/bin/env bash
# dev-setting/lib/codex_installers.sh
# Responsibility: Codex-specific project assets.

install_codex_hooks() {
  local project_path="$1"
  local src_dir="$ASSETS_DIR/codex/hooks"
  local target_dir="$project_path/scripts/codex-hooks"
  [[ -d "$src_dir" ]] || { log_warn "Codex hooks missing: $src_dir"; return 0; }

  mkdir -p "$target_dir"
  local f dest
  for f in "$src_dir"/*.sh; do
    [[ -f "$f" ]] || continue
    dest="$target_dir/$(basename "$f")"
    cp "$f" "$dest"
    chmod +x "$dest"
    log_info "  hook    → scripts/codex-hooks/$(basename "$f")"
  done
}

install_codex_scripts() {
  local project_path="$1"
  local src_dir="$ASSETS_DIR/codex/scripts"
  local target_dir="$project_path/scripts"
  [[ -d "$src_dir" ]] || return 0

  mkdir -p "$target_dir"
  local f dest
  for f in "$src_dir"/*.sh; do
    [[ -f "$f" ]] || continue
    dest="$target_dir/$(basename "$f")"
    cp "$f" "$dest"
    chmod +x "$dest"
    log_info "  script  → scripts/$(basename "$f")"
  done
}

install_codex_plugin_bundle() {
  local project_path="$1"
  local plugin_dir="$project_path/plugins/ai-dev-setting"
  mkdir -p "$plugin_dir/.codex-plugin" "$plugin_dir/skills" "$plugin_dir/agents" "$plugin_dir/rules"

  cat > "$plugin_dir/.codex-plugin/plugin.json" <<'EOF'
{
  "name": "ai-dev-setting",
  "version": "0.1.0",
  "description": "Project-local harness engineering assets for Codex.",
  "author": {
    "name": "jjackkun",
    "email": "local@ai-dev-setting"
  },
  "keywords": ["harness", "codex", "development"],
  "skills": "./skills/",
  "hooks": "./hooks.json",
  "interface": {
    "displayName": "AI Dev Setting",
    "shortDescription": "Harness engineering presets for Codex",
    "developerName": "jjackkun",
    "category": "Coding",
    "capabilities": ["Read", "Write"]
  }
}
EOF

  log_info "  plugin  → plugins/ai-dev-setting"
}

install_codex_marketplace() {
  local project_path="$1"
  local market_dir="$project_path/.agents/plugins"
  local market_file="$market_dir/marketplace.json"
  mkdir -p "$market_dir"

  cat > "$market_file" <<'EOF'
{
  "name": "ai-dev-setting-local",
  "interface": {
    "displayName": "AI Dev Setting Local"
  },
  "plugins": [
    {
      "name": "ai-dev-setting",
      "source": {
        "source": "local",
        "path": "./plugins/ai-dev-setting"
      },
      "policy": {
        "installation": "INSTALLED_BY_DEFAULT",
        "authentication": "ON_USE"
      },
      "category": "Coding"
    }
  ]
}
EOF

  log_info "  market  → .agents/plugins/marketplace.json"
}

install_codex_harness_docs_templates() {
  local project_path="$1"
  [[ ${HARNESS_DOCS_TEMPLATES:-0} -eq 1 ]] || return 0
  local src_dir="$ASSETS_DIR/docs-templates"
  [[ -d "$src_dir" ]] || { log_warn "docs-templates missing in assets (skipped)"; return 0; }

  local copied=0
  local f base dest
  for f in "$src_dir"/*.tmpl; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f" .tmpl)"
    [[ "$base" == "CLAUDE.md" ]] && continue
    dest="$project_path/$base"
    if [[ -e "$dest" ]]; then
      log_info "  doc     → $base (이미 존재, 보존)"
    else
      sed "s|{{PROJECT_NAME}}|$(basename "$project_path")|g; s|{{PROJECT_ROOT}}|$(basename "$project_path")|g" "$f" > "$dest"
      log_info "  doc     → $base (생성)"
      copied=$((copied + 1))
    fi
  done

  if [[ -d "$src_dir/docs" ]]; then
    while IFS= read -r f; do
      local rel="${f#$src_dir/}"
      base="${rel%.tmpl}"
      dest="$project_path/$base"
      if [[ -e "$dest" ]]; then
        continue
      fi
      mkdir -p "$(dirname "$dest")"
      cp "$f" "$dest"
      copied=$((copied + 1))
    done < <(find "$src_dir/docs" -type f \( -name "*.tmpl" -o -name "*.md" \) 2>/dev/null)
    log_info "  docs/   → $copied 개 템플릿 (기존 보존)"
  fi
}
