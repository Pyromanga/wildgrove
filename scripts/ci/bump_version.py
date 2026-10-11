#!/usr/bin/env python3
"""bump_version.py — APK versionCode/versionName aus der CI-Run-Nummer setzen.

Ersetzt den früheren Inline-Shell-Schritt "Set version code from git commit
count" in build-apk.yml, der doppelt kaputt war (siehe Workflow-Kommentar):
(a) git fetch --depth=1 + rev-list --count HEAD ergab immer 1, (b) das
Ergebnis wurde nie konsumiert. Dieses Script schreibt github.run_number als
monoton steigenden versionCode DIREKT in die export_presets.cfg — die Stelle,
die Godots Android-Export tatsächlich liest.

Lokal nutzbar ohne GitHub-Kontext: --version-code erwartet dann einen Wert
(z.B. Hand-Versionsnummer); ohne Angabe wird die Anzahl der Commits auf dem
aktuellen Branch benutzt (vollständige Clone-History vorausgesetzt).

Exit-Codes: 0 = ok, 1 = keine export_presets.cfg gefunden, 2 = Version
konnte nicht geschrieben werden.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

PRESETS = Path("export_presets.cfg")


def commit_count() -> int:
    """Anzahl der Commits auf HEAD (vollständige History vorausgesetzt)."""
    try:
        out = subprocess.run(["git", "rev-list", "--count", "HEAD"],
                             capture_output=True, text=True, check=True, timeout=30)
        return int(out.stdout.strip())
    except (OSError, subprocess.SubprocessError, ValueError):
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--presets", default=str(PRESETS),
                        help="Pfad zur export_presets.cfg (default: ./export_presets.cfg)")
    parser.add_argument("--version-code", type=int, default=None,
                        help="versionCode (default: CI-Run-Nummer bzw. Commit-Count)")
    parser.add_argument("--version-name", default=None,
                        help="versionName-Suffix (default: 0.1.<versionCode>)")
    args = parser.parse_args()

    presets = Path(args.presets)
    if not presets.is_file():
        print(f"❌ {presets} nicht gefunden — versionCode bleibt unverändert.", file=sys.stderr)
        return 1

    version_code = args.version_code
    if version_code is None:
        env = os.environ.get("GITHUB_RUN_NUMBER")
        if env:
            version_code = int(env)
            print(f"ℹ️ versionCode aus GITHUB_RUN_NUMBER: {version_code}")
        else:
            version_code = commit_count()
            print(f"ℹ️ versionCode aus Commit-Count (kein CI-Kontext): {version_code}")

    version_name = args.version_name or f"0.1.{version_code}"

    text = presets.read_text(encoding="utf-8")
    new_text, n_code = re.subn(r"version/code=\d+", f"version/code={version_code}", text)
    new_text, n_name = re.subn(r"version/name=\"[^\"]*\"", f'version/name="{version_name}"', new_text)

    if n_code == 0 and "version/code=" not in text:
        # Godot schreibt die Version nicht, wenn sie Default ist — anhängen
        # an jeden [preset.N.options]-Block wäre zu fragil; stattdessen
        # Hinweis: Presets einmal im Godot-Editor speichern, dann steht die
        # Zeile drin und dieses Script kann sie patchen.
        print("⚠️ Keine version/code-Zeile in export_presets.cfg — bitte einmal im "
              "Godot-Editor Versionsnummer setzen und speichern, danach patcht "
              "dieses Script sie.", file=sys.stderr)
        return 2

    presets.write_text(new_text, encoding="utf-8")
    print(f"✅ versionCode={version_code}, versionName=\"{version_name}\" "
          f"({n_code}× code, {n_name}× name gepatcht)")
    return 0


if __name__ == "__main__":
    import os  # noqa: E402 — erst nach Argument-Parsing nötig, aber Modul-Level wäre sauberer; bewusst hier, um den Import im CLI-Pfad klein zu halten
    sys.exit(main())
