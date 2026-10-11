# res://tests/unit/test_world_build_handler.gd
extends GutTest

## Tests für WorldBuildHandler + WorldTerrainEditor — komplett ohne SceneTree/Inventar:
## alles Externe (Definitionen, Boden, Spawnen, Inventar) wird per Callable gefaket.

const FLOOR := BuildPieceDefinition.Kind.FLOOR
const WALL  := BuildPieceDefinition.Kind.WALL
const ROOF  := BuildPieceDefinition.Kind.ROOF
const DOOR    := BuildPieceDefinition.Kind.DOOR
const WINDOW  := BuildPieceDefinition.Kind.WINDOW
const STAIRS  := BuildPieceDefinition.Kind.STAIRS
const PLAYER := "p1"
const NEAR := Vector3(1.0, 0.0, 8.0)      # Spielerposition, weit genug von Wänden bei z=4
const CHUNK := 64.0
## Zielpunkt für Haus-Tests: fällt in Zelle (0,0) — dieselbe Konvention wie Vector3(1,0,1) bei
## den Einzelteil-Tests oben.
const HOUSE_TARGET := Vector3(1.0, 0.0, 1.0)

var _registry: BuildRegistry
var _layer: TerrainEditLayer
var _editor: WorldTerrainEditor
var _handler: WorldBuildHandler

var _defs: Dictionary = {}
var _houses: Dictionary = {}
var _wallet: Dictionary = {}
var _spawned: Array = []
var _despawned: Array = []
var _refreshed: Array = []

func before_each() -> void:
	_defs = {}
	_houses = {}
	_wallet = {"log_normal": 20, "stone": 20}
	_spawned = []
	_despawned = []
	_refreshed = []

	var floor_def := BuildPieceDefinition.new()
	floor_def.id = "wood_floor"; floor_def.kind = FLOOR; floor_def.cost = {"log_normal": 4}
	var wall_def := BuildPieceDefinition.new()
	wall_def.id = "wood_wall"; wall_def.kind = WALL; wall_def.cost = {"log_normal": 5, "stone": 3}
	wall_def.refund_ratio = 0.5
	var roof_def := BuildPieceDefinition.new()
	roof_def.id = "wood_roof"; roof_def.kind = ROOF; roof_def.height = 1.4; roof_def.cost = {"log_normal": 4}
	var door_def := BuildPieceDefinition.new()
	door_def.id = "wood_door"; door_def.kind = DOOR; door_def.cost = {"log_normal": 3}
	var window_def := BuildPieceDefinition.new()
	window_def.id = "wood_window"; window_def.kind = WINDOW; window_def.cost = {"log_normal": 2}
	var stairs_def := BuildPieceDefinition.new()
	stairs_def.id = "wood_stairs"; stairs_def.kind = STAIRS; stairs_def.height = BuildGrid.LEVEL_HEIGHT
	stairs_def.cost = {"log_normal": 5}
	_defs["wood_floor"] = floor_def
	_defs["wood_wall"] = wall_def
	_defs["wood_roof"] = roof_def
	_defs["wood_door"] = door_def
	_defs["wood_window"] = window_def
	_defs["wood_stairs"] = stairs_def

	# Kleines Testhaus: 1 Zelle, 1 Boden + 2 Wände (genügt für _check_roof — nur EINE Wand an
	# der Zelle wird als Auflager gebraucht) + 1 Dach. Kosten (18 Holz, 6 Stein) passen absichtlich
	# unter das Standard-Wallet (20/20) oben, damit die bestehenden Einzelteil-Tests unverändert
	# bleiben und Haus-Tests trotzdem ohne Extra-Aufladen "affordable" sind.
	var hut := HouseTemplateDefinition.new()
	hut.id = "test_hut"
	hut.display_name = "Testhütte"
	hut.pieces = [
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 0, "dz": 0},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 0, "dz": 0},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 0, "dz": 0},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 0, "dz": 0},
	]
	_houses["test_hut"] = hut

	# Spiegelt data/building/houses/ForestLodge.tres 1:1 (siehe dort) — Regression: die
	# ausgelieferte .tres muss GEGEN DIE ECHTEN Regeln bestehen (Kreuz-Grundriss trägt jede
	# der vier Zimmer-Dachzellen, Treppenzelle bleibt absichtlich ohne eigenes Dach).
	var lodge := HouseTemplateDefinition.new()
	lodge.id = "forest_lodge"
	lodge.display_name = "Waldhütte"
	lodge.pieces = [
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 0, "dz": 0},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 0, "dz": 1},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 0, "dz": 2},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 0, "dz": 3},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 1, "dz": 0},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 1, "dz": 1},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 1, "dz": 2},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 1, "dz": 3},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 2, "dz": 0},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 2, "dz": 1},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 2, "dz": 3},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 3, "dz": 0},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 3, "dz": 1},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 3, "dz": 2},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 3, "dz": 3},
		{"piece_id": "wood_stairs", "kind": STAIRS, "axis": 0, "dx": 2, "dz": 2},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 0, "dz": 0},
		{"piece_id": "wood_door", "kind": DOOR, "axis": 0, "dx": 1, "dz": 0},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 2, "dz": 0},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 3, "dz": 0},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 0, "dz": 4},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 1, "dz": 4},
		{"piece_id": "wood_window", "kind": WINDOW, "axis": 0, "dx": 2, "dz": 4},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 3, "dz": 4},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 0, "dz": 0},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 0, "dz": 1},
		{"piece_id": "wood_window", "kind": WINDOW, "axis": 1, "dx": 0, "dz": 2},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 0, "dz": 3},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 4, "dz": 0},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 4, "dz": 1},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 4, "dz": 2},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 4, "dz": 3},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 0, "dz": 2},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 1, "dz": 2},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 2, "dz": 2},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 3, "dz": 2},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 2, "dz": 0},
		{"piece_id": "wood_door", "kind": DOOR, "axis": 1, "dx": 2, "dz": 1},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 2, "dz": 2},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 1, "dx": 2, "dz": 3},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 0, "dz": 0},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 0, "dz": 1},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 0, "dz": 2},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 0, "dz": 3},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 1, "dz": 0},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 1, "dz": 1},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 1, "dz": 2},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 1, "dz": 3},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 2, "dz": 0},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 2, "dz": 1},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 2, "dz": 3},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 3, "dz": 0},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 3, "dz": 1},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 3, "dz": 2},
		{"piece_id": "wood_roof", "kind": ROOF, "axis": 0, "dx": 3, "dz": 3},
	]
	_houses["forest_lodge"] = lodge

	_registry = BuildRegistry.new()
	_layer = TerrainEditLayer.new()
	_editor = WorldTerrainEditor.new(_layer, _registry, _fake_refresh)
	_handler = WorldBuildHandler.new(
		_registry, _editor, _fake_def, _fake_ground, _fake_spawn, _fake_despawn, CHUNK
	)
	_handler.set_inventory_ops(_fake_can_afford, _fake_pay, _fake_refund)
	_handler.set_house_defs(_fake_house_def)

# ── Fakes (als Methoden statt mehrzeiliger Lambdas: robuster zu parsen) ──

func _fake_refresh(points: Array) -> void:
	_refreshed.append_array(points)

func _fake_def(piece_id: String) -> Variant:
	return _defs.get(piece_id)

func _fake_house_def(template_id: String) -> Variant:
	return _houses.get(template_id)

func _fake_ground(_x: float, _z: float) -> float:
	return 1.0

func _fake_spawn(type_id: String, pos: Vector3, cfg: Dictionary) -> Node3D:
	var n := Node3D.new()
	autofree(n)
	_spawned.append({"type": type_id, "pos": pos, "cfg": cfg})
	return n

func _fake_despawn(node: Node3D) -> void:
	_despawned.append(node)

func _fake_can_afford(_pid: String, cost: Dictionary) -> bool:
	for id: String in cost.keys():
		if int(_wallet.get(id, 0)) < int(cost[id]):
			return false
	return true

func _fake_pay(_pid: String, cost: Dictionary) -> bool:
	for id: String in cost.keys():
		_wallet[id] = int(_wallet.get(id, 0)) - int(cost[id])
	return true

func _fake_refund(_pid: String, items: Dictionary) -> void:
	for id: String in items.keys():
		_wallet[id] = int(_wallet.get(id, 0)) + int(items[id])

# ── Platzieren ──────────────────────────────────

func test_place_floor_succeeds_spawns_and_charges() -> void:
	var res := _handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	assert_true(res["ok"], str(res))
	assert_eq(_registry.count(), 1)
	assert_eq(_spawned.size(), 1)
	assert_eq(_spawned[0]["type"], "build_piece")
	assert_eq(_spawned[0]["cfg"]["piece_id"], "wood_floor")
	assert_eq(_wallet["log_normal"], 16)

func test_place_floor_levels_terrain_and_refreshes_chunks() -> void:
	_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	assert_false(_layer.is_empty(), "Boden ebnet das Gelände darunter ein.")
	assert_false(_refreshed.is_empty(), "Betroffene Chunks werden neu gebaut.")

func test_place_record_has_expected_position() -> void:
	_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	var rec := _registry.get_record("F_0_0")
	assert_eq(rec["x"], 1.0)
	assert_eq(rec["z"], 1.0)
	assert_eq(rec["y"], 1.0)
	assert_eq(rec["owner"], PLAYER)

func test_place_wall_on_ground() -> void:
	var res := _handler.place(PLAYER, "wood_wall", Vector3(1, 0, 4), 0, NEAR)
	assert_true(res["ok"], str(res))
	assert_eq(_wallet["stone"], 17)
	assert_true(_layer.is_empty(), "Wände verändern das Gelände nicht.")

func test_place_unknown_piece_fails() -> void:
	var res := _handler.place(PLAYER, "gibt_es_nicht", Vector3(1, 0, 1), 0, NEAR)
	assert_false(res["ok"])
	assert_eq(res["reason"], "unknown_piece")

func test_place_without_materials_changes_nothing() -> void:
	_wallet["log_normal"] = 1
	var res := _handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	assert_false(res["ok"])
	assert_eq(res["reason"], "no_materials")
	assert_eq(_registry.count(), 0)
	assert_eq(_wallet["log_normal"], 1, "Nichts abgezogen.")
	assert_true(_layer.is_empty(), "Kein Einebnen ohne Bau.")
	assert_eq(_spawned.size(), 0)

func test_place_on_occupied_cell_fails_without_charging() -> void:
	_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	var before: int = _wallet["log_normal"]
	var res := _handler.place(PLAYER, "wood_floor", Vector3(1.5, 0, 0.5), 0, NEAR)
	assert_false(res["ok"])
	assert_eq(res["reason"], "occupied")
	assert_eq(_wallet["log_normal"], before)

func test_place_too_far_fails() -> void:
	var res := _handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, Vector3(100, 0, 100))
	assert_false(res["ok"])
	assert_eq(res["reason"], "too_far")

func test_place_wall_on_player_fails() -> void:
	var res := _handler.place(PLAYER, "wood_wall", Vector3(1, 0, 4), 0, Vector3(1.0, 0.0, 4.1))
	assert_false(res["ok"])
	assert_eq(res["reason"], "player_in_way")

func test_place_wall_on_floor_takes_floor_height() -> void:
	_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 3), 0, NEAR)   # Zelle (0,1), y=1.0
	var res := _handler.place(PLAYER, "wood_wall", Vector3(1, 0, 4), 0, NEAR)
	assert_true(res["ok"], str(res))
	assert_eq(_registry.get_record(res["key"])["y"], 1.0)

func test_place_without_inventory_ops_is_free() -> void:
	_handler.set_inventory_ops(Callable(), Callable(), Callable())
	var res := _handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	assert_true(res["ok"])

# ── Vorschau ────────────────────────────────────

func test_preview_does_not_mutate() -> void:
	var pv := _handler.preview(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	assert_true(pv["ok"])
	assert_eq(_registry.count(), 0)
	assert_eq(_spawned.size(), 0)
	assert_eq(_wallet["log_normal"], 20)
	assert_true(_layer.is_empty())

func test_preview_reports_snap_and_affordability() -> void:
	# Achse 1: x=1.2 → nächste Kante x=2 (Index 1); z=4 → Zelle 2.
	var pv := _handler.preview(PLAYER, "wood_wall", Vector3(1.2, 0, 4), 1, NEAR)
	assert_eq(pv["key"], "W1_1_2")
	assert_almost_eq(pv["yaw"], PI * 0.5, 0.0001)
	assert_true(pv["affordable"])
	_wallet["stone"] = 0
	assert_false(_handler.preview(PLAYER, "wood_wall", Vector3(1.2, 0, 4), 1, NEAR)["affordable"])

func test_preview_matches_place_outcome() -> void:
	_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	var pv := _handler.preview(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	assert_false(pv["ok"])
	assert_eq(pv["reason"], "occupied")

func test_preview_marks_too_far() -> void:
	var pv := _handler.preview(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, Vector3(100, 0, 100))
	assert_false(pv["ok"])
	assert_eq(pv["reason"], "too_far")

func test_preview_unknown_piece() -> void:
	assert_eq(_handler.preview(PLAYER, "x", Vector3.ZERO, 0, NEAR)["reason"], "unknown_piece")

# ── Entfernen ───────────────────────────────────

func test_remove_refunds_and_despawns() -> void:
	var placed := _handler.place(PLAYER, "wood_wall", Vector3(1, 0, 4), 0, NEAR)
	assert_eq(_wallet["log_normal"], 15)
	var res := _handler.remove(PLAYER, placed["key"], NEAR)
	assert_true(res["ok"])
	assert_eq(_registry.count(), 0)
	assert_eq(_despawned.size(), 1)
	assert_eq(_wallet["log_normal"], 17, "5 investiert, 50 % zurück = 2.")
	assert_eq(_wallet["stone"], 18, "3 investiert, 50 % zurück = 1.")

func test_remove_unknown_key_fails() -> void:
	var res := _handler.remove(PLAYER, "F_9_9", NEAR)
	assert_false(res["ok"])

func test_remove_too_far_fails_and_keeps_piece() -> void:
	var placed := _handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	var res := _handler.remove(PLAYER, placed["key"], Vector3(200, 0, 200))
	assert_false(res["ok"])
	assert_eq(res["reason"], "too_far")
	assert_eq(_registry.count(), 1)

func test_place_then_remove_frees_the_cell() -> void:
	var placed := _handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	_handler.remove(PLAYER, placed["key"], NEAR)
	assert_true(_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)["ok"])

# ── Chunk-Ansichten ─────────────────────────────

func test_chunk_unload_despawns_views_but_keeps_data() -> void:
	_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	_handler.on_chunk_unloaded(Vector2i(0, 0))
	assert_eq(_despawned.size(), 1)
	assert_eq(_registry.count(), 1, "Daten bleiben — nur die Ansicht verschwindet.")
	assert_eq(_handler.get_view_count(), 0)

func test_chunk_load_respawns_views_from_data() -> void:
	_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	_handler.on_chunk_unloaded(Vector2i(0, 0))
	_handler.on_chunk_loaded(Vector2i(0, 0))
	assert_eq(_spawned.size(), 2, "Einmal beim Bauen, einmal beim erneuten Laden.")
	assert_eq(_handler.get_view_count(), 1)

func test_chunk_load_does_not_duplicate_existing_view() -> void:
	_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	_handler.on_chunk_loaded(Vector2i(0, 0))
	assert_eq(_spawned.size(), 1)

func test_chunk_events_only_touch_their_own_pieces() -> void:
	_registry.add({"key": "F_far", "piece_id": "wood_floor", "kind": FLOOR, "x": 200.0, "y": 0.0, "z": 0.0, "yaw": 0.0})
	_handler.on_chunk_loaded(Vector2i(0, 0))
	assert_eq(_spawned.size(), 0)
	_handler.on_chunk_loaded(Vector2i(3, 0))   # x=200 → Chunk 3
	assert_eq(_spawned.size(), 1)

# ── Häuser ───────────────────────────────────────

func test_preview_house_happy_path() -> void:
	var pv := _handler.preview_house(PLAYER, "test_hut", HOUSE_TARGET, 0, NEAR)
	assert_true(pv["ok"], str(pv))
	assert_eq((pv["pieces"] as Array).size(), 4, "Boden + 2 Wände + Dach.")
	assert_eq(pv["total_cost"], {"log_normal": 18, "stone": 6})
	assert_true(pv["affordable"])
	# Reine Vorschau: verändert nichts am echten Bestand.
	assert_eq(_registry.count(), 0)
	assert_eq(_wallet["log_normal"], 20)

func test_preview_house_unknown_template() -> void:
	var pv := _handler.preview_house(PLAYER, "gibt_es_nicht", HOUSE_TARGET, 0, NEAR)
	assert_false(pv["ok"])
	assert_eq(pv["reason"], "unknown_house")

func test_preview_house_fails_when_cell_occupied() -> void:
	# Boden der Hütte liegt in Zelle (0,0) — schon belegt.
	_handler.place(PLAYER, "wood_floor", HOUSE_TARGET, 0, NEAR)
	var pv := _handler.preview_house(PLAYER, "test_hut", HOUSE_TARGET, 0, NEAR)
	assert_false(pv["ok"])
	assert_eq(pv["reason"], "occupied")

func test_preview_house_ok_but_not_affordable() -> void:
	_wallet["stone"] = 0
	var pv := _handler.preview_house(PLAYER, "test_hut", HOUSE_TARGET, 0, NEAR)
	assert_true(pv["ok"], "Geometrie passt weiterhin — nur das Material fehlt.")
	assert_false(pv["affordable"])

func test_preview_house_too_far() -> void:
	var pv := _handler.preview_house(PLAYER, "test_hut", HOUSE_TARGET, 0, Vector3(100, 0, 100))
	assert_false(pv["ok"])
	assert_eq(pv["reason"], "too_far")

func test_place_house_succeeds_spawns_and_charges_all_pieces() -> void:
	var res := _handler.place_house(PLAYER, "test_hut", HOUSE_TARGET, 0, NEAR)
	assert_true(res["ok"], str(res))
	assert_eq((res["keys"] as Array).size(), 4)
	assert_eq(_registry.count(), 4)
	assert_eq(_spawned.size(), 4)
	assert_eq(_wallet["log_normal"], 2, "20 - 18.")
	assert_eq(_wallet["stone"], 14, "20 - 6.")

func test_place_house_registers_expected_keys() -> void:
	var res := _handler.place_house(PLAYER, "test_hut", HOUSE_TARGET, 0, NEAR)
	var keys: Array = res["keys"]
	assert_has(keys, "F_0_0")
	assert_has(keys, "W0_0_0")
	assert_has(keys, "W1_0_0")
	assert_has(keys, "R_0_0")

func test_place_house_without_materials_changes_nothing() -> void:
	_wallet["stone"] = 0
	var res := _handler.place_house(PLAYER, "test_hut", HOUSE_TARGET, 0, NEAR)
	assert_false(res["ok"])
	assert_eq(res["reason"], "no_materials")
	assert_eq(_registry.count(), 0, "All-or-nothing: kein einziges Teil gebaut.")
	assert_eq(_spawned.size(), 0)
	assert_eq(_wallet["log_normal"], 20, "Nichts abgezogen.")

func test_place_house_unknown_template_fails() -> void:
	var res := _handler.place_house(PLAYER, "gibt_es_nicht", HOUSE_TARGET, 0, NEAR)
	assert_false(res["ok"])
	assert_eq(res["reason"], "unknown_house")
	assert_eq(_registry.count(), 0)

func test_place_house_too_far_fails() -> void:
	var res := _handler.place_house(PLAYER, "test_hut", HOUSE_TARGET, 0, Vector3(100, 0, 100))
	assert_false(res["ok"])
	assert_eq(res["reason"], "too_far")
	assert_eq(_registry.count(), 0)

func test_place_house_on_occupied_cell_fails_without_charging() -> void:
	_handler.place(PLAYER, "wood_floor", HOUSE_TARGET, 0, NEAR)
	var before: int = _wallet["log_normal"]
	var res := _handler.place_house(PLAYER, "test_hut", HOUSE_TARGET, 0, NEAR)
	assert_false(res["ok"])
	assert_eq(res["reason"], "occupied")
	assert_eq(_wallet["log_normal"], before)
	assert_eq(_registry.count(), 1, "Nur der vorher schon vorhandene Boden, nichts vom Hausversuch.")

func test_house_ghost_pieces_returns_one_entry_per_piece_with_expected_geometry() -> void:
	var geo: Array[Dictionary] = _handler.house_ghost_pieces("test_hut", HOUSE_TARGET, 0, 0)
	assert_eq(geo.size(), 4)

	var floor_piece: Dictionary = geo[0]
	assert_eq(floor_piece["piece_id"], "wood_floor")
	assert_eq(floor_piece["kind"], FLOOR)
	assert_eq((floor_piece["pos"] as Vector3), Vector3(1.0, 1.0, 1.0))

	var roof_piece: Dictionary = geo[3]
	assert_eq(roof_piece["piece_id"], "wood_roof")
	assert_eq(roof_piece["kind"], ROOF)
	var roof_pos: Vector3 = roof_piece["pos"]
	assert_eq(roof_pos.y, 1.0 + BuildGrid.LEVEL_HEIGHT, "Dach sitzt eine Ebene über dem Boden.")

	var wall0_pos: Vector3 = geo[1]["pos"]
	assert_eq(wall0_pos.y, 1.0, "Wand sitzt auf Bodenhöhe, nicht auf Dachhöhe.")

func test_house_ghost_pieces_ignores_registry_occupancy() -> void:
	# Genau der Punkt der Methode: KEINE Regelprüfung — die Zelle ist belegt (siehe
	# test_preview_house_fails_when_cell_occupied() für denselben Fall bei preview_house()),
	# der Geist zeichnet trotzdem die volle, unveränderte Geometrie.
	_handler.place(PLAYER, "wood_floor", HOUSE_TARGET, 0, NEAR)
	var geo: Array[Dictionary] = _handler.house_ghost_pieces("test_hut", HOUSE_TARGET, 0, 0)
	assert_eq(geo.size(), 4)

func test_house_ghost_pieces_unknown_template_returns_empty() -> void:
	var geo: Array[Dictionary] = _handler.house_ghost_pieces("gibt_es_nicht", HOUSE_TARGET, 0, 0)
	assert_eq(geo, [] as Array[Dictionary])

func test_house_ghost_pieces_rotation_changes_wall_axis() -> void:
	# rot_steps=1 dreht die Vorlage um 90° — die axis0-Wand von vorher wird zur axis1-Wand.
	var geo0: Array[Dictionary] = _handler.house_ghost_pieces("test_hut", HOUSE_TARGET, 0, 0)
	var geo1: Array[Dictionary] = _handler.house_ghost_pieces("test_hut", HOUSE_TARGET, 1, 0)
	var pos0: Vector3 = geo0[1]["pos"]
	var pos1: Vector3 = geo1[1]["pos"]
	assert_ne(pos0, pos1, "Gedrehtes Haus positioniert seine Wände anders.")

## "forest_lodge" (siehe data/building/houses/ForestLodge.tres, hier oben 1:1 nachgebaut):
## 4×4 Grundfläche, Kreuz-Grundriss aus vier 2×2-Zimmern, Außentür + 2 Fenster, eine
## Innentür, Treppe in der Mittelzelle statt Boden/Dach dort. Regressionstest GEGEN DIE
## ECHTEN REGELN (BuildPlacementRules.check() via preview_house(), nicht nur die eigene
## Geometrie-Annahme): jede Dachzelle — auch die vier "inneren" Zimmer, die KEINE Außenwand
## berühren — braucht mindestens eine Wand auf einer ihrer vier Kanten (_check_roof), das
## liefert hier ausschließlich das Wandkreuz in der Mitte.
func test_preview_house_forest_lodge_is_fully_buildable() -> void:
	var pv := _handler.preview_house(PLAYER, "forest_lodge", HOUSE_TARGET, 0, NEAR)
	assert_true(pv["ok"], str(pv))
	# 15 Boden + 1 Treppe + 20 Wand + 2 Tür + 2 Fenster + 15 Dach = 55 (siehe ForestLodge.tres).
	assert_eq((pv["pieces"] as Array).size(), 55)

func test_place_house_forest_lodge_builds_all_55_pieces() -> void:
	_wallet["log_normal"] = 500
	_wallet["stone"] = 500
	var res := _handler.place_house(PLAYER, "forest_lodge", HOUSE_TARGET, 0, NEAR)
	assert_true(res["ok"], str(res))
	assert_eq((res["keys"] as Array).size(), 55)
	assert_eq(_registry.count(), 55)

func test_house_ghost_pieces_forest_lodge_stairs_sit_at_floor_height() -> void:
	# Die Treppenzelle hat KEIN Dach in der Vorlage — sie führt bewusst offen nach oben (Ebene 1
	# separat ausbaubar). Reine Geometrie kennt diese Feinheit nicht (kein Regel-/Kind-Sonderfall
	# über "Dach fehlt hier"), zeigt also einfach 55 Geister — das ist ok, siehe Klassenkommentar
	# von house_ghost_pieces() ("Geist zeigt trotzdem etwas Sinnvolles").
	var geo: Array[Dictionary] = _handler.house_ghost_pieces("forest_lodge", HOUSE_TARGET, 0, 0)
	assert_eq(geo.size(), 55)
	var stairs_entries: Array[Dictionary] = geo.filter(func(p): return p["piece_id"] == "wood_stairs")
	assert_eq(stairs_entries.size(), 1)
	var stairs_pos: Vector3 = stairs_entries[0]["pos"]
	assert_eq(stairs_pos.y, 1.0, "Treppe startet auf Bodenhöhe wie ein Boden, nicht auf Dachhöhe.")

# ── WorldTerrainEditor ──────────────────────────

func test_dig_lowers_terrain_and_refreshes() -> void:
	var res := _editor.edit(WorldTerrainEditor.MODE_DIG, Vector3(20, 0, 20))
	assert_true(res["ok"])
	assert_lt(_layer.get_delta_at(20.0, 20.0), 0.0)
	assert_false(_refreshed.is_empty())

func test_fill_raises_terrain() -> void:
	var res := _editor.edit(WorldTerrainEditor.MODE_FILL, Vector3(20, 0, 20))
	assert_true(res["ok"])
	assert_gt(_layer.get_delta_at(20.0, 20.0), 0.0)

func test_dig_blocked_near_building() -> void:
	_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	_refreshed = []
	var res := _editor.edit(WorldTerrainEditor.MODE_DIG, Vector3(3, 0, 1))
	assert_false(res["ok"])
	assert_eq(res["reason"], "building_nearby")
	assert_true(_refreshed.is_empty())

func test_dig_reports_limit_when_nothing_changes() -> void:
	# Der äußere Rand des Pinsels bekommt nur ~0.07 m pro Schlag → Limit (30 m) erst nach
	# einigen hundert Schlägen erreicht; der Kern ist schon nach 60 am Limit.
	for i in 800:
		if not bool(_editor.edit(WorldTerrainEditor.MODE_DIG, Vector3(20, 0, 20))["ok"]):
			break
	var res := _editor.edit(WorldTerrainEditor.MODE_DIG, Vector3(20, 0, 20))
	assert_false(res["ok"])
	assert_eq(res["reason"], "limit")

func test_dig_core_is_flat_and_can_go_deep() -> void:
	for i in 60:
		_editor.edit(WorldTerrainEditor.MODE_DIG, Vector3(20, 0, 20))
	# Kern (3x3 Gitterpunkte um (20,20)) liegt exakt am Tiefenlimit — ebener Grubenboden.
	for dx in [-2.0, 0.0, 2.0]:
		for dz in [-2.0, 0.0, 2.0]:
			assert_eq(_layer.get_delta_at(20.0 + dx, 20.0 + dz), TerrainEditLayer.MAX_DELTA_DOWN)
	assert_lt(TerrainEditLayer.MAX_DELTA_DOWN, -20.0, "Deutlich tiefer als die alten 4 m.")

func test_dig_snaps_to_lattice_point() -> void:
	var res := _editor.edit(WorldTerrainEditor.MODE_DIG, Vector3(20.7, 0, 19.4))
	assert_eq(res["center"], Vector2(20.0, 20.0))

func test_edit_rejects_bad_mode() -> void:
	assert_eq(_editor.edit("explodieren", Vector3.ZERO)["reason"], "bad_mode")

func test_editor_reason_texts_are_specific() -> void:
	for code in ["building_nearby", "limit", "too_far", "no_dirt", "inventory_full", "coop_unsupported"]:
		assert_ne(WorldTerrainEditor.reason_text(code), "Das geht hier nicht.")

# ── WorldTerrainEditor.preview() (TerrainEditGhost-Grundlage, keine Mutation) ────

func test_preview_reports_ok_center_and_radii_without_changing_terrain() -> void:
	var res := _editor.preview(WorldTerrainEditor.MODE_DIG, Vector3(20.7, 0, 19.4))
	assert_true(res["ok"])
	assert_eq(res["center"], Vector2(20.0, 20.0))
	assert_eq(res["radius"], WorldTerrainEditor.BRUSH_RADIUS)
	assert_eq(res["core_radius"], WorldTerrainEditor.CORE_RADIUS)
	assert_eq(_layer.get_delta_at(20.0, 20.0), 0.0, "preview() darf das Gelände nicht verändern.")
	assert_true(_refreshed.is_empty(), "preview() darf keinen Chunk-Refresh auslösen.")

func test_preview_blocked_near_building_matches_edit() -> void:
	_handler.place(PLAYER, "wood_floor", Vector3(1, 0, 1), 0, NEAR)
	var res := _editor.preview(WorldTerrainEditor.MODE_DIG, Vector3(3, 0, 1))
	assert_false(res["ok"])
	assert_eq(res["reason"], "building_nearby")

func test_preview_rejects_bad_mode() -> void:
	assert_eq(_editor.preview("explodieren", Vector3.ZERO)["reason"], "bad_mode")

func test_edit_still_works_after_preview_refactor() -> void:
	# Absicherung für den preview()/edit()-Refactor: edit() muss trotz gemeinsamer Basis mit
	# preview() weiterhin exakt dasselbe Ergebnis liefern wie vorher.
	var res := _editor.edit(WorldTerrainEditor.MODE_FILL, Vector3(20, 0, 20))
	assert_true(res["ok"])
	assert_eq(res["center"], Vector2(20.0, 20.0))
	assert_gt(_layer.get_delta_at(20.0, 20.0), 0.0)

# ── Vorlagen mit Ebenen-Einträgen ("storey") und die echten Berufs-/Tor-Vorlagen ─────────────

func test_preview_house_supports_storey_offset_entries_and_builds_lower_storey_first() -> void:
	var tpl := HouseTemplateDefinition.new()
	tpl.id = "two_level"
	# Absichtlich der Obergeschoss-Boden ZUERST: die Baureihenfolge muss trotzdem Ebene 0 vorziehen.
	tpl.pieces = [
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 0, "dz": 0, "storey": 1},
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 0, "dz": 0},
	]
	_houses["two_level"] = tpl
	var res: Dictionary = _handler.preview_house(PLAYER, "two_level", HOUSE_TARGET, 0, Vector3(NAN, 0.0, NAN))
	assert_true(res["ok"], "reason=%s" % res["reason"])
	var pieces: Array = res["pieces"]
	assert_eq(pieces.size(), 2)
	assert_eq(int(pieces[0]["storey"]), 0, "Wand (Ebene 0) wird zuerst gebaut")
	assert_eq(int(pieces[1]["storey"]), 1)
	assert_almost_eq(float(pieces[1]["y"]), float(pieces[0]["y"]) + BuildGrid.LEVEL_HEIGHT, 0.0001, "Boden liegt auf der Wandkrone")

func test_preview_house_upper_storey_without_support_is_unsupported() -> void:
	var tpl := HouseTemplateDefinition.new()
	tpl.id = "floating"
	tpl.pieces = [{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 0, "dz": 0, "storey": 1}]
	_houses["floating"] = tpl
	var res: Dictionary = _handler.preview_house(PLAYER, "floating", HOUSE_TARGET, 0, Vector3(NAN, 0.0, NAN))
	assert_false(res["ok"])
	assert_eq(res["reason"], "unsupported")

func test_house_ghost_pieces_use_the_entry_storey_for_height() -> void:
	var tpl := HouseTemplateDefinition.new()
	tpl.id = "two_level_ghost"
	tpl.pieces = [
		{"piece_id": "wood_wall", "kind": WALL, "axis": 0, "dx": 0, "dz": 0},
		{"piece_id": "wood_floor", "kind": FLOOR, "axis": -1, "dx": 0, "dz": 0, "storey": 1},
	]
	_houses["two_level_ghost"] = tpl
	var ghosts: Array[Dictionary] = _handler.house_ghost_pieces("two_level_ghost", HOUSE_TARGET, 0)
	assert_eq(ghosts.size(), 2)
	assert_almost_eq((ghosts[1]["pos"] as Vector3).y, (ghosts[0]["pos"] as Vector3).y + BuildGrid.LEVEL_HEIGHT, 0.0001)

## Die AUSGELIEFERTEN .tres (echte Definitionen, echte Regeln) müssen als Ganzes baubar sein — in allen
## vier Drehungen. Regression u. a. für die VillageChurch (zwei Dachzellen ohne Wand → Dach-Überhang)
## und die Wehrgang-Vorlagen (Ebene 1 auf der Mauer).
func test_shipped_building_templates_are_fully_buildable_on_flat_ground() -> void:
	for path: String in DataManifest.BUILD_PIECES:
		var d := load(path) as BuildPieceDefinition
		if d != null:
			_defs[d.id] = d
	for path: String in DataManifest.HOUSE_TEMPLATES:
		var t := load(path) as HouseTemplateDefinition
		if t != null:
			_houses[t.id] = t
	for id: String in ["smithy", "bakery", "carpenter_shop", "market_square", "tavern", "farmstead", "craft_quarter",
			"gate_arch", "city_gate", "village_square", "wall_walk", "city_gate_grand", "village_church",
			"herb_garden", "stable", "barn", "wall_corner", "barracks", "feast_hall", "fortress_yard"]:
		assert_true(_houses.has(id), "%s fehlt in DataManifest.HOUSE_TEMPLATES" % id)
		if not _houses.has(id):
			continue
		for rot in 4:
			var res: Dictionary = _handler.preview_house(PLAYER, id, HOUSE_TARGET, rot, Vector3(NAN, 0.0, NAN))
			assert_true(res["ok"], "%s (Drehung %d) nicht baubar: %s" % [id, rot, res["reason"]])
