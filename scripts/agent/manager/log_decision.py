#!/usr/bin/env python3
# scripts/agent/manager/log_decision.py
#
# Loggt eine Manager/Sub-Agent-Entscheidung als Markdown-Datei unter
# data/manager/decisions/NNNN-slug.md und schreibt INDEX.md neu (aus den
# Dateien selbst generiert, nicht separat gepflegt — eine Quelle der
# Wahrheit). Append-only: bestehende Decision-Dateien werden nie
# überschrieben, nur --supersedes verweist auf ältere.
#
# Verwendung:
#   python3 scripts/agent/manager/log_decision.py \
#     --title "Kurztitel" \
#     --chosen "Was gewählt wurde" \
#     --alt "Verworfene Option A" --alt "Verworfene Option B" \
#     --rationale "Warum" \
#     --role manager \
#     [--supersedes 0001]

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[3]
_DECISIONS_DIR = _REPO_ROOT / "data" / "manager" / "decisions"
_INDEX_PATH = _DECISIONS_DIR / "INDEX.md"


def _slugify(title: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    return slug[:60] or "decision"


def _next_number() -> int:
    _DECISIONS_DIR.mkdir(parents=True, exist_ok=True)
    existing = list(_DECISIONS_DIR.glob("[0-9][0-9][0-9][0-9]-*.md"))
    if not existing:
        return 1
    nums = [int(p.name[:4]) for p in existing]
    return max(nums) + 1


def _write_decision(num: int, args: argparse.Namespace) -> Path:
    slug = _slugify(args.title)
    path = _DECISIONS_DIR / f"{num:04d}-{slug}.md"
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    alts = "\n".join(f"- {a}" for a in args.alt) if args.alt else "- (keine dokumentiert)"
    supersedes = f"\nSupersedes: {args.supersedes}" if args.supersedes else ""
    content = f"""# {num:04d} — {args.title}

Zeit: {ts}
Rolle: {args.role}{supersedes}

## Gewählt
{args.chosen}

## Verworfene Alternativen
{alts}

## Begründung
{args.rationale}
"""
    path.write_text(content, encoding="utf-8")
    return path


def _rebuild_index() -> None:
    files = sorted(_DECISIONS_DIR.glob("[0-9][0-9][0-9][0-9]-*.md"))
    superseded: set[str] = set()
    rows = []
    for f in files:
        text = f.read_text(encoding="utf-8")
        title_line = next((l for l in text.splitlines() if l.startswith("# ")), f"# {f.stem}")
        title = title_line[2:].strip()
        m = re.search(r"^Supersedes:\s*(\S+)", text, re.MULTILINE)
        if m:
            superseded.add(m.group(1).zfill(4))
        rows.append((f.stem[:4], f.name, title))

    lines = ["# Decision Index (autogeneriert — nicht von Hand editieren)", ""]
    lines.append("Neu regenerieren: `python3 scripts/agent/manager/log_decision.py --reindex-only`")
    lines.append("")
    lines.append("| # | Status | Titel | Datei |")
    lines.append("|---|---|---|---|")
    for num, fname, title in rows:
        status = "superseded" if num in superseded else "aktiv"
        lines.append(f"| {num} | {status} | {title} | `{fname}` |")
    _INDEX_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--title")
    ap.add_argument("--chosen")
    ap.add_argument("--alt", action="append", default=[])
    ap.add_argument("--rationale")
    ap.add_argument("--role", default="manager")
    ap.add_argument("--supersedes", default=None, help="Nummer der ersetzten Decision, z.B. 0001")
    ap.add_argument("--reindex-only", action="store_true", help="Nur INDEX.md neu bauen, nichts loggen")
    args = ap.parse_args()

    if args.reindex_only:
        _rebuild_index()
        print(f"INDEX.md neu gebaut: {_INDEX_PATH}")
        return

    missing = [n for n in ("title", "chosen", "rationale") if not getattr(args, n)]
    if missing:
        ap.error(f"fehlend: {', '.join('--' + m for m in missing)}")

    num = _next_number()
    path = _write_decision(num, args)
    _rebuild_index()
    print(f"Decision {num:04d} geloggt: {path}")
    print("Index aktualisiert.")


if __name__ == "__main__":
    sys.exit(main())
