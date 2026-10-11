#!/usr/bin/env python3
# scripts/agent/pet_range_check.py
#
# Deterministischer Checker + Selbsttest für den Bugfix 2026-09-26
# ("Pets können Ressourcen manchmal nicht abbauen/sammeln").
#
# ROOT CAUSE (durch das mitgeschickte Log bestätigt, siehe
# TODO-offene-probleme.md): EntityOrchestrator.resolve_for_player() maß die
# erlaubte Interaktions-Reichweite IMMER ab dem Besitzer-Spieler, nie ab dem
# Pet selbst, das die Aktion tatsächlich ausführt. Log-Beleg (zwei Treffer im
# mitgeschickten Log):
#   resolve_for_player('...'): peer_id=1 außerhalb Reichweite (9.3 > max 4.5).
#   resolve_for_player('...'): peer_id=1 außerhalb Reichweite (7.4 > max 4.5).
# Das Pet stand jeweils nah genug am Ziel (sonst wäre "ACTING" nie erreicht
# worden, siehe PetAbilityComponent._process_harvest()), aber der BESITZER
# stand weiter als max_range entfernt — die Autorität lehnte trotzdem ab.
#
# FIX: EntityOrchestrator.resolve_for_player()/WorldService.
# resolve_and_dispatch_interaction()/request_entity_interaction()/
# NetworkBridge.send_entity_interaction()/_rpc_request_entity_interaction()
# tragen jetzt einen optionalen actor_uuid-Parameter durch. PetAbilityComponent
# übergibt dort seine eigene entity_uuid — die Autorität misst die Reichweite
# dann ab dem Pet. Leer (Default) = unverändertes Verhalten für jede normale
# Spieler-Interaktion (Sicherheits-Äquivalent: actor_uuid zeigt IMMER auf eine
# servereigene registrierte Entity, nie eine roh vom Client gemeldete Position
# — dasselbe Prinzip wie schon für entity_uuid selbst, siehe NetworkContract.gd).
#
# Macht zwei Dinge, stdlib-only (siehe health_contract_check.py/
# interaction_range_check.py für dieselbe Philosophie, kein Godot-Binary hier):
#   1. STRUKTUR-CHECK: die Signaturkette trägt actor_uuid wirklich durch (leicht,
#      versehentlich an einer der 5 Stellen zu vergessen).
#   2. VERHALTENS-SELBSTTEST: reproduziert die exakten Log-Distanzen (9.3/7.4m
#      Besitzer↔Ziel, "eigentlich" aber nah am Pet) gegen unittest.
#
# Usage:
#   python3 scripts/agent/pet_range_check.py
#   python3 scripts/agent/pet_range_check.py --selftest-only
#   python3 scripts/agent/pet_range_check.py --structure-only

from __future__ import annotations

import argparse
import re
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ENTITY_ORCHESTRATOR_PATH = REPO_ROOT / "scripts" / "platform" / "EntityOrchestrator.gd"
WORLD_SERVICE_PATH = REPO_ROOT / "scripts" / "world" / "core" / "WorldService.gd"
NETWORK_BRIDGE_PATH = REPO_ROOT / "scripts" / "networking" / "NetworkBridge.gd"
PET_ABILITY_PATH = REPO_ROOT / "scripts" / "entities" / "animals" / "pets" / "PetAbilityComponent.gd"


# ─────────────────────────────────────────────
# 1. Struktur-Check: actor_uuid wirklich end-to-end durchgereicht
# ─────────────────────────────────────────────

_CHECKS: list[tuple[Path, str, str]] = [
    (
        ENTITY_ORCHESTRATOR_PATH,
        r"func\s+resolve_for_player\([^)]*actor_uuid\s*:\s*String\s*=\s*\"\"[^)]*\)",
        "resolve_for_player() hat keinen actor_uuid-Parameter (mehr) — Kern des Fixes fehlt.",
    ),
    (
        WORLD_SERVICE_PATH,
        r"func\s+resolve_and_dispatch_interaction\([^)]*actor_uuid\s*:\s*String\s*=\s*\"\"[^)]*\)",
        "resolve_and_dispatch_interaction() reicht actor_uuid nicht mehr durch.",
    ),
    (
        WORLD_SERVICE_PATH,
        r"func\s+request_entity_interaction\([^)]*actor_uuid\s*:\s*String\s*=\s*\"\"[^)]*\)",
        "request_entity_interaction() reicht actor_uuid nicht mehr durch.",
    ),
    (
        NETWORK_BRIDGE_PATH,
        r"func\s+send_entity_interaction\([^)]*actor_uuid\s*:\s*String\s*=\s*\"\"[^)]*\)",
        "NetworkBridge.send_entity_interaction() reicht actor_uuid nicht mehr durch (Remote-Clients "
        "würden den Fix wieder verlieren).",
    ),
    (
        NETWORK_BRIDGE_PATH,
        r"func\s+_rpc_request_entity_interaction\([^)]*actor_uuid\s*:\s*String\s*=\s*\"\"[^)]*\)",
        "NetworkBridge._rpc_request_entity_interaction() nimmt actor_uuid nicht mehr entgegen.",
    ),
    (
        PET_ABILITY_PATH,
        r"world\.resolve_entity_uuid\(_pet\)",
        "PetAbilityComponent löst nicht mehr die eigene entity_uuid auf — actor_uuid würde leer bleiben.",
    ),
    (
        PET_ABILITY_PATH,
        r"request_entity_interaction\([^)]*actor_uuid\)",
        "PetAbilityComponent übergibt actor_uuid nicht mehr an request_entity_interaction().",
    ),
]


def check_structure() -> list[str]:
    issues: list[str] = []
    for path, pattern, message in _CHECKS:
        if not path.is_file():
            issues.append(f"Datei nicht gefunden: {path}")
            continue
        text = path.read_text(encoding="utf-8")
        if not re.search(pattern, text):
            rel = path.relative_to(REPO_ROOT)
            issues.append(f"{rel}: {message}")
    return issues


# ─────────────────────────────────────────────
# 2. Verhaltens-Simulation — exakte Log-Szenarien
# ─────────────────────────────────────────────

def resolve_range_old(owner_to_target: float, max_range: float) -> bool:
    """Verhalten VOR dem Fix: immer Besitzer↔Ziel."""
    return owner_to_target <= max_range


def resolve_range_new(owner_to_target: float, pet_to_target: float, max_range: float, actor_is_pet: bool) -> bool:
    """Verhalten NACH dem Fix: actor_uuid gesetzt -> Pet↔Ziel, sonst wie vorher."""
    distance = pet_to_target if actor_is_pet else owner_to_target
    return distance <= max_range


class PetRangeTests(unittest.TestCase):
    def test_regression_log_scenario_9_3m(self) -> None:
        """Exakter erster Log-Treffer: Besitzer 9.3m weg, max_range 4.5m —
        Pet selbst muss dabei längst in ACTING-Reichweite (<=1.4m, siehe
        HARVEST_ARRIVE_RADIUS) gestanden haben, sonst wäre _complete_harvest()
        nie aufgerufen worden."""
        owner_to_target = 9.3
        pet_to_target = 1.2  # < HARVEST_ARRIVE_RADIUS (1.4), sonst nie ACTING erreicht
        max_range = 4.5
        self.assertFalse(resolve_range_old(owner_to_target, max_range),
                          "Altes Verhalten MUSS hier ablehnen — reproduziert den gemeldeten Bug.")
        self.assertTrue(resolve_range_new(owner_to_target, pet_to_target, max_range, actor_is_pet=True),
                         "Neues Verhalten muss mit actor_uuid=Pet annehmen.")

    def test_regression_log_scenario_7_4m(self) -> None:
        """Exakter zweiter Log-Treffer."""
        owner_to_target = 7.4
        pet_to_target = 0.9
        max_range = 4.5
        self.assertFalse(resolve_range_old(owner_to_target, max_range))
        self.assertTrue(resolve_range_new(owner_to_target, pet_to_target, max_range, actor_is_pet=True))

    def test_normal_player_interaction_unaffected(self) -> None:
        """actor_uuid leer (normale Spieler-Interaktion) -> unverändertes
        Verhalten, weiterhin ab dem Spieler selbst gemessen."""
        owner_to_target = 2.0
        max_range = 4.5
        self.assertTrue(resolve_range_new(owner_to_target, pet_to_target=99.0, max_range=max_range, actor_is_pet=False))

    def test_pet_still_rejected_if_truly_out_of_its_own_range(self) -> None:
        """Der Fix hebt die Prüfung nicht auf — steht auch das Pet zu weit weg
        (z.B. Ziel despawnt/Pet wurde weggestoßen), bleibt es eine Ablehnung."""
        owner_to_target = 2.0
        pet_to_target = 6.0
        max_range = 4.5
        self.assertFalse(resolve_range_new(owner_to_target, pet_to_target, max_range, actor_is_pet=True))

    def test_combat_scenario_usually_masked_bug_now_also_fixed(self) -> None:
        """Kampf 'funktionierte gut', weil Gegner dem Besitzer meist nahe
        bleiben — aber dieselbe Lücke bestand strukturell auch dort
        (_do_attack() nutzte denselben Aufruf ohne actor_uuid). Ein Gegner,
        der den Besitzer weiter als max_range hinter sich lässt, während das
        Pet noch dran ist, muss jetzt ebenfalls funktionieren."""
        owner_to_target = 5.2  # Gegner ist dem Besitzer entkommen
        pet_to_target = 1.5    # Pet ist noch dran (ATTACK_RANGE ~1.7)
        max_range = 4.5
        self.assertFalse(resolve_range_old(owner_to_target, max_range))
        self.assertTrue(resolve_range_new(owner_to_target, pet_to_target, max_range, actor_is_pet=True))


# ─────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest-only", action="store_true")
    parser.add_argument("--structure-only", action="store_true")
    args = parser.parse_args()

    exit_code = 0

    if not args.structure_only:
        print("== Verhaltens-Selbsttest (exakte Log-Szenarien) ==")
        suite = unittest.TestLoader().loadTestsFromTestCase(PetRangeTests)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        if not result.wasSuccessful():
            exit_code = 1

    if not args.selftest_only:
        print("\n== Struktur-Check (actor_uuid end-to-end durchgereicht) ==")
        issues = check_structure()
        if issues:
            exit_code = 1
            for issue in issues:
                print(f"  ✗ {issue}")
        else:
            print("  ✓ actor_uuid ist an allen 7 relevanten Stellen vorhanden (Orchestrator → WorldService → NetworkBridge → PetAbilityComponent).")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
