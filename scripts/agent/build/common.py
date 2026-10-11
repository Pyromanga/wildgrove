#!/usr/bin/env python3
# scripts/agent/build/common.py
#
# Gemeinsame Bausteine für alle Build-Module (schreibende Codemods).
# Gegenstück zu service_graph.py (read-only, findet Abweichungen) — Module
# unter scripts/agent/build/ FÜHREN Migrationen durch, die service_graph.py
# als Finding meldet. Kein Modul darf direkt Path.write_text() aufrufen —
# immer über BuildSession.apply_change(), damit Dry-Run/Backup/Summary für
# jedes Modul identisch funktionieren.
#
# Kein Git-Repo in diesem Projekt (kein .git/ gefunden) — deshalb ist ein
# Backup pro geänderter Datei PFLICHT, kein Nice-to-have, und --dry-run ist
# der Default, nicht --apply.
#
# Sicherheitsregeln für jedes Build-Modul:
#   1. Default = --dry-run: nur Diff berechnen und zeigen, nichts schreiben.
#   2. --apply schreibt UND legt <datei>.bak an — nur beim ERSTEN Touch
#      dieser Datei in diesem Lauf (spätere Änderungen an derselben Datei in
#      derselben Session überschreiben das .bak nicht erneut, sonst geht der
#      echte Ursprungszustand verloren).
#   3. Ein Modul liest die betroffene Datei genau einmal selbst (kennt seinen
#      eigenen Kontext — Regex-Match-Objekte etc.) und übergibt Original- UND
#      Neu-Text an apply_change(). common.py liest nichts selbst nach, um
#      keine TOCTOU-Lücke zwischen Modul-Read und Session-Read zu öffnen.
#   4. Kein Modul darf raten. Wenn die Datenlage für eine Ersetzung nicht
#      eindeutig ist (z. B. Konstante existiert nicht), MUSS die Stelle
#      unangetastet bleiben, nicht "wahrscheinlich richtig" ersetzt werden —
#      derselbe Grundsatz wie beim EMIT_WRAPPER_UNRESOLVED-Fix in
#      service_graph.py (TODO-offene-probleme.md Round 109).

from __future__ import annotations

import difflib
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

_AGENT_DIR = Path(__file__).resolve().parent.parent
_SYNTAX_CHECKER = _AGENT_DIR / "check_gdscript_syntax.py"


@dataclass
class ChangeResult:
    path: Path
    replacements: int
    diff: str


@dataclass
class BuildSession:
    """Sammelt alle Änderungen eines Laufs. Ein Modul erzeugt eine Session,
    ruft apply_change() pro geänderter Datei auf; service_build.py druckt am
    Ende print_diffs() + summary()."""
    apply: bool
    changes: list[ChangeResult] = field(default_factory=list)

    def apply_change(self, path: Path, original: str, new_text: str, count: int) -> None:
        if original == new_text or count == 0:
            return  # keine echte Änderung -> kein Eintrag, kein Backup, kein Rauschen
        diff = "".join(difflib.unified_diff(
            original.splitlines(keepends=True),
            new_text.splitlines(keepends=True),
            fromfile=str(path), tofile=f"{path} (neu)",
        ))
        self.changes.append(ChangeResult(path=path, replacements=count, diff=diff))
        if not self.apply:
            return
        # Neue Content-Ordner (z.B. data/items/armor/ beim ersten Rüstungsteil) existieren noch nicht —
        # ohne mkdir bricht ein --apply-Lauf MITTEN in der Batch ab und hinterlässt halb geschriebene Daten.
        path.parent.mkdir(parents=True, exist_ok=True)
        bak = path.with_name(path.name + ".bak")
        if not bak.exists() and original:
            bak.write_text(original, encoding="utf-8")
        path.write_text(new_text, encoding="utf-8")

    def print_diffs(self) -> None:
        for c in self.changes:
            print(c.diff)

    def summary(self) -> None:
        if not self.changes:
            print("Keine Fundstellen — nichts zu tun.")
            return
        total = sum(c.replacements for c in self.changes)
        mode = "ANGEWENDET" if self.apply else "DRY-RUN (nichts geschrieben)"
        print(f"\n{'=' * 70}")
        print(f"{mode}: {len(self.changes)} Datei(en), {total} Ersetzung(en)")
        print("=" * 70)
        for c in self.changes:
            print(f"  {c.path}  ({c.replacements})")
        if self.apply:
            print("\nRevert (kein Git-Repo!) — .bak liegt neben jeder geänderten Datei:")
            for c in self.changes:
                bak = c.path.with_name(c.path.name + ".bak")
                print(f"  cp {bak} {c.path}")
            print("\nDanach: service_graph.py erneut laufen lassen und prüfen, dass die "
                  "erwarteten Findings tatsächlich weniger geworden sind.")
            self._check_syntax()
        else:
            print("\nDry-Run — nichts geschrieben. Mit --apply wirklich ausführen.")

    def _check_syntax(self) -> None:
        """Läuft NUR bei --apply: siehe check_gdscript_syntax.py-Modulkommentar
        für den Vorfall, der diese Absicherung nötig gemacht hat. Ein reiner
        String-Diff sieht Parse-Fehler wie fehlendes '+' zwischen adjazenten
        String-Literalen nicht — das hier ist die Nachkontrolle direkt im
        selben Lauf, nicht erst beim nächsten hochgeladenen Boot-Log."""
        if not _SYNTAX_CHECKER.exists():
            return
        paths = [str(c.path) for c in self.changes]
        result = subprocess.run(
            [sys.executable, str(_SYNTAX_CHECKER), *paths],
            capture_output=True, text=True,
        )
        print(f"\n{'=' * 70}")
        print("SYNTAX-SANITY-CHECK (check_gdscript_syntax.py)")
        print("=" * 70)
        print(result.stdout.strip())
        if result.returncode != 0:
            print(
                "\n⚠ MINDESTENS EIN VERDACHTSFALL — vor dem Ausliefern prüfen! "
                "(Revert-Befehle siehe oben.)"
            )


def fail(msg: str) -> None:
    print(f"FEHLER: {msg}", file=sys.stderr)
    sys.exit(2)
