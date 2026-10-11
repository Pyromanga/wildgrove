#!/usr/bin/env python3
# scripts/agent/build/fix_eventbus_direct_access.py
#
# Codemod für TODO-offene-probleme.md Punkt 1: EventBus-Zugriff konsolidieren
# auf die IEventBus-Indirektion (ADR-012-Prinzip).
#
# WARUM DIESES MODUL LANGE FEHLTE (Round 109): kein reiner Text-Tausch —
# `EventBus.<ns>.<signal>` -> `<accessor>.<ns>().<signal>` setzt voraus, dass
# die Datei bereits ein Feld hat, das eine IEventBus-Fassade liefert (`_bus:
# IEventBus`, oder `_ctx`/`_app_ctx: IUIContext`/`IAppContext` mit `.bus()`).
# Fehlt dieses Feld, ist das kein Codemod, sondern eine Design-Entscheidung
# (siehe MainMenuController/HUDManager-Migration, Round 109 — dort wurde genau
# dieser Zugriffspunkt erst geschaffen, BEVOR dieses Modul lief).
#
# Dieses Modul rät NICHT, ob ein Zugriffspunkt fehlt oder nur unentdeckt ist:
# es erkennt Felder nach genau den drei etablierten Konventions-Typen (siehe
# _ACCESSOR_FIELD_RE) und lässt jede Datei ohne passendes Feld unangetastet —
# derselbe Grundsatz wie in fix_raw_string_lookups.py (dort: Konstante
# existiert nicht -> unangetastet).
#
# ZWEITER ZWECK (--report): auch ohne --apply zeigt ein Lauf, welche Dateien
# bereits einen Zugriffspunkt HABEN aber noch Direktzugriffe enthalten
# (echte Migrationskandidaten) vs. welche EventBus direkt nutzen OHNE
# Zugriffspunkt (brauchen zuerst DI-Arbeit, kein Fall für dieses Modul) —
# beantwortet TODO Punkt 1s offene Frage "service_graph.py events soll jede
# A-Stelle pro Datei auflisten, damit die Migration messbar ist statt gefühlt".

from __future__ import annotations

import re
import sys
from pathlib import Path

_AGENT_DIR = Path(__file__).resolve().parents[1]
if str(_AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(_AGENT_DIR))

import service_graph as sg  # noqa: E402
from build.common import BuildSession  # noqa: E402

# Dateien, die den EventBus-AutoLoad legitim direkt anfassen dürfen (Bootstrap-
# Ebene selbst, kein Consumer) — deckungsgleich mit
# tests/unit/test_event_bus_access_boundary.gd ALLOWED_FILES. Bewusst hier
# dupliziert statt importiert (GDScript-Test, kein Python) — beide Listen bei
# Änderung zusammen pflegen.
_EXEMPT_SUFFIXES = {
    "scripts/eventbus/EventBus.gd",
    "scripts/eventbus/EventBusAdapter.gd",
    "scripts/platform/ServiceOrchestrator.gd",
    "scripts/platform/Main.gd",
    # Beide tragen einen "justified: Autoload"-Kopfkommentar im Code
    # (Bootstrap-Ebene) — nachgetragen in beide Listen, Round 109.
    "scripts/platform/DedicatedServerBootstrap.gd",
    "scripts/testing/IT03Harness.gd",
}

# Die drei etablierten Konventionen für "diese Klasse hat einen Bus-Zugriffspunkt".
# Reihenfolge = Prioritaet falls mehrere gleichzeitig vorkommen (sollte nicht
# vorkommen, aber falls doch: direktes IEventBus-Feld gewinnt vor Context-Feld).
_ACCESSOR_FIELD_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"var\s+(_\w*bus\w*)\s*:\s*IEventBus\b"), "{field}"),
    (re.compile(r"var\s+(_\w*ctx\w*)\s*:\s*I(?:UI|App)Context\b"), "{field}.bus()"),
]

_DIRECT_RE = re.compile(r"(?<![A-Za-z0-9_])EventBus\.(\w+)\.")


def _find_accessor(text: str) -> str | None:
    for pattern, template in _ACCESSOR_FIELD_PATTERNS:
        m = pattern.search(text)
        if m:
            return template.format(field=m.group(1))
    return None


def _is_exempt(gd: Path) -> bool:
    rel = gd.relative_to(sg.PROJECT_ROOT).as_posix()
    return rel in _EXEMPT_SUFFIXES


def _strip_comment(line: str) -> str:
    """Wie test_event_bus_access_boundary.gd: alles ab dem ersten '#' ist
    Kommentar. Kein String-Literal-Parsing (GDScript-Strings enthalten in der
    Praxis kein '#') — deckt sich mit der Prüfung, die dieses Modul grün
    halten soll."""
    return line.split("#", 1)[0]


def run(apply: bool) -> BuildSession:
    ns_map = sg.parse_event_namespaces(sg.EVENT_BUS_GD)
    session = BuildSession(apply=apply)

    migratable: list[tuple[Path, int]] = []   # hat Accessor, hat Direktzugriffe -> Kandidat
    blocked: list[tuple[Path, int]] = []      # hat Direktzugriffe, aber KEIN Accessor -> DI-Arbeit noetig

    for gd in sorted((sg.PROJECT_ROOT / "scripts").rglob("*.gd")):
        if _is_exempt(gd) or gd.parent == sg.INTERFACES_DIR:
            continue
        original = gd.read_text(encoding="utf-8")

        # Nur echte Codezeilen zaehlen (Kommentare/Docstrings raus), bevor wir
        # ueberhaupt entscheiden ob diese Datei ein Fall fuer dieses Modul ist.
        code_lines = [_strip_comment(l) for l in original.splitlines()]
        direct_count = sum(len(_DIRECT_RE.findall(l)) for l in code_lines)
        if direct_count == 0:
            continue

        accessor = _find_accessor(original)
        if accessor is None:
            blocked.append((gd, direct_count))
            continue
        migratable.append((gd, direct_count))

        count = 0

        def _sub_line(line: str) -> str:
            nonlocal count
            code, _, comment = line.partition("#")
            def _sub(m: re.Match) -> str:
                nonlocal count
                ns = m.group(1)
                if ns not in ns_map:
                    return m.group(0)  # unbekannter Namespace -> unangetastet, kein Ratefall
                count += 1
                return f"{accessor}.{ns}()."
            new_code = _DIRECT_RE.sub(_sub, code)
            return new_code + ("#" + comment if comment else "")

        new_lines = [_sub_line(l) for l in original.splitlines()]
        new_text = "\n".join(new_lines)
        if original.endswith("\n"):
            new_text += "\n"
        session.apply_change(gd, original, new_text, count)

    _print_report(migratable, blocked)
    return session


def _print_report(migratable: list[tuple[Path, int]], blocked: list[tuple[Path, int]]) -> None:
    print(f"\n{'=' * 70}")
    print("EventBus-Direktzugriff — Bestandsaufnahme (TODO Punkt 1)")
    print("=" * 70)
    if migratable:
        print(f"\n✅ {len(migratable)} Datei(en) MIT Zugriffspunkt — Codemod-Kandidaten:")
        for path, n in migratable:
            print(f"   {path.relative_to(sg.PROJECT_ROOT)}  ({n} Stelle(n))")
    if blocked:
        print(f"\n⛔ {len(blocked)} Datei(en) OHNE Zugriffspunkt — brauchen erst DI-Arbeit,")
        print("   kein Fall für diesen Codemod (siehe MainMenuController-Migration Round 109):")
        for path, n in blocked:
            print(f"   {path.relative_to(sg.PROJECT_ROOT)}  ({n} Stelle(n))")
    if not migratable and not blocked:
        print("\nKeine Direktzugriffe außerhalb der Whitelist gefunden.")


if __name__ == "__main__":
    # Direkter Aufruf ohne Umweg über service_build.py — der Report kommt so
    # oder so (dry-run oder --apply), siehe run().
    run(apply=("--apply" in sys.argv))
