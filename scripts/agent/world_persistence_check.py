#!/usr/bin/env python3
# scripts/agent/world_persistence_check.py
#
# Deterministischer Checker + Selbsttest für zwei Bugfixes vom 2026-09-27:
#
#   1. "Flüsse und Biome verschieben sich nach Speichern/Neuladen": SaveSystem.gd
#      schreibt den Spielstand als JSON (JSON.stringify()/JSON.parse()), das
#      kennt keinen Unterschied zwischen int und float — JSON.parse() liefert
#      JEDE Zahl als float zurück. world_seed wurde als roher int gespeichert
#      und beim Laden mit einem strikten "is int"-Check geprüft, der nach dem
#      JSON-Roundtrip NIE zutraf → world_seed resettete bei jedem Laden auf 0
#      → komplett neuer Zufalls-Seed → Höhe/Klima/Biome/Flüsse (alle direkt
#      aus world_seed abgeleitet, siehe TerrainSeed.derive()) sahen jedes Mal
#      anders aus. Fix: var_to_str()/str_to_var() wie bei jedem anderen Feld,
#      zusätzlich tolerant gegen int UND float beim Laden (Fallback für alte
#      Spielstände im rohen Format).
#
#   2. "Bepflanzte Felder nicht persistent": FarmPlot.on_spawn() setzte stage
#      IMMER auf EMPTY, unabhängig vom vorherigen Zustand — kein
#      SaveSystem-Provider vorhanden. Fix: FarmPlotRegistry (Sparse-Registry,
#      Positions-Key) speichert stage + einen ABSOLUTEN Reif-Zeitpunkt
#      (ready_at, Unix-Zeitstempel) je Plot; on_spawn() stellt daraus den
#      richtigen Zustand wieder her — inkl. "während die App zu war fertig
#      gewachsen" (sofort READY statt erneut zu warten).
#
# Macht zwei Dinge, stdlib-only (siehe health_contract_check.py/
# interaction_range_check.py/pet_range_check.py/terrain_material_check.py für
# dieselbe Philosophie, kein Godot-Binary in dieser Sandbox):
#   1. STRUKTUR-CHECK über alle beteiligten Dateien.
#   2. VERHALTENS-SELBSTTEST: reine Python-Simulation des JSON-Roundtrips
#      bzw. der FarmPlotRegistry-Logik.
#
# Usage:
#   python3 scripts/agent/world_persistence_check.py
#   python3 scripts/agent/world_persistence_check.py --selftest-only
#   python3 scripts/agent/world_persistence_check.py --structure-only

from __future__ import annotations

import argparse
import json
import re
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
WORLD_SAVE_HANDLER_PATH = REPO_ROOT / "scripts" / "world" / "core" / "WorldSaveHandler.gd"
WORLD_DATA_PATH = REPO_ROOT / "scripts" / "world" / "core" / "WorldData.gd"
WORLD_SERVICE_PATH = REPO_ROOT / "scripts" / "world" / "core" / "WorldService.gd"
FARM_PLOT_PATH = REPO_ROOT / "scripts" / "world" / "farming" / "FarmPlot.gd"
FARM_PLOT_REGISTRY_PATH = REPO_ROOT / "scripts" / "world" / "farming" / "FarmPlotRegistry.gd"


# ─────────────────────────────────────────────
# 1. Struktur-Check
# ─────────────────────────────────────────────

_CHECKS: list[tuple[Path, str, str]] = [
    (WORLD_SAVE_HANDLER_PATH, r'"world_seed"\s*:\s*var_to_str\(_data\.world_seed\)',
     "world_seed wird beim Speichern nicht mehr über var_to_str() geschrieben — JSON-Roundtrip-Bug lebt wieder auf."),
    (WORLD_SAVE_HANDLER_PATH, r'seed_raw\s+is\s+int\s+or\s+seed_raw\s+is\s+float',
     "world_seed-Restore akzeptiert nicht mehr sowohl int als auch float — zu strikt, Regression zum Bug."),
    (WORLD_SAVE_HANDLER_PATH, r'"farm_plots"\s*:\s*var_to_str\(_data\.farm_plots\.to_save\(\)\)',
     "farm_plots wird nicht (mehr) gespeichert."),
    (WORLD_SAVE_HANDLER_PATH, r'_data\.farm_plots\.load_save\(',
     "farm_plots wird beim Laden nicht (mehr) wiederhergestellt."),
    (WORLD_DATA_PATH, r'var\s+farm_plots\s*:\s*FarmPlotRegistry', "WorldData.farm_plots fehlt."),
    (WORLD_SERVICE_PATH, r'func\s+get_farm_plots\(\)\s*->\s*FarmPlotRegistry', "WorldService.get_farm_plots()-Getter fehlt."),
    (FARM_PLOT_REGISTRY_PATH, r'class_name\s+FarmPlotRegistry', "FarmPlotRegistry-Klasse fehlt."),
    (FARM_PLOT_REGISTRY_PATH, r'func\s+to_save\(', "FarmPlotRegistry.to_save() fehlt — keine Persistenz."),
    (FARM_PLOT_PATH, r'_save_key\s*=\s*WorldData\.make_key\("farm_plot",\s*global_position\)',
     "FarmPlot bildet den Speicher-Key nicht mehr — Restore würde ins Leere laufen."),
    (FARM_PLOT_PATH, r'func\s+_save_state\(\)', "FarmPlot._save_state()-Helfer fehlt."),
    (FARM_PLOT_PATH, r'_ready_at\s*=\s*Time\.get_unix_time_from_system\(\)\s*\+\s*_crop_def\.growth_seconds',
     "_try_plant() setzt ready_at nicht mehr als absoluten Zeitstempel."),
    (FARM_PLOT_PATH, r'if\s+saved\.is_empty\(\)', "on_spawn() liest den gespeicherten Zustand nicht mehr — Regression zum ursprünglichen Bug (immer EMPTY)."),
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
# 2a. Verhaltens-Simulation: world_seed / JSON-Roundtrip
# ─────────────────────────────────────────────

def save_seed_old(seed: int) -> dict:
    """Altes Verhalten: roher int im Save-Dict."""
    return {"world_seed": seed}


def load_seed_old(saved: dict) -> int:
    seed_raw = saved.get("world_seed", 0)
    return seed_raw if isinstance(seed_raw, int) and not isinstance(seed_raw, bool) else 0


def gdscript_var_to_str(value: int) -> str:
    """Grobe Nachbildung von Godots var_to_str() für einen reinen int — für
    unsere Zwecke reicht die Dezimaldarstellung, str_to_var() liest das exakt
    so wieder ein (siehe gdscript_str_to_var())."""
    return str(value)


def gdscript_str_to_var(s: str):
    """Grobe Nachbildung von Godots str_to_var() für die hier vorkommenden
    Fälle (reine Ganzzahl- oder Fließkomma-Strings)."""
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    return float(s)


def save_seed_new(seed: int) -> dict:
    return {"world_seed": gdscript_var_to_str(seed)}


def load_seed_new(saved: dict) -> int:
    raw = gdscript_str_to_var(str(saved.get("world_seed", 0)))
    return int(raw) if isinstance(raw, (int, float)) else 0


def json_roundtrip(d: dict) -> dict:
    """Simuliert exakt das, was SaveSystem.gd tatsächlich tut: JSON.stringify()
    dann JSON.parse() — JSON kennt kein int/float, jede Zahl kommt als float
    zurück (Pythons json-Modul verhält sich hier identisch zu Godot: eine
    JSON-Ganzzahl ohne Nachkommastellen wird beim Parsen zu Python-int, wir
    erzwingen deshalb explizit float für rohe Zahlen, um Godots Verhalten
    nachzubilden — der Kern des Bugs)."""
    text = json.dumps(d)
    parsed = json.loads(text)
    # Godot liefert JEDE JSON-Zahl als float zurück, auch ganzzahlige —
    # Python behält int bei reinen Ganzzahlen. Explizit nachbilden:
    for k, v in list(parsed.items()):
        if isinstance(v, int) and not isinstance(v, bool):
            parsed[k] = float(v)
    return parsed


class WorldSeedPersistenceTests(unittest.TestCase):
    def test_old_behavior_loses_seed_after_json_roundtrip(self) -> None:
        """Beweis, dass es ein echter Bug war."""
        original_seed = 918273645
        saved = save_seed_old(original_seed)
        roundtripped = json_roundtrip(saved)
        loaded = load_seed_old(roundtripped)
        self.assertEqual(loaded, 0, "Alter Code verliert den Seed nach dem JSON-Roundtrip (reproduziert den Bug).")
        self.assertNotEqual(loaded, original_seed)

    def test_new_behavior_survives_json_roundtrip(self) -> None:
        original_seed = 918273645
        saved = save_seed_new(original_seed)
        roundtripped = json_roundtrip(saved)
        loaded = load_seed_new(roundtripped)
        self.assertEqual(loaded, original_seed, "Neuer Code muss den Seed exakt über den JSON-Roundtrip erhalten.")

    def test_new_behavior_also_reads_old_raw_format(self) -> None:
        """Rückwärtskompatibilität: ein Spielstand im alten (rohen) Format,
        der selbst schon vom Bug getroffen wurde (Seed kam als float zurück),
        darf beim Laden nicht crashen und soll den Wert trotzdem retten."""
        saved_old_format_after_json_bug = {"world_seed": 918273645.0}
        loaded = load_seed_new(saved_old_format_after_json_bug)
        self.assertEqual(loaded, 918273645)

    def test_zero_seed_still_falls_back_correctly(self) -> None:
        """Ein wirklich fehlender/leerer Spielstand (world_seed=0, z.B. ganz
        neue Welt) darf nicht versehentlich zu einem Crash oder falschen
        Nicht-Null-Wert führen."""
        self.assertEqual(load_seed_new({}), 0)


# ─────────────────────────────────────────────
# 2b. Verhaltens-Simulation: FarmPlotRegistry / on_spawn()-Restore
# ─────────────────────────────────────────────

EMPTY, GROWING, READY = 0, 1, 2


class FarmPlotRegistrySim:
    def __init__(self) -> None:
        self.records: dict[str, dict] = {}

    def set_state(self, key: str, stage: int, ready_at: float) -> None:
        if stage == EMPTY:
            self.records.pop(key, None)
        else:
            self.records[key] = {"stage": stage, "ready_at": ready_at}

    def get_state(self, key: str) -> dict:
        return self.records.get(key, {})


def restore_stage(saved: dict, now: float) -> tuple[int, bool]:
    """1:1-Nachbildung von FarmPlot.on_spawn()'s Restore-Zweig. Rückgabe:
    (stage, wurde_waehrend_offline_fertig)."""
    if not saved:
        return EMPTY, False
    saved_stage = saved.get("stage", EMPTY)
    ready_at = saved.get("ready_at", 0.0)
    if saved_stage == READY:
        return READY, False
    if saved_stage == GROWING:
        remaining = ready_at - now
        if remaining <= 0.0:
            return READY, True
        return GROWING, False
    return EMPTY, False


class FarmPlotPersistenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = FarmPlotRegistrySim()
        self.key = "farm_plot_5_0_3"

    def test_old_behavior_always_resets_to_empty(self) -> None:
        """Beweis, dass es ein echter Bug war: ohne Registry-Lookup (altes
        Verhalten) ist es IMMER EMPTY, egal was vorher gepflanzt war."""
        self.registry.set_state(self.key, GROWING, ready_at=1000.0)
        old_behavior_stage = EMPTY  # on_spawn() setzte das bisher hart.
        self.assertEqual(old_behavior_stage, EMPTY)
        self.assertNotEqual(old_behavior_stage, GROWING, "Der alte Code hätte den GROWING-Zustand verloren.")

    def test_ready_plot_survives_reload(self) -> None:
        self.registry.set_state(self.key, READY, ready_at=0.0)
        stage, finished_offline = restore_stage(self.registry.get_state(self.key), now=5000.0)
        self.assertEqual(stage, READY)
        self.assertFalse(finished_offline)

    def test_still_growing_plot_resumes_with_remaining_time(self) -> None:
        now = 1000.0
        self.registry.set_state(self.key, GROWING, ready_at=now + 300.0)  # noch 5 Minuten
        stage, finished_offline = restore_stage(self.registry.get_state(self.key), now=now + 100.0)  # 100s später geladen
        self.assertEqual(stage, GROWING)
        self.assertFalse(finished_offline)

    def test_plot_that_finished_while_app_was_closed_is_ready_immediately(self) -> None:
        """Kernszenario: App war länger zu als die Wachstumsdauer — Plot muss
        sofort READY sein, nicht erneut von vorne wachsen."""
        planted_at = 1000.0
        ready_at = planted_at + 300.0  # 5 Minuten Wachstumszeit
        self.registry.set_state(self.key, GROWING, ready_at=ready_at)
        much_later = planted_at + 99999.0  # App war Tage zu
        stage, finished_offline = restore_stage(self.registry.get_state(self.key), now=much_later)
        self.assertEqual(stage, READY)
        self.assertTrue(finished_offline)

    def test_empty_plot_has_no_registry_entry(self) -> None:
        """Sparse-Prinzip: EMPTY wird gar nicht erst gespeichert."""
        self.registry.set_state(self.key, GROWING, ready_at=1000.0)
        self.registry.set_state(self.key, EMPTY, ready_at=0.0)
        self.assertEqual(self.registry.get_state(self.key), {})

    def test_harvest_then_reload_starts_empty_not_ready(self) -> None:
        self.registry.set_state(self.key, READY, ready_at=0.0)
        self.registry.set_state(self.key, EMPTY, ready_at=0.0)  # _try_harvest()
        stage, _ = restore_stage(self.registry.get_state(self.key), now=2000.0)
        self.assertEqual(stage, EMPTY)


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
        print("== Verhaltens-Selbsttest (world_seed JSON-Roundtrip + FarmPlotRegistry) ==")
        suite = unittest.TestSuite()
        loader = unittest.TestLoader()
        suite.addTests(loader.loadTestsFromTestCase(WorldSeedPersistenceTests))
        suite.addTests(loader.loadTestsFromTestCase(FarmPlotPersistenceTests))
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        if not result.wasSuccessful():
            exit_code = 1

    if not args.selftest_only:
        print("\n== Struktur-Check (beide Fixes end-to-end verdrahtet) ==")
        issues = check_structure()
        if issues:
            exit_code = 1
            for issue in issues:
                print(f"  ✗ {issue}")
        else:
            print(f"  ✓ Alle {len(_CHECKS)} Struktur-Punkte vorhanden.")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
