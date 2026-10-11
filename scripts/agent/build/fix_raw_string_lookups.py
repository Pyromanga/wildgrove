#!/usr/bin/env python3
# scripts/agent/build/fix_raw_string_lookups.py
#
# Codemod für TODO-offene-probleme.md Punkt 8 / service_graph.py-Finding
# RAW_STRING_SERVICE_LOOKUP: ersetzt .get_service("x")/.require("x")/
# .get_optional("x") durch ServiceKeys.<CONST>, aber NUR wenn die passende
# Konstante nachweislich existiert — dieselbe key_map wie service_graph.py
# (import, kein eigener zweiter Parser -> keine zweite Wahrheitsquelle, die
# auseinanderdriften könnte). ServiceKeys ist global via class_name
# registriert, kein preload()/import in der Zieldatei nötig.
#
# Bewusst der erste Kandidat: reiner Text-für-Text-Tausch ohne
# Kontrollfluss-Änderung, keine Mehrdeutigkeit (Konstante existiert oder
# nicht — kein Ratefall). Dient als Referenzmuster für künftige Module zu
# Punkt 1 (Pfad A->B) und Punkt 2 (Kommentar->extends), die riskanter sind
# und deshalb noch NICHT existieren — siehe README.md in diesem Ordner.

from __future__ import annotations

import re
import sys
from pathlib import Path

_AGENT_DIR = Path(__file__).resolve().parents[1]
if str(_AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(_AGENT_DIR))

import service_graph as sg  # noqa: E402
from build.common import BuildSession  # noqa: E402

# Gruppen: (1) Methodenaufruf+Klammer-Auf, (2) der rohe String-Key, (3) Klammer-Zu.
_RE_CALL = re.compile(r'(\.(?:get_service|require|get_optional)\(\s*)"([a-z_][a-z0-9_]*)"(\s*\))')


def run(apply: bool) -> BuildSession:
    key_map = sg.parse_service_keys(sg.SERVICE_KEYS_GD)
    session = BuildSession(apply=apply)

    for gd in (sg.PROJECT_ROOT / "scripts").rglob("*.gd"):
        if gd == sg.SERVICE_KEYS_GD:
            continue
        original = gd.read_text(encoding="utf-8")
        count = 0

        def _sub(m: re.Match) -> str:
            nonlocal count
            const = key_map.get(m.group(2))
            if const is None:
                return m.group(0)  # keine passende Konstante -> unangetastet, kein Rateversuch
            count += 1
            return f'{m.group(1)}ServiceKeys.{const}{m.group(3)}'

        new_text = _RE_CALL.sub(_sub, original)
        session.apply_change(gd, original, new_text, count)

    return session
