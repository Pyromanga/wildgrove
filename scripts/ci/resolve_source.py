#!/usr/bin/env python3
"""resolve_source.py — Projektquelle für CI-Builds auflösen.

Bestimmt, ob ein Build gegen das Repo-Root oder gegen zip/game.zip bauen
soll — die zentrale Logik aus .github/workflows/build-apk.yml (resolve-source
Job), als wiederverwendbares Script extrahiert, damit sie lokal reproduzierbar
und unabhängig vom Workflow-Format wartbar ist.

Regeln (siehe auch Workflow-Kommentar "FIX 2026-10-11"):
  1. Ist zip/game.zip im auslösenden Commit GEÄNDERT worden (git diff
     HEAD^ HEAD) oder gibt es keinen Push-Kontext (--event workflow_dispatch),
     UND existiert das ZIP → ZIP ist die Quelle (Claude-Chat-Workflow pusht
     nur das ZIP).
  2. Sonst, wenn project.godot im Repo-Root liegt → Repo-Root ist die Quelle
     (normale Repo-Commits, z.B. nach restore) — der häufigste Fall.
  3. Fallback: ZIP existiert, Repo-Root hat kein project.godot → ZIP.
  4. Sonst: Fehler.

Output: GITHUB_OUTPUT-kompatibel (key=value Zeilen) plus menschenlesbarer
Zusammenfassung auf stdout. Exit-Code 1 bei Fehler.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

ZIP_PATH = Path("zip/game.zip")


def run_git(args: list[str]) -> str:
    """git-Kommando ausführen, Ausgabe als String (leer bei Fehlern)."""
    try:
        result = subprocess.run(
            ["git", *args], capture_output=True, text=True, check=False, timeout=30
        )
        return result.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def zip_changed_in_head_commit() -> bool:
    """Prüft via git diff HEAD^ HEAD, ob zip/game.zip im letzten Commit geändert wurde.

    Bei fehlender History (frischer Clone, depth=1) oder Fehlern: False —
    dann greift die Repo-Root-Regel, was die sichere Annahme ist.
    """
    changed = run_git(["diff", "--name-only", "HEAD^", "HEAD", "--", str(ZIP_PATH)])
    return bool(changed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--event", default=os.environ.get("GITHUB_EVENT_NAME", "push"),
                        help="GitHub-Event (push/workflow_dispatch/pull_request); default: GITHUB_EVENT_NAME bzw. push")
    parser.add_argument("--output", default=os.environ.get("GITHUB_OUTPUT", ""),
                        help="GITHUB_OUTPUT-Datei für key=value Paare (optional)")
    args = parser.parse_args()

    is_push = args.event == "push"
    zip_exists = ZIP_PATH.is_file()
    repo_root_is_project = Path("project.godot").is_file()

    # Regel 1: ZIP im Trigger-Commit geändert (oder kein Push-Kontext) + vorhanden
    if zip_exists and (not is_push or zip_changed_in_head_commit()):
        reason = ("ZIP im Trigger-Commit geändert" if is_push
                  else f"manueller Trigger ({args.event})")
        print(f"📦 Quelle: zip/game.zip ({reason}).")
        print("   → Der resolve-source-Job entpackt das ZIP nach _project_from_zip/.")
        result = {"project_path": "_project_from_zip", "used_zip": "true"}

    # Regel 2: Repo-Root ist selbst das Projekt (häufigster Fall)
    elif repo_root_is_project:
        print("✅ Quelle: Repo-Root (ZIP im Trigger-Commit unverändert oder nicht vorhanden).")
        result = {"project_path": ".", "used_zip": "false"}

    # Regel 3: Fallback auf ZIP wenn Repo-Root kein Projekt ist
    elif zip_exists:
        print("📦 Repo-Root hat kein project.godot, aber zip/game.zip existiert — nutze ZIP.")
        result = {"project_path": "_project_from_zip", "used_zip": "true"}

    # Regel 4: nichts Brauchbares gefunden
    else:
        print("❌ Weder zip/game.zip noch ein project.godot im Repo-Root gefunden!",
              file=sys.stderr)
        return 1

    # GITHUB_OUTPUT-kompatibel schreiben (Workflow nutzt id: detect)
    if args.output:
        with open(args.output, "a", encoding="utf-8") as f:
            for key, value in result.items():
                f.write(f"{key}={value}\n")

    # Lesbare Ausgabe für Logs und lokale Nutzung
    for key, value in result.items():
        print(f"  {key}={value}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
