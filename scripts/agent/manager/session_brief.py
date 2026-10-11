#!/usr/bin/env python3
# scripts/agent/manager/session_brief.py
#
# Der Einstiegspunkt für jede neue Session (siehe MANAGER.md §0 — "make
# brief" ist das Erste, was passiert, bevor irgendetwas editiert wird).
# Liest data/manager/decisions/ und metrics.jsonl, zeigt eine Kurzfassung.
# Self-healing (MEMORY_PROTOCOL.md): kaputte Einträge werden übersprungen
# und als Warnung gemeldet, nicht als Absturz.
#
# Verwendung:
#   python3 scripts/agent/manager/session_brief.py            # Kurzfassung
#   python3 scripts/agent/manager/session_brief.py --full     # inkl. superseded
#   python3 scripts/agent/manager/session_brief.py --stats    # Metrik-Auswertung (metrik-master)

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[3]
_DECISIONS_DIR = _REPO_ROOT / "data" / "manager" / "decisions"
_METRICS_PATH = _REPO_ROOT / "data" / "manager" / "metrics.jsonl"
_ROADMAP_PATH = _REPO_ROOT / "docs" / "manager" / "ROADMAP.md"

_RECENT_N = 5


def _read_decisions() -> tuple[list[dict], list[str]]:
    warnings: list[str] = []
    entries: list[dict] = []
    if not _DECISIONS_DIR.exists():
        return entries, warnings
    for f in sorted(_DECISIONS_DIR.glob("[0-9][0-9][0-9][0-9]-*.md")):
        try:
            text = f.read_text(encoding="utf-8")
            title_line = next((l for l in text.splitlines() if l.startswith("# ")), None)
            if title_line is None:
                raise ValueError("keine Titelzeile gefunden")
            title = title_line[2:].strip()
            superseded = bool(re.search(r"^Supersedes:", text, re.MULTILINE))
            is_superseded_by_later = False  # gesetzt beim Cross-Check unten
            entries.append({"num": f.stem[:4], "title": title, "file": f.name, "superseded_marker": superseded})
        except Exception as e:  # noqa: BLE001 - bewusst breit, self-healing statt Absturz
            warnings.append(f"⚠ konnte nicht gelesen werden: {f.name} ({e})")
    # Cross-check: welche Nummern werden von anderen Decisions superseded?
    superseded_nums: set[str] = set()
    for f in _DECISIONS_DIR.glob("[0-9][0-9][0-9][0-9]-*.md"):
        try:
            text = f.read_text(encoding="utf-8")
            m = re.search(r"^Supersedes:\s*(\S+)", text, re.MULTILINE)
            if m:
                superseded_nums.add(m.group(1).zfill(4))
        except Exception:  # noqa: BLE001
            continue
    for e in entries:
        e["active"] = e["num"] not in superseded_nums
    return entries, warnings


def _read_metrics() -> tuple[list[dict], list[str]]:
    warnings: list[str] = []
    entries: list[dict] = []
    if not _METRICS_PATH.exists():
        return entries, warnings
    for i, line in enumerate(_METRICS_PATH.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError as e:
            warnings.append(f"⚠ metrics.jsonl Zeile {i} kaputt: {e}")
    return entries, warnings


def _current_phase() -> str:
    if not _ROADMAP_PATH.exists():
        return "(ROADMAP.md fehlt)"
    text = _ROADMAP_PATH.read_text(encoding="utf-8")
    m = re.search(r"^## (Phase \d+ — [^\n(]+)(?:\s*\(([^)]*aktuell[^)]*)\))?", text, re.MULTILINE)
    for line in text.splitlines():
        if line.startswith("## Phase") and "aktuell" in line:
            return line.lstrip("# ").strip()
    return "(kein Phase-Marker mit 'aktuell' gefunden — ROADMAP.md prüfen)"


def _print_brief(full: bool) -> None:
    decisions, dwarn = _read_decisions()
    metrics, mwarn = _read_metrics()

    print("=" * 70)
    print("MANAGER BRIEF")
    print("=" * 70)
    print(f"\nAktuelle Roadmap-Phase: {_current_phase()}")

    active = [d for d in decisions if d["active"]] if not full else decisions
    print(f"\nEntscheidungen ({'alle' if full else 'aktiv'}, letzte {_RECENT_N} von {len(active)}):")
    if not active:
        print("  (keine)")
    for d in active[-_RECENT_N:]:
        print(f"  {d['title']}  ({d['file']})")

    if metrics:
        last = metrics[-_RECENT_N:]
        succ = sum(1 for m in last if m.get("success"))
        print(f"\nLetzte {len(last)} Metriken ({succ}/{len(last)} erfolgreich):")
        for m in last:
            status = "✓" if m.get("success") else "✗"
            print(f"  {status} [{m.get('agent')}] {m.get('task')} ({m.get('duration_seconds', '?')}s)")
    else:
        print("\nKeine Metriken vorhanden.")

    for w in dwarn + mwarn:
        print(f"\n{w}")

    print("\n" + "=" * 70)


def _print_stats() -> None:
    metrics, mwarn = _read_metrics()
    if not metrics:
        print("Keine Metriken vorhanden.")
        return

    by_agent: dict[str, list[dict]] = defaultdict(list)
    for m in metrics:
        by_agent[m.get("agent", "?")].append(m)

    print("=" * 70)
    print("METRIK-AUSWERTUNG (metrik-master)")
    print("=" * 70)
    for agent, entries in sorted(by_agent.items()):
        succ = sum(1 for e in entries if e.get("success"))
        durations = [e.get("duration_seconds", 0) for e in entries]
        avg = sum(durations) / len(durations) if durations else 0
        print(f"\n{agent}: {succ}/{len(entries)} erfolgreich, ⌀ {avg:.0f}s/Task")

    decisions, dwarn = _read_decisions()
    active = sum(1 for d in decisions if d["active"])
    superseded = len(decisions) - active
    print(f"\nDecisions: {len(decisions)} gesamt, {active} aktiv, {superseded} superseded")
    for w in mwarn + dwarn:
        print(f"\n{w}")
    print("\n" + "=" * 70)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--full", action="store_true", help="Auch superseded Decisions anzeigen")
    ap.add_argument("--stats", action="store_true", help="Metrik-Auswertung statt Kurzbrief")
    args = ap.parse_args()

    if args.stats:
        _print_stats()
    else:
        _print_brief(full=args.full)


if __name__ == "__main__":
    sys.exit(main())
