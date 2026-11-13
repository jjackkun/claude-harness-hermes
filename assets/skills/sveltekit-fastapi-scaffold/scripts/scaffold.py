"""Copy the SvelteKit + FastAPI skeleton into a project folder and write its single root .env.

    python3 scaffold.py --name apt-curtain --dest /path/to/project [--dry-run]

- Template files end in `.tmpl` (stripped on copy); a leading `dot.` becomes `.`.
- `{{PROJECT}}` is replaced with --name. Ports are picked from free ports, skipping ports
  already written in sibling projects' .env files.
- Never overwrites: if any target file exists, nothing is written and the conflicts are listed (exit 2).
- Writes one .env at the project root (frontend, pm2, db and backend all read it) with a random
  DB password and SECRET_KEY, mode 600. One file so env-secrets backs up every value.
  If a .env already exists, its keys and values are kept and only missing keys are appended
  (e.g. a project that already holds GEMINI_API_KEY in .env).
Exit codes: 0 ok · 1 bad input · 2 conflicts.
"""

import argparse
import json
import re
import secrets
import sys
from pathlib import Path

from free_ports import pick_ports

TEMPLATES = Path(__file__).resolve().parent.parent / "templates"
NAME_RE = re.compile(r"^[a-z][a-z0-9-]{1,39}$")
PLACEHOLDER_RE = re.compile(r"\{\{[A-Z_]+\}\}")
MERGE_FILES = {".gitignore", ".env"}  # appended to instead of treated as a conflict
PORT_KEYS = re.compile(r"^(?:VITE_FRONTEND_PORT_\w+|API_PORT_\w+|DB_PORT)=(\d+)$", re.M)


def target_path(template: Path, dest: Path) -> Path:
    rel = template.relative_to(TEMPLATES)
    parts = [p[len("dot.") - 1 :] if p.startswith("dot.") else p for p in rel.parts]
    parts[-1] = parts[-1].removesuffix(".tmpl")
    return dest.joinpath(*parts)


def render(text: str, name: str) -> str:
    out = text.replace("{{PROJECT}}", name)
    left = PLACEHOLDER_RE.findall(out)
    if left:
        raise ValueError(f"unreplaced placeholders: {sorted(set(left))}")
    return out


def ports_used_by_siblings(dest: Path) -> frozenset[int]:
    used: set[int] = set()
    for env in dest.resolve().parent.glob("*/.env"):
        try:
            used.update(int(p) for p in PORT_KEYS.findall(env.read_text(errors="ignore")))
        except OSError:
            continue
    return frozenset(used)


def env_files(name: str, ports: dict[str, int]) -> dict[str, str]:
    """The project's single .env. DATABASE_URL / ALLOWED_ORIGINS are derived by the backend."""
    db_name = name.replace("-", "_")
    root = "\n".join(
        [
            f"PROJECT_NAME={name}",
            f"VITE_FRONTEND_PORT_DEV={ports['FRONT_DEV']}",
            f"VITE_FRONTEND_PORT_PROD={ports['FRONT_PROD']}",
            f"API_PORT_DEV={ports['API_DEV']}",
            f"API_PORT_PROD={ports['API_PROD']}",
            f"DB_PORT={ports['DB']}",
            f"DB_NAME={db_name}",
            f"DB_USER={db_name}_app",
            f"DB_PASSWORD={secrets.token_urlsafe(24)}",
            f"SECRET_KEY={secrets.token_urlsafe(48)}",
            "ACCESS_TOKEN_EXPIRE_MINUTES=30",
            "REFRESH_TOKEN_EXPIRE_DAYS=7",
            "DEBUG_SQL=false",
            "# First superadmin: fill both, then `corepack pnpm bootstrap` creates it once.",
            "SUPERADMIN_EMAIL=",
            "SUPERADMIN_PASSWORD=",
            "",
        ]
    )
    return {".env": root}


def merge_lines(existing: str, wanted: str) -> str:
    """Append lines of `wanted` that `existing` lacks (used for .gitignore)."""
    have = {line.strip() for line in existing.splitlines()}
    extra = [line for line in wanted.splitlines() if line.strip() and line.strip() not in have]
    if not extra:
        return existing
    sep = "" if existing.endswith("\n") or not existing else "\n"
    return f"{existing}{sep}\n# --- sveltekit-fastapi-scaffold ---\n" + "\n".join(extra) + "\n"


def env_keys(text: str) -> set[str]:
    return {line.split("=", 1)[0].strip() for line in text.splitlines() if "=" in line and not line.startswith("#")}


def merge_env(existing: str, wanted: str) -> str:
    """Keep every existing KEY=value; append only keys the file does not have yet."""
    have = env_keys(existing)
    extra = [line for line in wanted.splitlines() if "=" in line and line.split("=", 1)[0] not in have]
    if not extra:
        return existing
    sep = "" if existing.endswith("\n") or not existing else "\n"
    return f"{existing}{sep}\n# --- sveltekit-fastapi-scaffold ---\n" + "\n".join(extra) + "\n"


def plan(name: str, dest: Path) -> dict[Path, str]:
    """Return files to write. Existing .gitignore/.env are merged, never treated as conflicts."""
    files = {target_path(t, dest): render(t.read_text(), name) for t in sorted(TEMPLATES.rglob("*.tmpl"))}
    files.update({dest / rel: body for rel, body in env_files(name, pick_ports(ports_used_by_siblings(dest))).items()})
    for path in [p for p in files if p.name in MERGE_FILES and p.exists()]:
        merge = merge_env if path.name == ".env" else merge_lines
        files[path] = merge(path.read_text(), files[path])
    return files


def find_conflicts(files: dict[Path, str], dest: Path) -> list[str]:
    return sorted(str(p.relative_to(dest)) for p in files if p.exists() and p.name not in MERGE_FILES)


def write_files(files: dict[Path, str]) -> None:
    for path, body in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
        if path.name == ".env":
            path.chmod(0o600)
        elif path.suffix == ".sh":
            path.chmod(0o755)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", required=True, help="project name: lowercase, digits, hyphen")
    ap.add_argument("--dest", required=True, type=Path)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not NAME_RE.match(args.name):
        print(f"bad --name {args.name!r}: use ^[a-z][a-z0-9-]{{1,39}}$", file=sys.stderr)
        return 1

    files = plan(args.name, args.dest)
    conflicts = find_conflicts(files, args.dest)
    if conflicts:
        print(json.dumps({"status": "conflict", "existing": conflicts}, ensure_ascii=False, indent=2))
        return 2

    if not args.dry_run:
        write_files(files)

    root_env = files[args.dest / ".env"]  # final content: existing values win over new ones
    summary = {
        "status": "dry-run" if args.dry_run else "ok",
        "files": len(files),
        "ports": dict(re.findall(r"^((?:VITE_FRONTEND_PORT|API_PORT)_\w+|DB_PORT)=(\d+)$", root_env, re.M)),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
