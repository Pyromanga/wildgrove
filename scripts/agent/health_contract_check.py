#!/usr/bin/env python3
# scripts/agent/health_contract_check.py
#
# Deterministischer Checker + Selbsttest für den HealthComponent.max_health-
# Kontrakt (Fix 2026-09-25, siehe TODO-offene-probleme.md).
#
# HINTERGRUND: HealthComponent.max_health war als "Sync current mit max beim
# ERSTEN Setzen" dokumentiert, hat aber jedes Setzen gleich behandelt — jede
# spätere max_health-Änderung an einer bereits laufenden Komponente (Buff,
# Admin-Befehl, künftiges Level-Up-System) hat das aktuelle Leben still-
# schweigend auf das neue Maximum gesetzt/geheilt. Fix: der Setter
# unterscheidet jetzt über is_node_ready() zwischen "erstes Setzen (vor
# _ready(), Konstruktion)" und "Live-Änderung" (siehe HealthComponent.gd für
# den vollen Kommentar).
#
# Diese Datei macht zwei Dinge, bewusst stdlib-only (keine Godot-Engine in
# dieser Sandbox vorhanden, siehe scripts/agent/requirements.txt):
#
#   1. STRUKTUR-CHECK gegen die echte HealthComponent.gd — verhindert, dass
#      der Fix künftig versehentlich wieder rausrefactored wird, ohne dass
#      es jemand merkt (reiner Text-Diff sieht "sauber" aus, siehe
#      check_gdscript_syntax.py-Kopfkommentar für ein reales Beispiel dieser
#      Fehlerklasse).
#   2. VERHALTENS-SELBSTTEST — eine 1:1-Python-Nachbildung der GDScript-
#      Setter-Logik (HealthContractSim), gegen unittest geprüft. Ersetzt
#      keinen echten GDScript-Test (tests/unit/test_health_component_
#      max_health_contract.gd ist die kanonische Spezifikation dafür,
#      GutTest-Stil wie der Rest von tests/unit/), sondern gibt eine
#      SOFORT lauffähige, deterministische Bestätigung, dass die
#      *Kontraktlogik selbst* in sich konsistent ist — unabhängig davon,
#      ob je ein Godot-Testrunner installiert wird (siehe Makefile
#      "test-gd"-Target: aktuell kein Runner vorhanden).
#
# Usage:
#   python3 scripts/agent/health_contract_check.py            # beides, exit 1 bei Fund
#   python3 scripts/agent/health_contract_check.py --selftest-only
#   python3 scripts/agent/health_contract_check.py --structure-only

from __future__ import annotations

import argparse
import re
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HEALTH_COMPONENT_PATH = REPO_ROOT / "scripts" / "entities" / "combat" / "HealthComponent.gd"


# ─────────────────────────────────────────────
# 1. Struktur-Check gegen die echte Datei
# ─────────────────────────────────────────────

_REQUIRED_PATTERNS: list[tuple[str, str]] = [
    (
        r"if\s+not\s+is_node_ready\(\)\s*:",
        "Setter unterscheidet nicht mehr über is_node_ready() zwischen "
        "Erst-Setzen (Konstruktion) und Live-Änderung — Kernstück des Fixes "
        "fehlt oder wurde umbenannt.",
    ),
    (
        r"current_health\s*=\s*min\(\s*current_health\s*,\s*v\s*\)",
        "Live-Änderung klemmt current_health nicht mehr nach unten auf das "
        "neue Maximum (min(current_health, v)) — Regression im else-Zweig.",
    ),
]


def check_structure(path: Path = HEALTH_COMPONENT_PATH) -> list[str]:
    """Regex-Struktur-Check (kein echter Parser, siehe check_gdscript_syntax.py-
    Philosophie) — findet keine Verhaltensregressionen im Detail, aber
    verhindert, dass die zentralen Kontrakt-Zeilen stillschweigend verschwinden."""
    if not path.is_file():
        return [f"Datei nicht gefunden: {path}"]
    text = path.read_text(encoding="utf-8")
    issues: list[str] = []
    for pattern, message in _REQUIRED_PATTERNS:
        if not re.search(pattern, text):
            issues.append(message)
    return issues


# ─────────────────────────────────────────────
# 2. Verhaltens-Simulation (1:1-Nachbildung der GDScript-Logik)
# ─────────────────────────────────────────────

class HealthContractSim:
    """Reine Python-Nachbildung von HealthComponent.max_health/current_health
    NACH dem Fix. Bei jeder künftigen Änderung an HealthComponent.gd muss
    diese Klasse manuell nachgezogen werden — sie ist kein Ersatz für den
    echten GDScript-Test, sondern ein schneller, Godot-freier Beweis, dass
    die GEPLANTE Logik in sich konsistent ist, bevor sie ins .gd-File
    übertragen wird bzw. als Nachweis nach der Übertragung."""

    def __init__(self) -> None:
        self.max_health: int = 50
        self.current_health: int = 50
        self._node_ready: bool = False  # entspricht Godots is_node_ready()

    def set_max_health(self, v: int) -> None:
        self.max_health = v
        if not self._node_ready:
            self.current_health = v
        else:
            self.current_health = min(self.current_health, v)

    def ready(self) -> None:
        """Entspricht _ready(): Sicherheitsnetz + danach 'live'."""
        self.current_health = self.max_health
        self._node_ready = True

    def take_damage(self, amount: int) -> None:
        self.current_health = max(0, self.current_health - amount)

    def reset(self) -> None:
        self.current_health = self.max_health


class HealthContractTests(unittest.TestCase):
    def test_first_set_before_ready_syncs_current(self) -> None:
        """Konstruktions-Pattern (PlayerSetup/EnemyNPC): max_health VOR
        add_child()/_ready() setzen -> current muss mitziehen."""
        sim = HealthContractSim()
        sim.set_max_health(30)
        self.assertEqual(sim.current_health, 30)

    def test_ready_safety_net_syncs_current(self) -> None:
        sim = HealthContractSim()
        sim.set_max_health(80)
        sim.ready()
        self.assertEqual(sim.current_health, 80)

    def test_live_increase_does_not_heal(self) -> None:
        """Der eigentliche Bugfix: ein Buff/Admin-Befehl, der max_health NACH
        _ready() erhöht, darf current NICHT stillschweigend mit hochziehen."""
        sim = HealthContractSim()
        sim.set_max_health(50)
        sim.ready()
        sim.take_damage(30)  # 20/50
        sim.set_max_health(80)  # Buff: 50 -> 80
        self.assertEqual(sim.current_health, 20, "current darf durch einen reinen Max-Anstieg nicht heilen")
        self.assertEqual(sim.max_health, 80)

    def test_live_decrease_clamps_current_down(self) -> None:
        """Ein Debuff/Admin-Befehl, der max_health NACH _ready() senkt, darf
        current höchstens deckeln, nie negativ oder unverändert über dem
        neuen Maximum lassen."""
        sim = HealthContractSim()
        sim.set_max_health(50)
        sim.ready()
        sim.take_damage(10)  # 40/50
        sim.set_max_health(20)  # Debuff: 50 -> 20
        self.assertEqual(sim.current_health, 20, "current muss auf das neue (kleinere) Maximum geklemmt werden")

    def test_live_decrease_above_current_leaves_current_untouched(self) -> None:
        sim = HealthContractSim()
        sim.set_max_health(50)
        sim.ready()
        sim.take_damage(40)  # 10/50
        sim.set_max_health(30)  # immer noch > current(10)
        self.assertEqual(sim.current_health, 10)

    def test_explicit_reset_still_fully_heals(self) -> None:
        """reset() bleibt der explizite, bewusste Weg für 'voll heilen auf
        neues Maximum' — z.B. EnemyNPC-Pool-Reuse nutzt genau das."""
        sim = HealthContractSim()
        sim.set_max_health(50)
        sim.ready()
        sim.take_damage(45)  # 5/50
        sim.set_max_health(80)
        self.assertEqual(sim.current_health, 5)
        sim.reset()
        self.assertEqual(sim.current_health, 80)

    def test_pool_reuse_pattern_matches_enemy_npc(self) -> None:
        """Nachbildung von EnemyNPC._respawn_from_pool()-artigem Code:
        max_health setzen + sofort reset() aufrufen -> IMMER voll geheilt,
        unabhängig vom is_node_ready()-Zustand (deckt EnemyNPC.gd Zeile
        ~487 ab, wo genau dieses Paar aufgerufen wird)."""
        sim = HealthContractSim()
        sim.set_max_health(40)
        sim.ready()
        sim.take_damage(35)  # 5/40, "gestorbener" Gegner im Pool
        sim.set_max_health(40)  # neue Konfiguration beim Pool-Reuse
        sim.reset()
        self.assertEqual(sim.current_health, 40)


# ─────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest-only", action="store_true", help="Nur die Verhaltens-Simulation laufen lassen.")
    parser.add_argument("--structure-only", action="store_true", help="Nur den Struktur-Check gegen HealthComponent.gd laufen lassen.")
    args = parser.parse_args()

    exit_code = 0

    if not args.structure_only:
        print("== Verhaltens-Selbsttest (HealthContractSim) ==")
        suite = unittest.TestLoader().loadTestsFromTestCase(HealthContractTests)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        if not result.wasSuccessful():
            exit_code = 1

    if not args.selftest_only:
        print("\n== Struktur-Check gegen scripts/entities/combat/HealthComponent.gd ==")
        issues = check_structure()
        if issues:
            exit_code = 1
            for issue in issues:
                print(f"  ✗ {issue}")
        else:
            print("  ✓ Kontrakt-Kernzeilen (is_node_ready()-Verzweigung + min()-Klemmung) vorhanden.")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
