#!/usr/bin/env python3
# scripts/agent/terrain_material_check.py
#
# Deterministischer Checker + Selbsttest für das Bodenmaterial-System
# (2026-09-26, "überall nur Erde" + "Sand aus der Wüste im Wald ablegen und
# es bleibt Sand").
#
# VORHER: WorldService.request_terrain_edit() vergab beim Graben IMMER das
# Item "dirt", unabhängig vom Biom, und Aufschütten verbrauchte ebenfalls
# immer nur "dirt" — kein Materialbegriff jenseits davon, keine Persistenz.
#
# NACHHER:
#   - BiomeDefinition.surface_material: natürliches Material pro Biom
#     (Wüste -> sand, Gebirge -> gravel, sonst dirt).
#   - TerrainField.get_material_at(): EINE Auflösung für Gameplay (welches
#     Item Graben liefert) UND Optik (TerrainChunkBuilder._biome_color()) —
#     Override (TerrainMaterialLayer) > Kies-Unterboden ab SUBSOIL_DEPTH >
#     natürliches Biom-Material.
#   - TerrainMaterialLayer: dünn besetzte, gespeicherte Schicht für bewusst
#     abgelegtes Material (Geschwister zu TerrainEditLayer).
#   - WorldService.request_terrain_edit(): liest/schreibt diese Schicht.
#
# Macht zwei Dinge, stdlib-only (siehe health_contract_check.py/
# interaction_range_check.py/pet_range_check.py für dieselbe Philosophie):
#   1. STRUKTUR-CHECK über alle beteiligten Dateien.
#   2. VERHALTENS-SELBSTTEST: reine Python-Nachbildung von
#      TerrainField.get_material_at() (Override > Tiefe > Biom), inkl. dem
#      konkreten Szenario aus der Anfrage ("Sand aus der Wüste in einem
#      Wald-Biom ablegen und es bleibt Sand, auch nach erneutem Ausgraben").
#
# Usage:
#   python3 scripts/agent/terrain_material_check.py
#   python3 scripts/agent/terrain_material_check.py --selftest-only
#   python3 scripts/agent/terrain_material_check.py --structure-only

from __future__ import annotations

import argparse
import re
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BIOME_DEFINITION_PATH = REPO_ROOT / "scripts" / "world" / "terrain" / "BiomeDefinition.gd"
BIOME_REGISTRY_PATH = REPO_ROOT / "scripts" / "world" / "terrain" / "BiomeRegistry.gd"
TERRAIN_FIELD_PATH = REPO_ROOT / "scripts" / "world" / "terrain" / "TerrainField.gd"
TERRAIN_MATERIAL_LAYER_PATH = REPO_ROOT / "scripts" / "world" / "terrain" / "TerrainMaterialLayer.gd"
TERRAIN_CHUNK_BUILDER_PATH = REPO_ROOT / "scripts" / "world" / "terrain" / "TerrainChunkBuilder.gd"
WORLD_SERVICE_PATH = REPO_ROOT / "scripts" / "world" / "core" / "WorldService.gd"
WORLD_DATA_PATH = REPO_ROOT / "scripts" / "world" / "core" / "WorldData.gd"
WORLD_SAVE_HANDLER_PATH = REPO_ROOT / "scripts" / "world" / "core" / "WorldSaveHandler.gd"
DATA_MANIFEST_PATH = REPO_ROOT / "scripts" / "persistence" / "DataManifest.gd"


# ─────────────────────────────────────────────
# 1. Struktur-Check
# ─────────────────────────────────────────────

_CHECKS: list[tuple[Path, str, str]] = [
    (BIOME_DEFINITION_PATH, r'@export\s+var\s+surface_material\s*:\s*String', "surface_material-Feld fehlt."),
    (BIOME_REGISTRY_PATH, r'b\.surface_material\s*=\s*"sand"', "Wüste liefert kein surface_material=\"sand\" mehr."),
    (BIOME_REGISTRY_PATH, r'b\.surface_material\s*=\s*"gravel"', "Gebirge liefert kein surface_material=\"gravel\" mehr."),
    (TERRAIN_FIELD_PATH, r'func\s+get_material_at\(', "TerrainField.get_material_at() fehlt."),
    (TERRAIN_FIELD_PATH, r'func\s+set_material_layer\(', "TerrainField.set_material_layer() fehlt."),
    (TERRAIN_FIELD_PATH, r'const\s+SUBSOIL_DEPTH', "Kies-Tiefenschwelle (SUBSOIL_DEPTH) fehlt."),
    (TERRAIN_MATERIAL_LAYER_PATH, r'class_name\s+TerrainMaterialLayer', "TerrainMaterialLayer-Klasse fehlt."),
    (TERRAIN_MATERIAL_LAYER_PATH, r'func\s+to_save\(', "TerrainMaterialLayer.to_save() fehlt — keine Persistenz."),
    (TERRAIN_CHUNK_BUILDER_PATH, r'_field\.get_material_at\(', "_biome_color() nutzt get_material_at() nicht mehr — Optik würde vom Gameplay-Material abweichen."),
    (WORLD_SERVICE_PATH, r'material_id\s*=\s*_terrain\.get_material_at\(center\.x,\s*center\.y\)', "MODE_DIG liest das Material nicht mehr über get_material_at() — würde wieder überall \"dirt\" liefern."),
    (WORLD_SERVICE_PATH, r'materials\.set_overrides\(changed,\s*material_id\)', "MODE_FILL legt das abgelegte Material nicht mehr dauerhaft ab — \"Sand bleibt Sand\" würde nicht mehr gelten."),
    (WORLD_SERVICE_PATH, r'materials\.clear_overrides\(changed\)', "MODE_DIG räumt den Override an der Grabstelle nicht mehr auf."),
    (WORLD_DATA_PATH, r'var\s+terrain_materials\s*:\s*TerrainMaterialLayer', "WorldData.terrain_materials fehlt."),
    (WORLD_SAVE_HANDLER_PATH, r'"terrain_materials"', "WorldSaveHandler speichert terrain_materials nicht (mehr)."),
    (WORLD_SAVE_HANDLER_PATH, r'_data\.terrain_materials\.load_save\(', "WorldSaveHandler lädt terrain_materials nicht (mehr) — Overrides würden Server-Neustarts nicht überleben."),
    (DATA_MANIFEST_PATH, r'data/items/Sand\.tres', "Sand.tres nicht im DataManifest — würde im Export fehlen."),
    (DATA_MANIFEST_PATH, r'data/items/Gravel\.tres', "Gravel.tres nicht im DataManifest — würde im Export fehlen."),
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

    for item_path in (REPO_ROOT / "data" / "items" / "Sand.tres", REPO_ROOT / "data" / "items" / "Gravel.tres"):
        if not item_path.is_file():
            issues.append(f"Item-Resource fehlt: {item_path.relative_to(REPO_ROOT)}")

    return issues


# ─────────────────────────────────────────────
# 2. Verhaltens-Simulation
# ─────────────────────────────────────────────

SUBSOIL_DEPTH = -2.0


class TerrainMaterialSim:
    """1:1-Nachbildung von TerrainField.get_material_at() (Override > Kies-
    Tiefe > natürliches Biom-Material) — rein Python, kein Godot nötig.
    biome_surface: {biome_id: material_id}. depths/overrides: {(x,z): wert}."""

    def __init__(self, biome_surface: dict[str, str]) -> None:
        self.biome_surface = biome_surface
        self.depths: dict[tuple[int, int], float] = {}
        self.overrides: dict[tuple[int, int], str] = {}

    def dig(self, p: tuple[int, int], amount: float = 0.5) -> None:
        self.depths[p] = self.depths.get(p, 0.0) - amount

    def set_override(self, p: tuple[int, int], material_id: str) -> None:
        self.overrides[p] = material_id

    def clear_override(self, p: tuple[int, int]) -> None:
        self.overrides.pop(p, None)

    def get_material_at(self, p: tuple[int, int], biome_id: str) -> str:
        if p in self.overrides:
            return self.overrides[p]
        if self.depths.get(p, 0.0) <= SUBSOIL_DEPTH:
            return "gravel"
        return self.biome_surface.get(biome_id, "dirt")


class TerrainMaterialTests(unittest.TestCase):
    def setUp(self) -> None:
        self.sim = TerrainMaterialSim({"desert": "sand", "mountain": "gravel", "forest": "dirt"})

    def test_desert_yields_sand_by_default(self) -> None:
        self.assertEqual(self.sim.get_material_at((0, 0), "desert"), "sand")

    def test_forest_yields_dirt_by_default(self) -> None:
        self.assertEqual(self.sim.get_material_at((0, 0), "forest"), "dirt")

    def test_deep_dig_reveals_gravel_regardless_of_biome(self) -> None:
        p = (5, 5)
        for _ in range(6):  # 6 * 0.5 = 3.0m, über SUBSOIL_DEPTH (2.0m)
            self.sim.dig(p)
        self.assertEqual(self.sim.get_material_at(p, "forest"), "gravel")
        self.assertEqual(self.sim.get_material_at(p, "desert"), "gravel")

    def test_shallow_dig_stays_natural_material(self) -> None:
        p = (5, 5)
        self.sim.dig(p, amount=0.5)  # nur 0.5m, unter SUBSOIL_DEPTH-Schwelle
        self.assertEqual(self.sim.get_material_at(p, "desert"), "sand")

    def test_core_scenario_sand_stays_sand_in_forest(self) -> None:
        """Exaktes Szenario aus der Anfrage: Sand aus der Wüste ausgraben, im
        Wald ablegen — bleibt dort Sand, auch nachdem der Spieler weg ist."""
        desert_spot = (100, 0)
        forest_spot = (0, 100)

        mined = self.sim.get_material_at(desert_spot, "desert")
        self.assertEqual(mined, "sand")

        # Im Wald ablegen (WorldService.request_terrain_edit(mode=FILL, material_id=mined)).
        self.sim.set_override(forest_spot, mined)
        self.assertEqual(self.sim.get_material_at(forest_spot, "forest"), "sand",
                          "Abgelegter Sand muss im Wald-Biom Sand bleiben, nicht zu Erde werden.")

    def test_digging_up_deposited_material_returns_it_and_clears_override(self) -> None:
        """Gräbt jemand den abgelegten Sand wieder aus, bekommt er Sand zurück
        UND der Override wird entfernt (WorldService: materials.clear_overrides()) —
        erneutes Graben an derselben Stelle liefert danach wieder die
        natürliche (Tiefen-/Biom-)Antwort, nicht nochmal denselben Sand."""
        forest_spot = (0, 100)
        self.sim.set_override(forest_spot, "sand")
        self.assertEqual(self.sim.get_material_at(forest_spot, "forest"), "sand")

        self.sim.clear_override(forest_spot)
        self.sim.dig(forest_spot, amount=0.5)
        self.assertEqual(self.sim.get_material_at(forest_spot, "forest"), "dirt")

    def test_override_wins_over_gravel_depth(self) -> None:
        """Bewusst abgelegtes Material gewinnt IMMER gegen die Tiefen-Heuristik
        — jemand könnte z.B. einen tiefen Schacht bewusst mit Sand verfüllen."""
        p = (1, 1)
        for _ in range(8):
            self.sim.dig(p)  # tief genug für Kies
        self.sim.set_override(p, "sand")
        self.assertEqual(self.sim.get_material_at(p, "forest"), "sand")


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
        print("== Verhaltens-Selbsttest (TerrainMaterialSim) ==")
        suite = unittest.TestLoader().loadTestsFromTestCase(TerrainMaterialTests)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        if not result.wasSuccessful():
            exit_code = 1

    if not args.selftest_only:
        print("\n== Struktur-Check (Bodenmaterial-System end-to-end verdrahtet) ==")
        issues = check_structure()
        if issues:
            exit_code = 1
            for issue in issues:
                print(f"  ✗ {issue}")
        else:
            print(f"  ✓ Alle {len(_CHECKS)} Struktur-Punkte + Item-Resources vorhanden.")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
