#!/usr/bin/env python3
# scripts/agent/build/fix_emit_wrapper_names.py
#
# TODO-offene-probleme.md Punkt 5 (Round 109): 7 emit_<wrapper>()-Namen
# weichen vom tatsächlich emittierten Signal ab. Konvention im gesamten
# Projekt (verifiziert gegen alle NICHT betroffenen Wrapper in PlayerEvents.gd/
# UIEvents.gd/QuestEvents.gd, Round 110): emit_<exakter_Signal-Name>().
#
# Kein pauschaler Automatismus über alle Fälle hinweg — pro Fall wurde vorher
# geprüft (Round 110, Decision-Log), dass die Wrapper-Umbenennung tatsächlich
# die kleinere Änderung ist (Signal-Name erscheint an mehr Stellen: eigene
# Deklaration + alle .connect()-Stellen + der eigene .emit()-Aufruf;
# Wrapper-Name nur an Definition + Call-Sites). Deshalb hartkodierte
# Mapping-Tabelle, kein Regex-Rateschritt über beliebige Namensabweichungen.

from __future__ import annotations

import re
import sys
from pathlib import Path

_AGENT_DIR = Path(__file__).resolve().parents[1]
if str(_AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(_AGENT_DIR))

import service_graph as sg  # noqa: E402
from build.common import BuildSession  # noqa: E402

# alt -> neu, siehe Herleitung in TODO-offene-probleme.md Punkt 5 + Decision-Log Round 110.
RENAMES = {
    "emit_xp": "emit_xp_gained",
    "emit_speed_mod": "emit_speed_modifier_changed",
    "emit_speed_removed": "emit_speed_modifier_removed",
    "emit_notification": "emit_notification_requested",
    "emit_floating_text": "emit_floating_loot_text_requested",
    "emit_objective_updated": "emit_quest_objective_updated",
    "emit_reward_signal": "emit_reward_custom_signal",
}

_PATTERNS = {old: re.compile(rf"\b{re.escape(old)}\b") for old in RENAMES}


def run(apply: bool) -> BuildSession:
    session = BuildSession(apply=apply)
    scan_dirs = [sg.PROJECT_ROOT / "scripts", sg.PROJECT_ROOT / "tests"]
    for d in scan_dirs:
        if not d.exists():
            continue
        for gd in sorted(d.rglob("*.gd")):
            original = gd.read_text(encoding="utf-8", errors="replace")
            new_text = original
            total_count = 0
            for old, new in RENAMES.items():
                new_text, count = _PATTERNS[old].subn(new, new_text)
                total_count += count
            session.apply_change(gd, original, new_text, total_count)
    return session
