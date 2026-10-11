#!/usr/bin/env python3
# scripts/agent/service_build.py
#
# BUILD-COMMAND für Agents — Gegenstück zu service_graph.py. service_graph.py
# ist read-only und meldet Findings; dieses Script FÜHRT die zugehörigen
# Migrationen tatsächlich durch (Codemods), Modul für Modul unter
# scripts/agent/build/ — keine God-Datei, ein Modul pro TODO-Punkt.
#
# Kein Git-Repo in diesem Projekt (kein .git/ gefunden) — deshalb:
#   1. IMMER erst ohne --apply laufen lassen und den Diff lesen.
#   2. --apply legt zusätzlich <datei>.bak neben jeder geänderten Datei an
#      (siehe scripts/agent/build/common.py), das ersetzt aber kein
#      Code-Review vor dem Commit/Zip.
#   3. Nach --apply: service_graph.py erneut laufen lassen und prüfen, dass
#      das erwartete Finding tatsächlich weniger wird — dieses Script prüft
#      das NICHT automatisch selbst (bewusst getrennt: Ausführen und
#      Verifizieren sind zwei unabhängige Schritte).
#
# Module (aktuell verfügbar):
#   raw-strings     — TODO Punkt 8: get_service("x") -> ServiceKeys.X (Round 109)
#   eventbus-direct — TODO Punkt 1: EventBus.<ns>.<sig> -> <accessor>.<ns>().<sig>,
#                      NUR für Dateien die bereits einen Bus-Zugriffspunkt haben
#                      (_bus: IEventBus / _ctx: IUIContext|IAppContext). Dry-Run
#                      zeigt zusätzlich Dateien, die zuerst noch DI-Arbeit
#                      brauchen, bevor dieses Modul dort etwas tun kann (Round 109).
#   emit-wrapper-names — TODO Punkt 5: emit_<wrapper>() -> emit_<signal_name>(),
#                      hartkodierte 7er-Mapping-Tabelle (Round 110, kein Ratefall).
#
# Noch NICHT gebaut (siehe scripts/agent/build/README.md für den Grund pro
# Punkt — überwiegend: zu riskant für einen reinen Text-Tausch ohne
# Zwischenschritt/ADR):
#   Punkt 2 (Kommentar->extends), strukturelle Datei-Verschiebungen/Ordner-Reorg.
#
# Verwendung:
#   python3 scripts/agent/service_build.py raw-strings              # Dry-Run
#   python3 scripts/agent/service_build.py raw-strings --apply       # schreibt + .bak
#   python3 scripts/agent/service_build.py eventbus-direct           # Dry-Run + Bestandsaufnahme
#   python3 scripts/agent/service_build.py eventbus-direct --apply   # schreibt + .bak
#   python3 scripts/agent/service_build.py --list                    # verfügbare Module

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_AGENT_DIR = Path(__file__).resolve().parent
if str(_AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(_AGENT_DIR))

from build import fix_raw_string_lookups, fix_eventbus_direct_access, fix_emit_wrapper_names  # noqa: E402

MODULES = {
    "raw-strings": fix_raw_string_lookups,
    "eventbus-direct": fix_eventbus_direct_access,
    "emit-wrapper-names": fix_emit_wrapper_names,
}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("module", nargs="?", choices=sorted(MODULES), help="Welche Migration ausführen")
    ap.add_argument("--apply", action="store_true", help="Wirklich schreiben (Default: Dry-Run)")
    ap.add_argument("--list", action="store_true", help="Verfügbare Module auflisten und beenden")
    args = ap.parse_args()

    if args.list or not args.module:
        print("Verfügbare Build-Module:")
        for name in sorted(MODULES):
            print(f"  {name}")
        sys.exit(0)

    mod = MODULES[args.module]
    session = mod.run(apply=args.apply)
    session.print_diffs()
    session.summary()


if __name__ == "__main__":
    main()
