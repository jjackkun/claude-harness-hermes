"""Copy the SvelteKit + FastAPI skeleton into a project folder and write its .env files.

    python3 scaffold.py --name apt-curtain --dest /path/to/project [--dry-run]

- Template files end in `.tmpl` (stripped on copy); a leading `dot.` becomes `.`.
- `{{PROJECT}}` is replaced with --name. Ports are picked from free ports, skipping ports
  already written in sibling projects' .env files.
- Never overwrites: if any target file exists, nothing is written and the conflicts are listed (exit 2).
- Writes .env (root) and backend/.env with a random DB password and SECRET_KEY, mode 600.
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
MERGE_FILES = {".gitignore"}  # appended to instead of treated as a conflict
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
    db_name = name.replace("-", "_")
    db_user = f"{db_name}_app"
    db_password = secrets.token_urlsafe(24)
    root = "\n".join(
        [
            f"PROJECT_NAME={name}",
            f"VITE_FRONTEND_PORT_DEV={ports['FRONT_DEV']}",
            f"VITE_FRONTEND_PORT_PROD={ports['FRONT_PROD']}",
            f"API_PORT_DEV={ports['API_DEV']}",
            f"API_PORT_PROD={ports['API_PROD']}",
            f"DB_PORT={ports['DB']}",
            f"DB_NAME={db_name}",
            f"DB_USER={db_user}",
            f"DB_PASSWORD={db_password}",
            "",
        ]
    )
    origins = f"http://localhost:{ports['FRONT_DEV']},http://localhost:{ports['FRONT_PROD']}"
    backend = "\n".join(
        [
            f"DATABASE_URL=postgresql+asyncpg://{db_user}:{db_password}@localhost:{ports['DB']}/{db_name}",
            f"SECRET_KEY={secrets.token_urlsafe(48)}",
            f"ALLOWED_ORIGINS={origins}",
            "ACCESS_TOKEN_EXPIRE_MINUTES=30",
            "REFRESH_TOKEN_EXPIRE_DAYS=7",
            "DEBUG_SQL=false",
            "",
        ]
    )
    return {".env": root, "backend/.env": backend}


def merge_lines(existing: str, wanted: str) -> str:
    """Append lines of `wanted` that `existing` lacks (used for .gitignore)."""
    have = {line.strip() for line in existing.splitlines()}
    extra = [line for line in wanted.splitlines() if line.strip() and line.strip() not in have]
    if not extra:
        return existing
    sep = "" if existing.endswith("\n") or not existing else "\n"
    return f"{existing}{sep}\n# --- sveltekit-fastapi-scaffold ---\n" + "\n".join(extra) + "\n"


def plan(name: str, dest: Path) -> tuple[dict[Path, str], dict[str, int]]:
    """Return (files to write, chosen ports). Existing .env files and merge files are not conflicts."""
    files = {target_path(t, dest): render(t.read_text(), name) for t in sorted(TEMPLATES.rglob("*.tmpl"))}
    for path in [p for p in files if p.name in MERGE_FILES and p.exists()]:
        files[path] = merge_lines(path.read_text(), files[path])
    ports = pick_ports(ports_used_by_siblings(dest))
    env_targets = {dest / rel: body for rel, body in env_files(name, ports).items()}
    files.update({p: b for p, b in env_targets.items() if not p.exists()})  # keep an existing .env
    return files, ports


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

    files, ports = plan(args.name, args.dest)
    conflicts = find_conflicts(files, args.dest)
    if conflicts:
        print(json.dumps({"status": "conflict", "existing": conflicts}, ensure_ascii=False, indent=2))
        return 2

    kept_env = (args.dest / ".env") not in files  # an existing .env was left untouched
    if not args.dry_run:
        write_files(files)

    summary = {
        "status": "dry-run" if args.dry_run else "ok",
        "files": len(files),
        "ports": "kept existing .env" if kept_env else ports,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
