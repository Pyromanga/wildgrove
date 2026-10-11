#!/usr/bin/env python3
# scripts/agent/adr_tool.py
#
# DEBUG/AUDIT-COMMAND für Agents — strukturierte Bearbeitung/Prüfung von
# docs/adr/*.md statt Ad-hoc-Grep-Skripten, die niemand wiederfindet.
#
# Direkter Auslöser (Round 110): eine ADR-Bestandsaufnahme wurde erst als
# Wegwerf-Script unter /tmp/ gemacht — nicht geloggt, nicht reproduzierbar,
# exakt der Fehler, den MANAGER.md §3 verhindern soll. Dieses Tool ist die
# Korrektur: es lebt im Repo, jeder Aufruf ist wiederholbar, und
# `--log-metric` schreibt den Lauf ins Metrik-Log statt ihn verschwinden zu
# lassen.
#
# Kern-Prinzip: der "Status" eines ADR (geprüft/unverifiziert) wird NICHT
# in einer separaten Datei gepflegt, die veralten kann — er wird bei jedem
# Aufruf live aus dem tatsächlichen Repo-Zustand berechnet (grep nach
# "ADR-NNN" in service_graph.py / scripts/agent/build/). Keine Datenbank,
# die aus dem Takt geraten kann, siehe todo_tool.py-Konvention (ein
# Parse-Schritt pro Aufruf statt gecachtem State).
#
# "Geprüft/enforced" heißt hier bewusst eng: ADR-Nummer taucht in
# service_graph.py (aktive statische Analyse) oder in einem Codemod unter
# scripts/agent/build/ auf. Ein Kommentar in einer .gd-Datei oder eine
# .gd-Testdatei, die referenziert aber (siehe Decision 0005) nicht
# ausführbar ist, zählt NICHT als geprüft — nur als "referenziert".
#
# Befehle:
#   list                         Alle ADRs mit live berechnetem Status
#   show <nnn>                   Volltext + Referenz-Fundstellen eines ADR
#   audit [--log-metric]         Zusammenfassung geprüft/unverifiziert,
#                                 optional als Metrik geloggt (code-tester)
#   deprecate <nnn> --reason ".."  Setzt einen DEPRECATED-Banner in die Datei
#                                 (Backup wird angelegt, Inhalt bleibt sonst
#                                 erhalten — kein Löschen, siehe
#                                 MEMORY_PROTOCOL.md-Prinzip "nicht löschen,
#                                 als ersetzt markieren")
#
# Schreibt niemals ohne Backup (<datei>.bak), analog todo_tool.py.

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ADR_DIR = Path("docs/adr")
SERVICE_GRAPH = Path("scripts/agent/service_graph.py")
BUILD_DIR = Path("scripts/agent/build")
TEST_DIR = Path("tests")
SCRIPTS_DIR = Path("scripts")


@dataclass
class AdrStatus:
    num: str
    path: Path
    title: str
    enforced_by: list[str]
    test_ref_count: int
    comment_ref_count: int
    deprecated: bool

    @property
    def enforced(self) -> bool:
        return bool(self.enforced_by)


def _grep_files(pattern: str, paths: list[Path]) -> list[str]:
    existing = [str(p) for p in paths if p.exists()]
    if not existing:
        return []
    r = subprocess.run(["grep", "-rl", pattern, *existing], capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.strip()]


def _adr_files() -> list[Path]:
    return sorted(p for p in ADR_DIR.glob("*.md") if p.name != "000-index.md")


def _title_of(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    for line in text.splitlines():
        if line.startswith("# "):
            title = line[2:].strip()
            title = re.sub(r"^ADR-\d+\s*[:—-]\s*", "", title)
            return title
    return path.stem


def _status_of(path: Path) -> AdrStatus:
    num = path.name.split("-")[0]
    pat = f"ADR-{num}"
    in_graph = bool(_grep_files(pat, [SERVICE_GRAPH]))
    in_codemod = bool(_grep_files(pat, [BUILD_DIR]))
    test_refs = _grep_files(pat, [TEST_DIR])
    comment_refs = _grep_files(pat, [SCRIPTS_DIR])
    enforced_by = []
    if in_graph:
        enforced_by.append("service_graph.py")
    if in_codemod:
        enforced_by.append("codemod")
    text = path.read_text(encoding="utf-8")
    deprecated = text.startswith("> **DEPRECATED")
    return AdrStatus(num=num, path=path, title=_title_of(path), enforced_by=enforced_by,
                      test_ref_count=len(test_refs), comment_ref_count=len(comment_refs),
                      deprecated=deprecated)


def cmd_list(args) -> None:
    for f in _adr_files():
        s = _status_of(f)
        tag = "DEPRECATED" if s.deprecated else ("ENFORCED" if s.enforced else "unverified")
        extra = f" [{', '.join(s.enforced_by)}]" if s.enforced_by else ""
        print(f"  ADR-{s.num}  {tag:10s} {s.title}{extra}")


def cmd_show(args) -> None:
    f = _find(args.num)
    s = _status_of(f)
    print(f"# ADR-{s.num}  {s.title}")
    print(f"Datei: {f}")
    print(f"Status: {'DEPRECATED' if s.deprecated else ('ENFORCED' if s.enforced else 'unverified')}")
    if s.enforced_by:
        print(f"Enforced durch: {', '.join(s.enforced_by)}")
    print(f"Referenzen in tests/: {s.test_ref_count} (nicht ausführbar, siehe Decision 0005)")
    print(f"Referenzen in scripts/ (Kommentare o.ä.): {s.comment_ref_count}")
    print()
    print(f.read_text(encoding="utf-8"))


def cmd_audit(args) -> None:
    rows = [_status_of(f) for f in _adr_files()]
    enforced = [r for r in rows if r.enforced]
    deprecated = [r for r in rows if r.deprecated]
    unverified = [r for r in rows if not r.enforced and not r.deprecated]

    lines = []
    lines.append("=" * 70)
    lines.append("ADR-AUDIT")
    lines.append("=" * 70)
    lines.append(f"Gesamt: {len(rows)}")
    lines.append(f"Enforced (service_graph.py/Codemod): {len(enforced)}")
    lines.append(f"Deprecated: {len(deprecated)}")
    lines.append(f"Unverifiziert (reine Doku, MANAGER.md §3): {len(unverified)}")
    lines.append("")
    lines.append("Enforced:")
    for r in enforced:
        lines.append(f"  ADR-{r.num}  {r.title}  [{', '.join(r.enforced_by)}]")
    lines.append("")
    lines.append("Unverifiziert (Kandidaten für: Check-Script bauen ODER deprecaten):")
    for r in unverified:
        lines.append(f"  ADR-{r.num}  {r.title}")
    output = "\n".join(lines)
    print(output)

    if args.log_metric:
        subprocess.run([
            sys.executable, "scripts/agent/manager/log_metric.py",
            "--agent", "code-tester",
            "--task", f"ADR-Audit ({len(rows)} ADRs, {len(enforced)} enforced, {len(unverified)} unverifiziert)",
            "--duration", "0",
            "--success",
            "--notes", f"via adr_tool.py audit — {datetime.now(timezone.utc).isoformat()}",
        ], check=False)


def cmd_deprecate(args) -> None:
    f = _find(args.num)
    text = f.read_text(encoding="utf-8")
    if text.startswith("> **DEPRECATED"):
        print(f"ADR-{args.num} ist bereits als DEPRECATED markiert.")
        return
    shutil.copyfile(f, f.with_suffix(f.suffix + ".bak"))
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    banner = f"> **DEPRECATED ({ts}):** {args.reason}\n> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.\n\n"
    f.write_text(banner + text, encoding="utf-8")
    print(f"ADR-{args.num} als DEPRECATED markiert.")
    print(f"Backup: {f}.bak")
    print("Hinweis: als Decision loggen — `make decide` (siehe MANAGER.md §4).")


def _find(num: str) -> Path:
    num = num.zfill(3)
    matches = [f for f in _adr_files() if f.name.split("-")[0] == num]
    if not matches:
        sys.exit(f"Kein ADR mit Nummer {num} gefunden. `list` zeigt alle.")
    return matches[0]


def main() -> None:
    p = argparse.ArgumentParser(description="Strukturierte Bearbeitung/Prüfung von docs/adr/*.md")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="Alle ADRs mit live berechnetem Status")

    sp = sub.add_parser("show", help="Volltext + Referenzen eines ADR")
    sp.add_argument("num", help="ADR-Nummer, z.B. 012 oder 12")

    sp = sub.add_parser("audit", help="Zusammenfassung geprüft/unverifiziert")
    sp.add_argument("--log-metric", action="store_true", help="Lauf als Metrik loggen (code-tester)")

    sp = sub.add_parser("deprecate", help="DEPRECATED-Banner setzen (kein Löschen)")
    sp.add_argument("num")
    sp.add_argument("--reason", required=True)

    args = p.parse_args()
    if args.cmd == "list":
        cmd_list(args)
    elif args.cmd == "show":
        cmd_show(args)
    elif args.cmd == "audit":
        cmd_audit(args)
    elif args.cmd == "deprecate":
        cmd_deprecate(args)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.stderr.close()
