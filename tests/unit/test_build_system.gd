# res://tests/unit/test_build_system.gd
extends GutTest

## Tests für die reine Bau-Logik: BuildGrid, BuildRegistry, BuildPlacementRules,
## BuildPieceDefinition. (Engine-freie Klassen — kein SceneTree nötig.)

const FLOOR   := BuildPieceDefinition.Kind.FLOOR
const WALL    := BuildPieceDefinition.Kind.WALL
const ROOF    := BuildPieceDefinition.Kind.ROOF
const DOOR    := BuildPieceDefinition.Kind.DOOR
const WINDOW  := BuildPieceDefinition.Kind.WINDOW
const STAIRS  := BuildPieceDefinition.Kind.STAIRS
const TARGET  := BuildPieceDefinition.Kind.TARGET

var _registry: BuildRegistry
var _floor_def: BuildPieceDefinition
var _wall_def: BuildPieceDefinition
var _roof_def: BuildPieceDefinition
var _door_def: BuildPieceDefinition
var _window_def: BuildPieceDefinition
var _stairs_def: BuildPieceDefinition
var _target_def: BuildPieceDefinition

func before_each() -> void:
	_registry = BuildRegistry.new()
	_floor_def = BuildPieceDefinition.new()
	_floor_def.id = "wood_floor"
	_floor_def.kind = FLOOR
	_floor_def.cost = {"log_normal": 4}
	_wall_def = BuildPieceDefinition.new()
	_wall_def.id = "wood_wall"
	_wall_def.kind = WALL
	_wall_def.cost = {"log_normal": 5, "stone": 3}
	_wall_def.refund_ratio = 0.5
	_roof_def = BuildPieceDefinition.new()
	_roof_def.id = "wood_roof"
	_roof_def.kind = ROOF
	_roof_def.height = 1.4
	_roof_def.cost = {"log_normal": 4}
	_door_def = BuildPieceDefinition.new()
	_door_def.id = "wood_door"
	_door_def.kind = DOOR
	_door_def.height = 2.5
	_door_def.thickness = 0.2
	_door_def.skirt = 0.8
	_door_def.cost = {"log_normal": 3}
	_window_def = BuildPieceDefinition.new()
	_window_def.id = "wood_window"
	_window_def.kind = WINDOW
	_window_def.height = 2.5
	_window_def.thickness = 0.18
	_window_def.skirt = 0.8
	_window_def.cost = {"log_normal": 2}
	_stairs_def = BuildPieceDefinition.new()
	_stairs_def.id = "wood_stairs"
	_stairs_def.kind = STAIRS
	_stairs_def.height = BuildGrid.LEVEL_HEIGHT
	_stairs_def.cost = {"log_normal": 5}
	_target_def = BuildPieceDefinition.new()
	_target_def.id = "archery_target"
	_target_def.kind = TARGET
	_target_def.height = 1.6
	_target_def.cost = {"log_normal": 2, "fern_fiber": 6}

func _flat(h: float) -> Callable:
	return func(_x: float, _z: float) -> float: return h

func _add_floor(cell: Vector2i, y: float) -> void:
	_registry.add({"key": BuildGrid.floor_key(cell), "piece_id": "wood_floor",
		"kind": FLOOR, "x": 0.0, "y": y, "z": 0.0, "yaw": 0.0, "owner": ""})

# ── BuildGrid ───────────────────────────────────

func test_floor_snaps_to_cell_center() -> void:
	var s := BuildGrid.snap(FLOOR, Vector3(2.9, 0, 5.1), 0)
	assert_eq(s["cell"], Vector2i(1, 2))
	assert_eq(s["center"], Vector2(3.0, 5.0))
	assert_eq(s["key"], "F_1_2")

func test_floor_snap_handles_negative_coordinates() -> void:
	var s := BuildGrid.snap(FLOOR, Vector3(-0.5, 0, -0.5), 0)
	assert_eq(s["cell"], Vector2i(-1, -1))
	assert_eq(s["center"], Vector2(-1.0, -1.0))

func test_floor_ignores_rotation() -> void:
	var a := BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0)
	var b := BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 3)
	assert_eq(a["key"], b["key"])

func test_wall_even_rotation_uses_x_axis_edge() -> void:
	var s := BuildGrid.snap(WALL, Vector3(2.9, 0, 3.1), 0)
	assert_eq(s["axis"], 0)
	# z=3.1 → nächste Kante z=4 (roundi(1.55)=2 → 2*2=4); x=2.9 → Zelle 1 → Mitte x=3.
	assert_eq(s["center"], Vector2(3.0, 4.0))
	assert_eq(s["yaw"], 0.0)

func test_wall_odd_rotation_uses_z_axis_edge() -> void:
	var s := BuildGrid.snap(WALL, Vector3(2.9, 0, 3.1), 1)
	assert_eq(s["axis"], 1)
	# x=2.9 → nächste Kante x=2 (roundi(1.45)=1 → 2); z=3.1 → Zelle 1 → Mitte z=3.
	assert_eq(s["center"], Vector2(2.0, 3.0))
	assert_almost_eq(s["yaw"], PI * 0.5, 0.0001)

func test_wall_negative_rotation_steps_are_valid() -> void:
	assert_eq(BuildGrid.snap(WALL, Vector3(1, 0, 1), -1)["axis"], 1)
	assert_eq(BuildGrid.snap(WALL, Vector3(1, 0, 1), -2)["axis"], 0)

func test_floor_corners_are_four_terrain_lattice_points() -> void:
	var corners := BuildGrid.floor_corner_lattice(Vector2i(3, -1))
	assert_eq(corners.size(), 4)
	assert_true(corners.has(Vector2i(3, -1)))
	assert_true(corners.has(Vector2i(4, 0)))

func test_wall_endpoints_match_axis() -> void:
	var e0 := BuildGrid.wall_endpoints(0, 1, 2)
	assert_eq(e0[0], Vector2(2, 4))
	assert_eq(e0[1], Vector2(4, 4))
	var e1 := BuildGrid.wall_endpoints(1, 1, 2)
	assert_eq(e1[1], Vector2(2, 6))

func test_wall_adjacent_cells() -> void:
	var a0 := BuildGrid.cells_adjacent_to_wall(0, 1, 2)
	assert_true(a0.has(Vector2i(1, 2)) and a0.has(Vector2i(1, 1)))
	var a1 := BuildGrid.cells_adjacent_to_wall(1, 1, 2)
	assert_true(a1.has(Vector2i(1, 2)) and a1.has(Vector2i(0, 2)))

func test_distance_to_wall_segment() -> void:
	# Wand entlang X von (2,4) bis (4,4).
	assert_almost_eq(BuildGrid.distance_to_wall(Vector2(3, 5), 0, 1, 2), 1.0, 0.0001)
	assert_almost_eq(BuildGrid.distance_to_wall(Vector2(6, 4), 0, 1, 2), 2.0, 0.0001)  # jenseits des Endes

func test_quantize_y_rounds_to_step() -> void:
	assert_eq(BuildGrid.quantize_y(1.13), 1.25)
	assert_eq(BuildGrid.quantize_y(1.10), 1.0)

# ── BuildRegistry ───────────────────────────────

func test_registry_add_and_get() -> void:
	assert_true(_registry.add({"key": "F_0_0", "piece_id": "wood_floor", "x": 1.0, "y": 0.0, "z": 1.0}))
	assert_true(_registry.has_key("F_0_0"))
	assert_eq(_registry.get_record("F_0_0")["piece_id"], "wood_floor")
	assert_eq(_registry.count(), 1)

func test_registry_rejects_duplicate_and_empty_key() -> void:
	_registry.add({"key": "F_0_0", "piece_id": "a", "x": 0, "y": 0, "z": 0})
	assert_false(_registry.add({"key": "F_0_0", "piece_id": "b", "x": 0, "y": 0, "z": 0}))
	assert_false(_registry.add({"piece_id": "b"}))
	assert_eq(_registry.count(), 1)

func test_registry_get_record_returns_copy() -> void:
	_registry.add({"key": "F_0_0", "piece_id": "a", "x": 0, "y": 0, "z": 0})
	var rec := _registry.get_record("F_0_0")
	rec["piece_id"] = "manipuliert"
	assert_eq(_registry.get_record("F_0_0")["piece_id"], "a", "Änderungen an der Kopie dürfen die Registry nicht verändern.")

func test_registry_remove_returns_record() -> void:
	_registry.add({"key": "F_0_0", "piece_id": "a", "x": 0, "y": 0, "z": 0})
	assert_eq(_registry.remove("F_0_0")["piece_id"], "a")
	assert_false(_registry.has_key("F_0_0"))
	assert_true(_registry.remove("F_0_0").is_empty())

func test_registry_finds_adjacent_floors_for_wall() -> void:
	_add_floor(Vector2i(1, 1), 2.0)
	# Wand Achse 0 bei (1, 2) grenzt an Zellen (1,2) und (1,1) → findet (1,1).
	assert_eq(_registry.floors_adjacent_to_wall(0, 1, 2).size(), 1)
	assert_eq(_registry.floors_adjacent_to_wall(0, 5, 5).size(), 0)

func test_registry_area_occupied() -> void:
	_registry.add({"key": "F_0_0", "piece_id": "a", "x": 10.0, "y": 0, "z": 10.0})
	assert_true(_registry.is_area_occupied(10.0, 10.0, 1.0))
	assert_true(_registry.is_area_occupied(12.0, 10.0, 1.0), "Toleranz: eine Zelle Puffer.")
	assert_false(_registry.is_area_occupied(40.0, 40.0, 3.5))

func test_registry_records_in_chunk() -> void:
	_registry.add({"key": "a", "piece_id": "x", "x": 5.0, "y": 0, "z": 5.0})      # Chunk (0,0)
	_registry.add({"key": "b", "piece_id": "x", "x": 70.0, "y": 0, "z": 0.0})     # Chunk (1,0)
	var in_zero := _registry.records_in_chunk(Vector2i(0, 0), 64.0)
	assert_eq(in_zero.size(), 1)
	assert_eq(in_zero[0]["key"], "a")

func test_chunk_of_matches_chunk_manager_convention() -> void:
	# ChunkManager: Vector2i(round(x/64), round(z/64)). 31.9 → 0, 32.1 → 1.
	assert_eq(BuildRegistry.chunk_of(31.9, 0.0, 64.0), Vector2i(0, 0))
	assert_eq(BuildRegistry.chunk_of(32.1, 0.0, 64.0), Vector2i(1, 0))
	assert_eq(BuildRegistry.chunk_of(-40.0, 0.0, 64.0), Vector2i(-1, 0))

func test_registry_save_roundtrip_via_var_to_str() -> void:
	_registry.add({"key": "F_1_2", "piece_id": "wood_floor", "kind": FLOOR,
		"x": 3.0, "y": 1.25, "z": 5.0, "yaw": 0.0, "owner": "p1"})
	var restored := BuildRegistry.new()
	restored.load_save(str_to_var(var_to_str(_registry.to_save())))
	assert_eq(restored.count(), 1)
	assert_eq(restored.get_record("F_1_2")["y"], 1.25)

func test_registry_load_skips_invalid_entries() -> void:
	_registry.load_save([
		{"key": "ok", "piece_id": "a", "x": 0, "y": 0, "z": 0},
		{"key": "", "piece_id": "a", "x": 0, "y": 0, "z": 0},
		{"key": "nopiece", "x": 0, "y": 0, "z": 0},
		{"key": "nopos", "piece_id": "a"},
		"müll", 42,
	])
	assert_eq(_registry.count(), 1)
	_registry.load_save("kein array")
	assert_eq(_registry.count(), 0)

# ── BuildPieceDefinition ────────────────────────

func test_refund_rounds_down_and_never_exceeds_cost() -> void:
	assert_eq(_wall_def.refund_for("log_normal"), 2)   # 5 * 0.5 = 2.5 → 2
	assert_eq(_wall_def.refund_for("stone"), 1)        # 3 * 0.5 = 1.5 → 1
	assert_eq(_wall_def.refund_for("gold"), 0)
	_wall_def.refund_ratio = 1.0
	assert_eq(_wall_def.refund_for("log_normal"), 5)

# ── BuildPlacementRules: Boden ──────────────────

func test_floor_on_flat_ground_is_valid_and_levels_terrain() -> void:
	var layer := TerrainEditLayer.new()
	var snap := BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0)
	var res := BuildPlacementRules.check(_floor_def, snap, _registry, _flat(1.0), layer)
	assert_true(res["ok"])
	assert_eq(res["y"], 1.0)
	assert_true(res["level"]["ok"])
	assert_eq((res["level"]["changes"] as Dictionary).size(), 4)
	assert_almost_eq(res["level"]["target_y"], 1.0 - BuildPlacementRules.FLOOR_LIFT, 0.0001)

func test_floor_lift_survives_terrain_quantization() -> void:
	# Auf ebenem Gelände muss das Einebnen ein ECHTES Delta erzeugen (Terrain knapp unter dem
	# Boden), sonst wären Bodenoberkante und Gelände koplanar → Flackern (Z-Fighting).
	var layer := TerrainEditLayer.new()
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry, _flat(1.0), layer)
	var changed := layer.apply_changes(res["level"]["changes"])
	assert_eq(changed.size(), 4)
	assert_lt(layer.get_delta_lattice(0, 0), 0.0)

func test_floor_height_is_quantized_mean_of_corners() -> void:
	var ground := func(x: float, _z: float) -> float: return 1.0 if x < 1.0 else 2.0
	# Zelle (0,0): Ecken x=0 (2 Stück, h=1) und x=2 (2 Stück, h=2) → Mittel 1.5.
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry, ground, null)
	assert_true(res["ok"])
	assert_eq(res["y"], 1.5)

func test_floor_without_layer_skips_leveling() -> void:
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry, _flat(0.0), null)
	assert_true(res["ok"])
	assert_true((res["level"] as Dictionary).is_empty())

func test_floor_rejected_when_occupied() -> void:
	_add_floor(Vector2i(0, 0), 0.0)
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry, _flat(0.0), null)
	assert_false(res["ok"])
	assert_eq(res["reason"], "occupied")

func test_floor_rejected_without_ground() -> void:
	var no_ground := func(_x: float, _z: float) -> float: return NAN
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry, no_ground, null)
	assert_false(res["ok"])
	assert_eq(res["reason"], "no_ground")

func test_floor_rejected_when_terrain_too_steep_to_level() -> void:
	# Ecken sehr unterschiedlich hoch → Mittelwert liegt >4 m von einer Ecke entfernt.
	var ground := func(x: float, _z: float) -> float: return 0.0 if x < 1.0 else 12.0
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry, ground, TerrainEditLayer.new())
	assert_false(res["ok"])
	assert_eq(res["reason"], "too_steep")

# ── BuildPlacementRules: Wand ───────────────────

func test_freestanding_wall_on_flat_ground_is_valid() -> void:
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0), _registry, _flat(1.1))
	assert_true(res["ok"])
	assert_eq(res["y"], 1.0)   # 1.1 → Raster 0.25 → 1.0

func test_wall_on_floor_uses_floor_top() -> void:
	_add_floor(Vector2i(0, 1), 3.0)
	# Wand Achse 0 bei (0, 2)? Grenzt an Zellen (0,2) und (0,1) → Boden (0,1) trägt sie.
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0), _registry, _flat(0.0))
	assert_true(res["ok"])
	assert_eq(res["y"], 3.0)

func test_wall_on_two_floors_uses_higher_one() -> void:
	_add_floor(Vector2i(0, 1), 3.0)
	_add_floor(Vector2i(0, 2), 3.5)
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0), _registry, _flat(0.0))
	assert_eq(res["y"], 3.5)

func test_wall_rejected_when_occupied() -> void:
	var snap := BuildGrid.snap(WALL, Vector3(1, 0, 4), 0)
	_registry.add({"key": snap["key"], "piece_id": "wood_wall", "x": 0, "y": 0, "z": 0})
	var res := BuildPlacementRules.check(_wall_def, snap, _registry, _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "occupied")

func test_freestanding_wall_rejected_on_steep_slope() -> void:
	var ground := func(x: float, _z: float) -> float: return x * 2.0   # 4 m Unterschied über 2 m
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0), _registry, ground)
	assert_false(res["ok"])
	assert_eq(res["reason"], "too_steep")

func test_wall_takes_highest_ground_point_as_base() -> void:
	# Wand liegt zwischen x=0 und x=2: linkes Ende/Mitte auf 0, rechtes Ende auf 1.
	var ground := func(x: float, _z: float) -> float: return 0.0 if x < 1.5 else 1.0
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0), _registry, ground)
	assert_true(res["ok"])
	assert_eq(res["y"], 1.0)

func test_wall_rejected_when_player_stands_in_it() -> void:
	var snap := BuildGrid.snap(WALL, Vector3(1, 0, 4), 0)   # Wand von (0,4) bis (2,4)
	var res := BuildPlacementRules.check(_wall_def, snap, _registry, _flat(0.0), null, Vector3(1.0, 0.0, 4.2))
	assert_false(res["ok"])
	assert_eq(res["reason"], "player_in_way")

func test_wall_ok_when_player_is_clear() -> void:
	var snap := BuildGrid.snap(WALL, Vector3(1, 0, 4), 0)
	var res := BuildPlacementRules.check(_wall_def, snap, _registry, _flat(0.0), null, Vector3(1.0, 0.0, 6.0))
	assert_true(res["ok"])

func test_reason_text_exists_for_all_codes() -> void:
	for code in ["occupied", "no_ground", "too_steep", "unsupported", "player_in_way", "in_water", "too_far", "no_materials", "unknown_piece", "coop_unsupported"]:
		assert_ne(BuildPlacementRules.reason_text(code), "Bauen nicht möglich.", "Code '%s' braucht einen eigenen Text." % code)

# ── Wasser ──────────────────────────────────────

func test_floor_rejected_in_water() -> void:
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry,
		_flat(-1.0), null, Vector3(NAN, NAN, NAN), _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "in_water")

func test_floor_at_shoreline_is_still_too_wet() -> void:
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry,
		_flat(0.1), null, Vector3(NAN, NAN, NAN), _flat(0.0))
	assert_eq(res["reason"], "in_water", "Knapp über dem Spiegel zählt noch als Ufer (MIN_DRY_CLEARANCE).")

func test_floor_on_dry_land_is_fine_with_water_level() -> void:
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry,
		_flat(2.0), null, Vector3(NAN, NAN, NAN), _flat(0.0))
	assert_true(res["ok"])

func test_freestanding_wall_rejected_in_water() -> void:
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0), _registry,
		_flat(-0.5), null, Vector3(NAN, NAN, NAN), _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "in_water")

func test_default_water_level_disables_the_check() -> void:
	# Ohne water_level_fn (Default: ungültiges Callable) verhalten sich alle bisherigen
	# Aufrufe wie vorher — keine Wasserprüfung.
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry, _flat(-5.0), null)
	assert_true(res["ok"])

func test_river_water_level_blocks_building_above_global_sea_level() -> void:
	# Fluss liegt (BUGFIX 2026-09-20) lokal höher als der globale Meeresspiegel — Bauen muss
	# trotzdem blockieren, wenn die Bauhöhe unter DIESEM lokalen Spiegel liegt.
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0), _registry,
		_flat(3.0), null, Vector3(NAN, NAN, NAN), _flat(3.5))
	assert_false(res["ok"])
	assert_eq(res["reason"], "in_water")

# ── Geometrie (gemeinsam für Bauteil und Geist) ──

func test_floor_box_top_is_at_origin() -> void:
	_floor_def.height = 0.3
	_floor_def.skirt = 0.6
	var size := _floor_def.get_box_size(BuildGrid.CELL)
	var center := _floor_def.get_box_center()
	assert_eq(size, Vector3(BuildGrid.CELL, 0.9, BuildGrid.CELL))
	assert_almost_eq(center.y + size.y * 0.5, 0.0, 0.0001, "Oberkante des Bodens liegt bei y=0 (Bauhöhe).")

func test_wall_box_spans_skirt_to_height() -> void:
	_wall_def.height = 2.5
	_wall_def.skirt = 0.8
	_wall_def.thickness = 0.25
	var size := _wall_def.get_box_size(BuildGrid.CELL)
	var center := _wall_def.get_box_center()
	assert_eq(size, Vector3(BuildGrid.CELL, 3.3, 0.25))
	assert_almost_eq(center.y - size.y * 0.5, -0.8, 0.0001, "Unterkante = -skirt")
	assert_almost_eq(center.y + size.y * 0.5, 2.5, 0.0001, "Oberkante = +height")

# ── Ebenen (storey) ─────────────────────────────

func _add_wall(axis: int, cx: int, cz: int, y: float, storey: int = 0) -> void:
	_registry.add({"key": BuildGrid.wall_key(axis, cx, cz, storey), "piece_id": "wood_wall",
		"kind": WALL, "x": 0.0, "y": y, "z": 0.0, "yaw": 0.0, "owner": "", "storey": storey})

func _add_floor_at(cell: Vector2i, y: float, storey: int) -> void:
	_registry.add({"key": BuildGrid.floor_key(cell, storey), "piece_id": "wood_floor",
		"kind": FLOOR, "x": 0.0, "y": y, "z": 0.0, "yaw": 0.0, "owner": "", "storey": storey})

func test_storey_zero_keys_are_unchanged() -> void:
	assert_eq(BuildGrid.floor_key(Vector2i(2, 3)), "F_2_3")
	assert_eq(BuildGrid.wall_key(1, -1, 4), "W1_-1_4")
	assert_eq(BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0)["key"], "F_0_0")

func test_upper_storey_keys_get_suffix() -> void:
	assert_eq(BuildGrid.floor_key(Vector2i(2, 3), 1), "F_2_3_L1")
	assert_eq(BuildGrid.wall_key(0, -1, 4, 2), "W0_-1_4_L2")
	assert_eq(BuildGrid.snap(WALL, Vector3(1, 0, 4), 0, 1)["key"], "W0_0_2_L1")

func test_snap_clamps_storey() -> void:
	assert_eq(BuildGrid.snap(FLOOR, Vector3.ZERO, 0, 99)["storey"], BuildGrid.MAX_STOREY)
	assert_eq(BuildGrid.snap(FLOOR, Vector3.ZERO, 0, -3)["storey"], 0)

func test_parse_key_roundtrip() -> void:
	var f := BuildGrid.parse_key(BuildGrid.floor_key(Vector2i(-2, 5), 2))
	assert_eq(f["kind"], FLOOR)
	assert_eq(f["x"], -2)
	assert_eq(f["z"], 5)
	assert_eq(f["storey"], 2)
	var w := BuildGrid.parse_key(BuildGrid.wall_key(1, 3, -4))
	assert_eq(w["kind"], WALL)
	assert_eq(w["axis"], 1)
	assert_eq(w["storey"], 0)
	assert_true(BuildGrid.parse_key("Quatsch").is_empty())

func test_upper_floor_needs_wall_below() -> void:
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0, 1), _registry, _flat(0.0), null)
	assert_false(res["ok"])
	assert_eq(res["reason"], "unsupported")

func test_upper_floor_rests_on_wall_top() -> void:
	_add_wall(0, 0, 0, 1.0)   # Wand auf Kante z=0 der Zelle (0,0)
	var res := BuildPlacementRules.check(_floor_def, BuildGrid.snap(FLOOR, Vector3(1, 0, 1), 0, 1), _registry, _flat(0.0), null)
	assert_true(res["ok"])
	assert_eq(res["y"], 1.0 + BuildGrid.LEVEL_HEIGHT)

func _upper_floor_check(cx: int, cz: int, storey: int = 1) -> Dictionary:
	var snap := BuildGrid.snap_from_cell(FLOOR, -1, cx, cz, storey)
	return BuildPlacementRules.check(_floor_def, snap, _registry, _flat(0.0), null)

## Auskragung (Balkon/Erker): Boden ohne eigene Wand darunter, aber lückenlose Bodenkette bis Reichweite 3.
func test_upper_floor_cantilevers_up_to_three_cells() -> void:
	_add_wall(0, 0, 0, 1.0)                              # trägt Zelle (0,0) auf Ebene 1
	var top: float = 1.0 + BuildGrid.LEVEL_HEIGHT
	_add_floor_at(Vector2i(0, 0), top, 1)
	_add_floor_at(Vector2i(1, 0), top, 1)
	_add_floor_at(Vector2i(2, 0), top, 1)
	var res := _upper_floor_check(3, 0)
	assert_true(res["ok"], "drei Zellen Auskragung")
	assert_almost_eq(float(res["y"]), top, 0.0001, "Oberkante vom tragenden Boden")

func test_upper_floor_cantilever_stops_at_reach_three() -> void:
	_add_wall(0, 0, 0, 1.0)
	var top: float = 1.0 + BuildGrid.LEVEL_HEIGHT
	for x in 4:
		_add_floor_at(Vector2i(x, 0), top, 1)
	var res := _upper_floor_check(4, 0)
	assert_false(res["ok"])
	assert_eq(res["reason"], "unsupported")

func test_upper_floor_cantilever_needs_unbroken_chain_and_same_storey() -> void:
	_add_wall(0, 0, 0, 1.0)
	var top: float = 1.0 + BuildGrid.LEVEL_HEIGHT
	_add_floor_at(Vector2i(0, 0), top, 1)
	assert_false(_upper_floor_check(2, 0)["ok"], "Lücke bei (1,0)")
	assert_false(_upper_floor_check(1, 0, 2)["ok"], "Boden auf anderer Ebene trägt nicht")

func test_has_dependents_for_upper_floor_carrying_a_cantilever() -> void:
	_add_wall(0, 0, 0, 1.0)
	var top: float = 1.0 + BuildGrid.LEVEL_HEIGHT
	_add_floor_at(Vector2i(0, 0), top, 1)
	_add_floor_at(Vector2i(1, 0), top, 1)
	assert_true(_registry.has_dependents(BuildGrid.floor_key(Vector2i(0, 0), 1)), "trägt den Balkon (1,0)")
	assert_false(_registry.has_dependents(BuildGrid.floor_key(Vector2i(1, 0), 1)), "Balkonende trägt nichts")

func test_has_dependents_cantilever_chain_blocks_only_where_support_would_break() -> void:
	# Zwei Wände tragen zwei Böden; der Balkon (1,0) hängt an beiden Seiten — Abriss eines Trägers ist ok.
	_add_wall(0, 0, 0, 1.0)
	_add_wall(0, 2, 0, 1.0)
	var top: float = 1.0 + BuildGrid.LEVEL_HEIGHT
	_add_floor_at(Vector2i(0, 0), top, 1)
	_add_floor_at(Vector2i(1, 0), top, 1)
	_add_floor_at(Vector2i(2, 0), top, 1)
	assert_false(_registry.has_dependents(BuildGrid.floor_key(Vector2i(0, 0), 1)), "(1,0) bleibt über (2,0) gehalten")

func test_upper_wall_needs_support() -> void:
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0, 1), _registry, _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "unsupported")

func test_upper_wall_stacks_on_wall_below() -> void:
	_add_wall(0, 0, 2, 0.0)
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0, 1), _registry, _flat(0.0))
	assert_true(res["ok"])
	assert_eq(res["y"], BuildGrid.LEVEL_HEIGHT)

func test_upper_wall_stands_on_upper_floor() -> void:
	_add_floor_at(Vector2i(0, 1), 2.5, 1)
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0, 1), _registry, _flat(0.0))
	assert_true(res["ok"])
	assert_eq(res["y"], 2.5)

func test_upper_wall_ignores_player_standing_below() -> void:
	_add_wall(0, 0, 2, 0.0)
	# Spieler steht am Boden direkt unter der oberen Wand → darf sie nicht blockieren.
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0, 1), _registry,
		_flat(0.0), null, Vector3(1.0, -3.0, 4.1))
	assert_true(res["ok"])

func test_upper_wall_blocked_by_player_at_same_height() -> void:
	_add_floor_at(Vector2i(0, 1), 2.5, 1)
	var res := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0, 1), _registry,
		_flat(0.0), null, Vector3(1.0, 2.5, 4.1))
	assert_false(res["ok"])
	assert_eq(res["reason"], "player_in_way")

func test_upper_pieces_key_is_separate_from_ground() -> void:
	_add_wall(0, 0, 2, 0.0)
	var upper := BuildPlacementRules.check(_wall_def, BuildGrid.snap(WALL, Vector3(1, 0, 4), 0, 1), _registry, _flat(0.0))
	assert_true(upper["ok"], "Ebene 1 darf trotz belegter Ebene 0 frei sein.")

func test_has_dependents_for_wall_with_wall_above() -> void:
	_add_wall(0, 0, 2, 0.0)
	assert_false(_registry.has_dependents(BuildGrid.wall_key(0, 0, 2)))
	_add_wall(0, 0, 2, 2.5, 1)
	assert_true(_registry.has_dependents(BuildGrid.wall_key(0, 0, 2)))

func test_has_dependents_for_wall_with_floor_above() -> void:
	_add_wall(0, 0, 2, 0.0)
	_add_floor_at(Vector2i(0, 2), 2.5, 1)
	assert_true(_registry.has_dependents(BuildGrid.wall_key(0, 0, 2)))

func test_has_dependents_for_upper_floor_with_walls() -> void:
	_add_floor_at(Vector2i(0, 0), 2.5, 1)
	assert_false(_registry.has_dependents(BuildGrid.floor_key(Vector2i(0, 0), 1)))
	_add_wall(0, 0, 0, 2.5, 1)
	assert_true(_registry.has_dependents(BuildGrid.floor_key(Vector2i(0, 0), 1)))

func test_ground_floor_never_has_dependents() -> void:
	_add_floor(Vector2i(0, 0), 1.0)
	_add_wall(0, 0, 0, 1.0)
	assert_false(_registry.has_dependents(BuildGrid.floor_key(Vector2i(0, 0))))

func test_supports_others_has_reason_text() -> void:
	assert_ne(BuildPlacementRules.reason_text("supports_others"), "Bauen nicht möglich.")

# ── Dach (ROOF) ──────────────────────────────────

func test_roof_key_matches_floor_style() -> void:
	assert_eq(BuildGrid.roof_key(Vector2i(2, 3)), "R_2_3")
	assert_eq(BuildGrid.roof_key(Vector2i(2, 3), 1), "R_2_3_L1")

func test_roof_snap_axis_follows_rotation_like_walls() -> void:
	var even := BuildGrid.snap(ROOF, Vector3(1, 0, 1), 0)
	assert_eq(even["axis"], 0)
	assert_eq(even["yaw"], 0.0)
	assert_eq(even["key"], "R_0_0")
	var odd := BuildGrid.snap(ROOF, Vector3(1, 0, 1), 1)
	assert_eq(odd["axis"], 1)
	assert_almost_eq(float(odd["yaw"]), PI * 0.5, 0.0001)
	# Achse ändert nichts am Schlüssel — pro Zelle/Ebene passt ohnehin nur ein Dach.
	assert_eq(odd["key"], "R_0_0")

func test_roof_snap_respects_storey() -> void:
	assert_eq(BuildGrid.snap(ROOF, Vector3(1, 0, 1), 0, 1)["key"], "R_0_0_L1")

func test_roof_parse_key_roundtrip() -> void:
	var r := BuildGrid.parse_key(BuildGrid.roof_key(Vector2i(-2, 5), 1))
	assert_eq(r["kind"], ROOF)
	assert_eq(r["axis"], -1)
	assert_eq(r["x"], -2)
	assert_eq(r["z"], 5)
	assert_eq(r["storey"], 1)

func test_roof_is_roof_flag() -> void:
	assert_true(_roof_def.is_roof())
	assert_false(_roof_def.is_wall())
	assert_false(_roof_def.is_floor())

func test_roof_box_center_is_half_height() -> void:
	_roof_def.height = 1.4
	var size := _roof_def.get_box_size(BuildGrid.CELL)
	var center := _roof_def.get_box_center()
	assert_eq(size, Vector3(BuildGrid.CELL, 1.4, BuildGrid.CELL))
	assert_almost_eq(center.y, 0.7, 0.0001)

func test_roof_mesh_has_one_surface() -> void:
	var mesh := BuildPieceDefinition.build_roof_mesh(BuildGrid.CELL, 1.4)
	assert_eq(mesh.get_surface_count(), 1)
	# 3 Quads (2 Dachflächen + Unterseite, je 2 Dreiecke = 6 Punkte) + 2 Giebel-Dreiecke
	# (3 Punkte) = 3*6 + 2*3 = 24 Vertices (nicht indiziert, SurfaceTool.commit() ohne
	# index_array).
	assert_eq(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 24)

func test_roof_rejected_without_walls() -> void:
	var res := BuildPlacementRules.check(_roof_def, BuildGrid.snap(ROOF, Vector3(1, 0, 1), 0), _registry, _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "unsupported")

func test_roof_rests_on_wall_top_of_same_storey() -> void:
	_add_wall(0, 0, 0, 0.0)   # Wand auf Kante z=0 der Zelle (0,0), Ebene 0
	var res := BuildPlacementRules.check(_roof_def, BuildGrid.snap(ROOF, Vector3(1, 0, 1), 0), _registry, _flat(0.0))
	assert_true(res["ok"])
	assert_eq(res["y"], BuildGrid.LEVEL_HEIGHT)

func test_roof_uses_highest_surrounding_wall() -> void:
	_add_wall(0, 0, 0, 0.0)
	_add_wall(1, 0, 0, 0.5)   # höhere Wand auf Kante x=0
	var res := BuildPlacementRules.check(_roof_def, BuildGrid.snap(ROOF, Vector3(1, 0, 1), 0), _registry, _flat(0.0))
	assert_true(res["ok"])
	assert_eq(res["y"], 0.5 + BuildGrid.LEVEL_HEIGHT)

func test_roof_needs_wall_of_same_storey_not_below() -> void:
	_add_wall(0, 0, 0, 0.0, 0)   # Wand auf Ebene 0
	var res := BuildPlacementRules.check(_roof_def, BuildGrid.snap(ROOF, Vector3(1, 0, 1), 0, 1), _registry, _flat(0.0))
	assert_false(res["ok"], "Dach auf Ebene 1 braucht eine Wand AUF Ebene 1, nicht Ebene 0.")
	assert_eq(res["reason"], "unsupported")

func test_roof_rejected_when_occupied() -> void:
	_registry.add({"key": "R_0_0", "piece_id": "wood_roof", "kind": ROOF, "x": 0.0, "y": 0.0, "z": 0.0, "owner": ""})
	var res := BuildPlacementRules.check(_roof_def, BuildGrid.snap(ROOF, Vector3(1, 0, 1), 0), _registry, _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "occupied")

func test_roof_never_has_dependents() -> void:
	_add_wall(0, 0, 0, 0.0)
	_registry.add({"key": "R_0_0", "piece_id": "wood_roof", "kind": ROOF, "x": 0.0, "y": BuildGrid.LEVEL_HEIGHT, "z": 0.0, "owner": ""})
	assert_false(_registry.has_dependents("R_0_0"))
	assert_false(_registry.has_dependents(BuildGrid.roof_key(Vector2i(0, 0), 2)), "Auch auf oberen Ebenen: unbekannter Schlüssel → false, kein Absturz.")

# ── Tür/Fenster (DOOR/WINDOW) — wandartig, teilen sich den Schlüsselraum mit WALL ──

func test_door_and_window_snap_like_a_wall() -> void:
	var w := BuildGrid.snap(WALL, Vector3(2.9, 0, 3.1), 0)
	var d := BuildGrid.snap(DOOR, Vector3(2.9, 0, 3.1), 0)
	var n := BuildGrid.snap(WINDOW, Vector3(2.9, 0, 3.1), 0)
	assert_eq(d["key"], w["key"])
	assert_eq(n["key"], w["key"])
	assert_eq(d["kind"], DOOR)
	assert_eq(n["kind"], WINDOW)
	assert_eq(d["center"], w["center"])
	assert_eq(d["yaw"], w["yaw"])

func test_door_is_wall_like_but_not_wall() -> void:
	assert_true(_door_def.is_wall_like())
	assert_true(_window_def.is_wall_like())
	assert_false(_door_def.is_wall())
	assert_false(_window_def.is_wall())

func test_door_is_door_flag() -> void:
	assert_true(_door_def.is_door())
	assert_true(_window_def.is_window())
	assert_false(_door_def.is_stairs())
	assert_false(_window_def.is_door())

func test_door_and_wall_on_same_edge_are_mutually_exclusive() -> void:
	var snap := BuildGrid.snap(WALL, Vector3(1, 0, 4), 0)
	_registry.add({"key": snap["key"], "piece_id": "wood_wall", "x": 0, "y": 0, "z": 0})
	var res := BuildPlacementRules.check(_door_def, BuildGrid.snap(DOOR, Vector3(1, 0, 4), 0), _registry, _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "occupied")

func test_freestanding_door_uses_wall_placement_rules() -> void:
	var res := BuildPlacementRules.check(_door_def, BuildGrid.snap(DOOR, Vector3(1, 0, 4), 0), _registry, _flat(1.1))
	assert_true(res["ok"])
	assert_eq(res["y"], 1.0)

func test_door_supports_floor_above_like_a_wall() -> void:
	# has_dependents() liest den Kind aus dem SCHLÜSSEL (parse_key), nicht aus piece_id —
	# eine Tür an einer Kante trägt strukturell genauso wie eine Wand.
	var key := BuildGrid.wall_key(0, 0, 2)
	_registry.add({"key": key, "piece_id": "wood_door", "kind": DOOR, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "owner": ""})
	_add_floor_at(Vector2i(0, 2), 2.5, 1)
	assert_true(_registry.has_dependents(key))

func test_door_boxes_leave_a_walkable_gap_at_the_base() -> void:
	var boxes := _door_def.get_door_boxes(BuildGrid.CELL)
	assert_eq(boxes.size(), 3, "2 Pfosten + Sturz (Tür niedriger als Wand).")
	for b: Dictionary in boxes:
		var size: Vector3 = b["size"]
		var center: Vector3 = b["center"]
		var half_x: float = size.x * 0.5
		# Keine Box darf die Mittelachse (x=0) am Boden (y nahe 0) überdecken — dort ist die
		# Öffnung, durch die man gehen können muss.
		if absf(center.y) < 0.5:
			assert_true(center.x - half_x > -0.01 or center.x + half_x < 0.01,
				"Box '%s' reicht in die Türöffnung hinein." % [b])

func test_window_boxes_have_sill_jambs_and_lintel() -> void:
	var boxes := _window_def.get_window_boxes(BuildGrid.CELL)
	assert_eq(boxes.size(), 4, "2 Pfosten + Brüstung + Sturz.")

func test_framed_mesh_combines_all_boxes() -> void:
	var boxes := _door_def.get_door_boxes(BuildGrid.CELL)
	var mesh := BuildPieceDefinition.build_framed_mesh(boxes)
	assert_eq(mesh.get_surface_count(), 1)
	# Jede Box = 6 Quads × 6 Punkte (2 Dreiecke, nicht indiziert) = 36 Vertices.
	assert_eq(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), boxes.size() * 36)

# ── Treppe (STAIRS) ─────────────────────────────

func test_stairs_key_matches_floor_style() -> void:
	assert_eq(BuildGrid.stairs_key(Vector2i(2, 3)), "T_2_3")
	assert_eq(BuildGrid.stairs_key(Vector2i(2, 3), 1), "T_2_3_L1")

func test_stairs_snap_uses_full_rotation_for_facing() -> void:
	var s0 := BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 0)
	var s1 := BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 1)
	var s2 := BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 2)
	var s3 := BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 3)
	assert_eq(s0["axis"], 0)
	assert_eq(s1["axis"], 1)
	assert_eq(s2["axis"], 2)
	assert_eq(s3["axis"], 3)
	assert_almost_eq(float(s1["yaw"]), PI * 0.5, 0.0001)
	assert_almost_eq(float(s2["yaw"]), PI, 0.0001)
	# Achse ändert nichts am Schlüssel — pro Zelle/Ebene passt ohnehin nur eine Treppe.
	assert_eq(s0["key"], "T_0_0")
	assert_eq(s3["key"], "T_0_0")

func test_stairs_snap_respects_storey() -> void:
	assert_eq(BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 0, 1)["key"], "T_0_0_L1")

func test_stairs_parse_key_roundtrip() -> void:
	var t := BuildGrid.parse_key(BuildGrid.stairs_key(Vector2i(-2, 5), 1))
	assert_eq(t["kind"], STAIRS)
	assert_eq(t["axis"], -1)
	assert_eq(t["x"], -2)
	assert_eq(t["z"], 5)
	assert_eq(t["storey"], 1)

func test_stairs_is_stairs_flag() -> void:
	assert_true(_stairs_def.is_stairs())
	assert_false(_stairs_def.is_wall_like())
	assert_false(_stairs_def.is_floor())

func test_stairs_box_center_is_half_height() -> void:
	_stairs_def.height = BuildGrid.LEVEL_HEIGHT
	var size := _stairs_def.get_box_size(BuildGrid.CELL)
	var center := _stairs_def.get_box_center()
	assert_eq(size, Vector3(BuildGrid.CELL, BuildGrid.LEVEL_HEIGHT, BuildGrid.CELL))
	assert_almost_eq(center.y, BuildGrid.LEVEL_HEIGHT * 0.5, 0.0001)

func test_stairs_mesh_has_one_surface_per_step() -> void:
	var mesh := BuildPieceDefinition.build_stairs_mesh(BuildGrid.CELL, BuildGrid.LEVEL_HEIGHT)
	assert_eq(mesh.get_surface_count(), 1)
	var expected: int = BuildPieceDefinition.STAIR_STEPS * 36   # 6 Quads × 6 Punkte je Stufenbox
	assert_eq(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), expected)

func test_stairs_rejected_without_ground() -> void:
	var no_ground := func(_x: float, _z: float) -> float: return NAN
	var res := BuildPlacementRules.check(_stairs_def, BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 0), _registry, no_ground)
	assert_false(res["ok"])
	assert_eq(res["reason"], "no_ground")

func test_stairs_on_flat_ground_bases_at_lowest_corner() -> void:
	var ground := func(x: float, _z: float) -> float: return 1.0 if x < 1.0 else 1.3
	var res := BuildPlacementRules.check(_stairs_def, BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 0), _registry, ground)
	assert_true(res["ok"])
	assert_eq(res["y"], 1.0)

func test_stairs_rejected_when_terrain_too_steep() -> void:
	var ground := func(x: float, _z: float) -> float: return 0.0 if x < 1.0 else 12.0
	var res := BuildPlacementRules.check(_stairs_def, BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 0), _registry, ground)
	assert_false(res["ok"])
	assert_eq(res["reason"], "too_steep")

func test_stairs_rejected_in_water() -> void:
	var res := BuildPlacementRules.check(_stairs_def, BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 0), _registry,
		_flat(-1.0), null, Vector3(NAN, NAN, NAN), _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "in_water")

func test_stairs_rejected_when_occupied() -> void:
	_registry.add({"key": "T_0_0", "piece_id": "wood_stairs", "kind": STAIRS, "x": 0.0, "y": 0.0, "z": 0.0, "owner": ""})
	var res := BuildPlacementRules.check(_stairs_def, BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 0), _registry, _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "occupied")

func test_upper_stairs_need_wall_below() -> void:
	var res := BuildPlacementRules.check(_stairs_def, BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 0, 1), _registry, _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "unsupported")

func test_upper_stairs_rest_on_wall_top() -> void:
	_add_wall(0, 0, 0, 1.0)
	var res := BuildPlacementRules.check(_stairs_def, BuildGrid.snap(STAIRS, Vector3(1, 0, 1), 0, 1), _registry, _flat(0.0))
	assert_true(res["ok"])
	assert_eq(res["y"], 1.0 + BuildGrid.LEVEL_HEIGHT)

func test_stairs_never_have_dependents() -> void:
	_registry.add({"key": "T_0_0", "piece_id": "wood_stairs", "kind": STAIRS, "x": 0.0, "y": 0.0, "z": 0.0, "owner": ""})
	assert_false(_registry.has_dependents("T_0_0"))

# ── Requisit (TARGET) ────────────────────────────

func test_target_key_matches_floor_style() -> void:
	assert_eq(BuildGrid.target_key(Vector2i(2, 3)), "P_2_3")
	assert_eq(BuildGrid.target_key(Vector2i(2, 3), 1), "P_2_3_L1")

func test_target_snap_uses_full_rotation_for_facing() -> void:
	var s0 := BuildGrid.snap(TARGET, Vector3(1, 0, 1), 0)
	var s1 := BuildGrid.snap(TARGET, Vector3(1, 0, 1), 1)
	var s3 := BuildGrid.snap(TARGET, Vector3(1, 0, 1), 3)
	assert_eq(s0["axis"], 0)
	assert_eq(s1["axis"], 1)
	assert_eq(s3["axis"], 3)
	assert_almost_eq(float(s1["yaw"]), PI * 0.5, 0.0001)
	# Achse ändert nichts am Schlüssel — pro Zelle/Ebene passt ohnehin nur eine Requisite.
	assert_eq(s0["key"], "P_0_0")
	assert_eq(s3["key"], "P_0_0")

func test_target_snap_respects_storey() -> void:
	assert_eq(BuildGrid.snap(TARGET, Vector3(1, 0, 1), 0, 1)["key"], "P_0_0_L1")

func test_target_parse_key_roundtrip() -> void:
	var t := BuildGrid.parse_key(BuildGrid.target_key(Vector2i(-2, 5), 1))
	assert_eq(t["kind"], TARGET)
	assert_eq(t["axis"], -1)
	assert_eq(t["x"], -2)
	assert_eq(t["z"], 5)
	assert_eq(t["storey"], 1)

func test_target_is_target_flag() -> void:
	assert_true(_target_def.is_target())
	assert_false(_target_def.is_wall_like())
	assert_false(_target_def.is_floor())
	assert_false(_target_def.is_stairs())

func test_target_box_center_is_half_height() -> void:
	var center := _target_def.get_box_center()
	assert_almost_eq(center.y, _target_def.height * 0.5, 0.0001)

func test_target_mesh_has_one_surface() -> void:
	var mesh := BuildPieceDefinition.build_target_mesh(1.6)
	assert_eq(mesh.get_surface_count(), 1)
	assert_gt(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 0)

func test_target_rejected_without_ground() -> void:
	var no_ground := func(_x: float, _z: float) -> float: return NAN
	var res := BuildPlacementRules.check(_target_def, BuildGrid.snap(TARGET, Vector3(1, 0, 1), 0), _registry, no_ground)
	assert_false(res["ok"])
	assert_eq(res["reason"], "no_ground")

func test_target_on_flat_ground_bases_at_average_corner_height() -> void:
	var res := BuildPlacementRules.check(_target_def, BuildGrid.snap(TARGET, Vector3(1, 0, 1), 0), _registry, _flat(1.0))
	assert_true(res["ok"])
	assert_eq(res["y"], 1.0)

func test_target_rejected_in_water() -> void:
	var res := BuildPlacementRules.check(_target_def, BuildGrid.snap(TARGET, Vector3(1, 0, 1), 0), _registry,
		_flat(-1.0), null, Vector3(NAN, NAN, NAN), _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "in_water")

func test_target_rejected_when_occupied() -> void:
	_registry.add({"key": "P_0_0", "piece_id": "archery_target", "kind": TARGET, "x": 0.0, "y": 0.0, "z": 0.0, "owner": ""})
	var res := BuildPlacementRules.check(_target_def, BuildGrid.snap(TARGET, Vector3(1, 0, 1), 0), _registry, _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "occupied")

func test_upper_target_needs_wall_below() -> void:
	var res := BuildPlacementRules.check(_target_def, BuildGrid.snap(TARGET, Vector3(1, 0, 1), 0, 1), _registry, _flat(0.0))
	assert_false(res["ok"])
	assert_eq(res["reason"], "unsupported")

func test_target_never_has_dependents() -> void:
	_registry.add({"key": "P_0_0", "piece_id": "archery_target", "kind": TARGET, "x": 0.0, "y": 0.0, "z": 0.0, "owner": ""})
	assert_false(_registry.has_dependents("P_0_0"))

func test_target_rotate_house_piece_advances_facing() -> void:
	var entry := {"piece_id": "archery_target", "kind": TARGET, "axis": 0, "dx": 2, "dz": 0}
	var rotated := BuildGrid.rotate_house_piece(entry, 1)
	assert_eq(rotated["axis"], 1)
	assert_eq(rotated["dx"], -1)
	assert_eq(rotated["dz"], 2)

# ── Requisit: Brunnen (TARGET, prop_shape=WELL) ──

func test_target_default_prop_shape_is_stand_disc() -> void:
	assert_eq(_target_def.prop_shape, BuildPieceDefinition.PropShape.STAND_DISC)

func test_well_box_size_differs_from_target_disc() -> void:
	var well_def := BuildPieceDefinition.new()
	well_def.kind = TARGET
	well_def.prop_shape = BuildPieceDefinition.PropShape.WELL
	well_def.height = 1.9
	var well_size := well_def.get_box_size(BuildGrid.CELL)
	var disc_size := _target_def.get_box_size(BuildGrid.CELL)
	assert_almost_eq(well_size.x, BuildPieceDefinition.WELL_RADIUS * 2.2, 0.0001)
	assert_almost_eq(well_size.z, BuildPieceDefinition.WELL_RADIUS * 2.2, 0.0001)
	assert_ne(well_size.x, disc_size.x)

func test_well_box_center_is_half_height() -> void:
	var well_def := BuildPieceDefinition.new()
	well_def.kind = TARGET
	well_def.prop_shape = BuildPieceDefinition.PropShape.WELL
	well_def.height = 1.9
	assert_almost_eq(well_def.get_box_center().y, 1.9 * 0.5, 0.0001)

func test_well_mesh_has_one_surface() -> void:
	var mesh := BuildPieceDefinition.build_well_mesh(1.9)
	assert_eq(mesh.get_surface_count(), 1)
	assert_gt(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 0)

func test_build_prop_mesh_dispatches_on_prop_shape() -> void:
	var disc := BuildPieceDefinition.build_prop_mesh(1.6, BuildPieceDefinition.PropShape.STAND_DISC)
	var well := BuildPieceDefinition.build_prop_mesh(1.9, BuildPieceDefinition.PropShape.WELL)
	var expect_disc := BuildPieceDefinition.build_target_mesh(1.6)
	var expect_well := BuildPieceDefinition.build_well_mesh(1.9)
	assert_eq(disc.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),
		expect_disc.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
	assert_eq(well.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),
		expect_well.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())

func test_well_uses_same_placement_rules_as_any_target() -> void:
	var well_def := BuildPieceDefinition.new()
	well_def.id = "well"
	well_def.kind = TARGET
	well_def.prop_shape = BuildPieceDefinition.PropShape.WELL
	well_def.height = 1.9
	var res := BuildPlacementRules.check(well_def, BuildGrid.snap(TARGET, Vector3(1, 0, 1), 0), _registry, _flat(2.0))
	assert_true(res["ok"])
	assert_eq(res["y"], 2.0)

# ── Requisit: Türme rund/eckig (TARGET, prop_shape=TOWER_ROUND/TOWER_SQUARE) ──

func test_tower_box_size_reaches_above_shaft_height() -> void:
	var tower_def := BuildPieceDefinition.new()
	tower_def.kind = TARGET
	tower_def.prop_shape = BuildPieceDefinition.PropShape.TOWER_ROUND
	tower_def.height = 3.2
	var size := tower_def.get_box_size(BuildGrid.CELL)
	# Hüllbox muss über den reinen Schaft (height) hinausreichen — Zinnen + Dach kommen
	# obendrauf (siehe BuildPieceDefinition.tower_total_height()).
	assert_gt(size.y, tower_def.height)
	assert_almost_eq(size.y, BuildPieceDefinition.tower_total_height(3.2), 0.0001)
	assert_almost_eq(size.x, BuildPieceDefinition.TOWER_RADIUS * 2.2, 0.0001)

func test_tower_box_center_is_half_total_height() -> void:
	var tower_def := BuildPieceDefinition.new()
	tower_def.kind = TARGET
	tower_def.prop_shape = BuildPieceDefinition.PropShape.TOWER_SQUARE
	tower_def.height = 3.2
	var expected: float = BuildPieceDefinition.tower_total_height(3.2) * 0.5
	assert_almost_eq(tower_def.get_box_center().y, expected, 0.0001)

func test_tower_round_and_square_meshes_are_nonempty_and_differ() -> void:
	var round_mesh := BuildPieceDefinition.build_tower_mesh(3.2, true)
	var square_mesh := BuildPieceDefinition.build_tower_mesh(3.2, false)
	assert_eq(round_mesh.get_surface_count(), 1)
	assert_eq(square_mesh.get_surface_count(), 1)
	assert_gt(round_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 0)
	assert_gt(square_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 0)
	# Rund (16 Segmente) und eckig (4 Seiten) erzeugen unterschiedlich viele Vertices —
	# ein einfacher Nachweis, dass build_prop_mesh() wirklich zwei verschiedene Formen liefert.
	assert_ne(round_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),
		square_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())

func test_build_prop_mesh_dispatches_on_tower_shape() -> void:
	var round_via_prop := BuildPieceDefinition.build_prop_mesh(3.2, BuildPieceDefinition.PropShape.TOWER_ROUND)
	var round_direct := BuildPieceDefinition.build_tower_mesh(3.2, true)
	assert_eq(round_via_prop.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),
		round_direct.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())

func test_tower_uses_same_placement_rules_as_any_target() -> void:
	var tower_def := BuildPieceDefinition.new()
	tower_def.id = "tower_stone_round"
	tower_def.kind = TARGET
	tower_def.prop_shape = BuildPieceDefinition.PropShape.TOWER_ROUND
	tower_def.height = 3.2
	var res := BuildPlacementRules.check(tower_def, BuildGrid.snap(TARGET, Vector3(1, 0, 1), 0), _registry, _flat(2.0))
	assert_true(res["ok"])
	assert_eq(res["y"], 2.0)

# ── Dach: mehr Formen (ROOF, roof_shape=HIP/PYRAMID/FLAT), First adjustierbar (roof_ridge) ──

func test_roof_default_shape_is_gable() -> void:
	assert_eq(_roof_def.roof_shape, BuildPieceDefinition.RoofShape.GABLE)

func test_gable_roof_ignores_roof_ridge() -> void:
	# GABLE ruft _build_hip_gable_mesh() intern immer mit ridge=0 auf — ein roof_ridge-Wert
	# auf der Definition darf am Ergebnis nichts ändern (Abwärtskompatibilität bestehender
	# Dach-.tres ohne dieses Feld).
	var a := BuildPieceDefinition.build_roof_mesh(BuildGrid.CELL, 1.4, BuildPieceDefinition.RoofShape.GABLE, 0.0)
	var b := BuildPieceDefinition.build_roof_mesh(BuildGrid.CELL, 1.4, BuildPieceDefinition.RoofShape.GABLE, 1.0)
	assert_eq(a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])

func test_hip_roof_ridge_adjusts_shape() -> void:
	# roof_ridge ist der "adjustierende" Regler zwischen Sattel- (0) und Walmdach (1) —
	# unterschiedliche Werte müssen unterschiedliche Geometrie erzeugen.
	var low := BuildPieceDefinition.build_roof_mesh(BuildGrid.CELL, 1.4, BuildPieceDefinition.RoofShape.HIP, 0.2)
	var high := BuildPieceDefinition.build_roof_mesh(BuildGrid.CELL, 1.4, BuildPieceDefinition.RoofShape.HIP, 0.9)
	assert_ne(low.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], high.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])

func test_pyramid_roof_ignores_roof_ridge_and_is_fully_hipped() -> void:
	# PYRAMID erzwingt intern ridge=1 unabhängig vom Feld — bei quadratischer Zelle ergibt
	# das dieselbe Geometrie wie HIP mit roof_ridge=1.0.
	var pyramid := BuildPieceDefinition.build_roof_mesh(BuildGrid.CELL, 1.4, BuildPieceDefinition.RoofShape.PYRAMID, 0.1)
	var hip_full := BuildPieceDefinition.build_roof_mesh(BuildGrid.CELL, 1.4, BuildPieceDefinition.RoofShape.HIP, 1.0)
	assert_eq(pyramid.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], hip_full.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])

func test_flat_roof_box_ignores_height() -> void:
	_roof_def.roof_shape = BuildPieceDefinition.RoofShape.FLAT
	_roof_def.height = 5.0
	var size := _roof_def.get_box_size(BuildGrid.CELL)
	# FLAT nutzt `height` nicht (siehe RoofShape-Kommentar) — die Hüllbox bleibt niedrig,
	# unabhängig davon, wie hoch `height` gesetzt ist.
	assert_almost_eq(size.y, BuildPieceDefinition.FLAT_ROOF_THICKNESS + BuildPieceDefinition.FLAT_ROOF_PARAPET, 0.0001)

func test_flat_roof_mesh_is_nonempty() -> void:
	var mesh := BuildPieceDefinition.build_roof_mesh(BuildGrid.CELL, 1.4, BuildPieceDefinition.RoofShape.FLAT)
	assert_eq(mesh.get_surface_count(), 1)
	assert_gt(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 0)

# ── Requisiten: Kapelle, Wegweiser, Straßenlaterne (TARGET, prop_shape=CHAPEL/SIGNPOST/LAMP_POST) ──

func _prop_def(shape: int, prop_height: float) -> BuildPieceDefinition:
	var d := BuildPieceDefinition.new()
	d.id = "test_prop_%d" % shape
	d.kind = TARGET
	d.prop_shape = shape
	d.height = prop_height
	return d

func _mesh_vertices(mesh: ArrayMesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in mesh.get_surface_count():
		out.append_array(mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX])
	return out

func _mesh_max_y(mesh: ArrayMesh) -> float:
	var top: float = -INF
	for v: Vector3 in _mesh_vertices(mesh):
		top = maxf(top, v.y)
	return top

## Schneidet irgendeine Kollisionsbox ({size, center}) den Quader lo..hi?
func _boxes_hit(boxes: Array[Dictionary], lo: Vector3, hi: Vector3) -> bool:
	for b: Dictionary in boxes:
		var size: Vector3 = b["size"]
		var c: Vector3 = b["center"]
		var blo: Vector3 = c - size * 0.5
		var bhi: Vector3 = c + size * 0.5
		if blo.x < hi.x and bhi.x > lo.x and blo.y < hi.y and bhi.y > lo.y and blo.z < hi.z and bhi.z > lo.z:
			return true
	return false

func test_every_prop_shape_has_one_surface_role_per_mesh_surface() -> void:
	# Invariante zwischen build_prop_mesh() und prop_surface_roles(): BuildPiece setzt je Surface
	# ein Material — stimmen die Anzahlen nicht, bliebe eine Fläche unbemalt oder ein Material ungenutzt.
	for shape: int in BuildPieceDefinition.PropShape.values():
		var mesh := BuildPieceDefinition.build_prop_mesh(2.0, shape)
		var roles := BuildPieceDefinition.prop_surface_roles(shape)
		assert_eq(mesh.get_surface_count(), roles.size(), "PropShape %d" % shape)
		for i in mesh.get_surface_count():
			assert_gt(mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size(), 0, "PropShape %d Surface %d leer" % [shape, i])

func test_older_prop_shapes_stay_single_surface_main() -> void:
	for shape: int in [BuildPieceDefinition.PropShape.STAND_DISC, BuildPieceDefinition.PropShape.WELL,
			BuildPieceDefinition.PropShape.TOWER_ROUND, BuildPieceDefinition.PropShape.CROSS]:
		var roles := BuildPieceDefinition.prop_surface_roles(shape)
		assert_eq(roles.size(), 1, "PropShape %d" % shape)
		assert_eq(roles[0], BuildPieceDefinition.PropSurface.MAIN, "PropShape %d" % shape)

func test_chapel_mesh_height_matches_total_height() -> void:
	var mesh := BuildPieceDefinition.build_chapel_mesh(2.4)
	assert_almost_eq(_mesh_max_y(mesh), BuildPieceDefinition.chapel_total_height(2.4), 0.001)
	var def := _prop_def(BuildPieceDefinition.PropShape.CHAPEL, 2.4)
	assert_almost_eq(def.get_box_size(BuildGrid.CELL).y, BuildPieceDefinition.chapel_total_height(2.4), 0.0001)
	assert_almost_eq(def.get_box_center().y, BuildPieceDefinition.chapel_total_height(2.4) * 0.5, 0.0001)

func test_chapel_is_enterable_door_and_interior_are_free() -> void:
	var def := _prop_def(BuildPieceDefinition.PropShape.CHAPEL, 2.4)
	var boxes := def.get_prop_collision_boxes()
	assert_gt(boxes.size(), 0)
	# Gang von draußen (vor dem Eingang, +Z) durch die Tür bis an die Rückwand, Körperbreite
	# knapp unter der Türöffnung, Höhe bis knapp unter den Sturz — darf nichts treffen.
	var hd: float = BuildPieceDefinition.CHAPEL_HALF_DEPTH
	var walk_lo := Vector3(-0.4, BuildPieceDefinition.CHAPEL_FLOOR_TOP + 0.05, -hd + BuildPieceDefinition.CHAPEL_WALL_THICKNESS + 0.1)
	var walk_hi := Vector3(0.4, 1.7, hd + 0.5)
	assert_false(_boxes_hit(boxes, walk_lo, walk_hi))

func test_chapel_walls_block_from_outside() -> void:
	var def := _prop_def(BuildPieceDefinition.PropShape.CHAPEL, 2.4)
	var boxes := def.get_prop_collision_boxes()
	var hw: float = BuildPieceDefinition.CHAPEL_HALF_WIDTH
	var hd: float = BuildPieceDefinition.CHAPEL_HALF_DEPTH
	# Seitenwand links/rechts, Rückwand, Frontwand neben der Tür, Sturz über der Tür.
	assert_true(_boxes_hit(boxes, Vector3(-hw + 0.02, 0.5, -0.1), Vector3(-hw + 0.1, 1.5, 0.1)))
	assert_true(_boxes_hit(boxes, Vector3(hw - 0.1, 0.5, -0.1), Vector3(hw - 0.02, 1.5, 0.1)))
	assert_true(_boxes_hit(boxes, Vector3(-0.1, 0.5, -hd + 0.02), Vector3(0.1, 1.5, -hd + 0.1)))
	assert_true(_boxes_hit(boxes, Vector3(0.6, 0.5, hd - 0.1), Vector3(0.8, 1.5, hd - 0.02)))
	assert_true(_boxes_hit(boxes, Vector3(-0.1, 2.1, hd - 0.1), Vector3(0.1, 2.3, hd - 0.02)))

func test_only_chapel_uses_custom_collision_boxes() -> void:
	assert_true(_target_def.get_prop_collision_boxes().is_empty())
	for shape: int in [BuildPieceDefinition.PropShape.WELL, BuildPieceDefinition.PropShape.TOWER_ROUND,
			BuildPieceDefinition.PropShape.SIGNPOST, BuildPieceDefinition.PropShape.LAMP_POST]:
		assert_true(_prop_def(shape, 2.4).get_prop_collision_boxes().is_empty(), "PropShape %d" % shape)
	# Auch ein Nicht-TARGET mit prop_shape=CHAPEL darf keine Kapselkollision bekommen.
	_wall_def.prop_shape = BuildPieceDefinition.PropShape.CHAPEL
	assert_true(_wall_def.get_prop_collision_boxes().is_empty())

func test_signpost_mesh_height_and_boards_reach_beyond_hull() -> void:
	var mesh := BuildPieceDefinition.build_signpost_mesh(2.4)
	assert_almost_eq(_mesh_max_y(mesh), 2.4, 0.001)
	var def := _prop_def(BuildPieceDefinition.PropShape.SIGNPOST, 2.4)
	var hull := def.get_box_size(BuildGrid.CELL)
	assert_almost_eq(hull.x, BuildPieceDefinition.SIGNPOST_HULL, 0.0001)
	assert_almost_eq(hull.y, 2.4, 0.0001)
	var min_x: float = INF
	var max_x: float = -INF
	for v: Vector3 in _mesh_vertices(mesh):
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
	# Die Schilder ragen nach beiden Seiten deutlich über die Pfosten-Hüllbox hinaus (man geht vorbei).
	assert_gt(max_x, hull.x * 0.5 + 0.3)
	assert_lt(min_x, -(hull.x * 0.5 + 0.3))

func test_signpost_boards_alternate_direction() -> void:
	var dirs: Array[float] = []
	for entry: Vector4 in BuildPieceDefinition.SIGNPOST_BOARDS:
		dirs.append(entry.y)
	assert_true(dirs.has(1.0) and dirs.has(-1.0))

func test_lamp_mesh_height_and_light_sits_in_glass() -> void:
	var mesh := BuildPieceDefinition.build_lamp_post_mesh(3.4)
	assert_almost_eq(_mesh_max_y(mesh), 3.4, 0.001)
	var glass := BuildPieceDefinition.lamp_glass_bounds(3.4)
	assert_lt(glass.x, glass.y)
	var offset := BuildPieceDefinition.prop_light_offset(BuildPieceDefinition.PropShape.LAMP_POST, 3.4)
	assert_gt(offset.y, glass.x)
	assert_lt(offset.y, glass.y)
	assert_almost_eq(offset.x, 0.0, 0.0001)
	assert_almost_eq(offset.z, 0.0, 0.0001)

func test_lamp_glow_surface_is_the_last_surface() -> void:
	var roles := BuildPieceDefinition.prop_surface_roles(BuildPieceDefinition.PropShape.LAMP_POST)
	assert_eq(roles[roles.size() - 1], BuildPieceDefinition.PropSurface.GLOW)

func test_has_light_needs_range_and_target_kind() -> void:
	var lamp := _prop_def(BuildPieceDefinition.PropShape.LAMP_POST, 3.4)
	assert_false(lamp.has_light(), "Standard: light_range = 0 → kein Licht")
	lamp.light_range = 6.0
	assert_true(lamp.has_light())
	_stairs_def.light_range = 6.0
	assert_false(_stairs_def.has_light(), "Nur TARGET kann Licht abgeben")

func test_prop_materials_follow_roles() -> void:
	var def := _prop_def(BuildPieceDefinition.PropShape.CHAPEL, 2.4)
	def.color = Color(0.6, 0.6, 0.6)
	def.accent_color = Color(0.3, 0.2, 0.1)
	var mats := def.build_prop_materials()
	var roles := BuildPieceDefinition.prop_surface_roles(def.prop_shape)
	assert_eq(mats.size(), roles.size())
	for i in roles.size():
		var role: int = roles[i]
		if role == BuildPieceDefinition.PropSurface.MAIN:
			assert_eq(mats[i].albedo_color, def.color)
			assert_false(mats[i].emission_enabled)
		elif role == BuildPieceDefinition.PropSurface.ACCENT:
			assert_eq(mats[i].albedo_color, def.accent_color)
		else:
			assert_true(mats[i].emission_enabled)
			assert_eq(mats[i].emission, BuildPieceDefinition.PROP_GLOW_COLOR)

func test_single_surface_prop_material_uses_main_color() -> void:
	# Regression: ältere einflächige Requisiten (Brunnen, Zielscheibe, ...) färben sich weiter mit `color`.
	_target_def.color = Color(0.1, 0.2, 0.3)
	var mats := _target_def.build_prop_materials()
	assert_eq(mats.size(), 1)
	assert_eq(mats[0].albedo_color, Color(0.1, 0.2, 0.3))

func test_new_props_use_same_placement_rules_as_any_target() -> void:
	for shape: int in [BuildPieceDefinition.PropShape.CHAPEL, BuildPieceDefinition.PropShape.SIGNPOST,
			BuildPieceDefinition.PropShape.LAMP_POST]:
		var def := _prop_def(shape, 2.4)
		var res := BuildPlacementRules.check(def, BuildGrid.snap(TARGET, Vector3(1, 0, 1), 0), _registry, _flat(2.0))
		assert_true(res["ok"], "PropShape %d" % shape)
		assert_eq(res["y"], 2.0)

func test_new_prop_pieces_are_registered_and_valid() -> void:
	var expected: Dictionary = {
		"chapel_stone": BuildPieceDefinition.PropShape.CHAPEL,
		"chapel_wood": BuildPieceDefinition.PropShape.CHAPEL,
		"signpost_wood": BuildPieceDefinition.PropShape.SIGNPOST,
		"street_lamp_iron": BuildPieceDefinition.PropShape.LAMP_POST,
		"street_lamp_wood": BuildPieceDefinition.PropShape.LAMP_POST,
	}
	var found: Dictionary = {}
	var seen_ids: Dictionary = {}
	for path: String in DataManifest.BUILD_PIECES:
		var def := load(path) as BuildPieceDefinition
		assert_not_null(def, "%s ist keine BuildPieceDefinition" % path)
		if def == null:
			continue
		assert_false(seen_ids.has(def.id), "doppelte Bauteil-ID %s" % def.id)
		seen_ids[def.id] = true
		if expected.has(def.id):
			found[def.id] = def
	for id: String in expected.keys():
		assert_true(found.has(id), "%s fehlt in DataManifest.BUILD_PIECES" % id)
		if not found.has(id):
			continue
		var d: BuildPieceDefinition = found[id]
		assert_eq(d.kind, TARGET, id)
		assert_eq(d.prop_shape, expected[id], id)
		assert_false(d.cost.is_empty(), "%s ohne Baukosten" % id)
		# Lampen leuchten, alles andere nicht.
		assert_eq(d.has_light(), expected[id] == BuildPieceDefinition.PropShape.LAMP_POST, id)

# ── Schmiede-Stationen: Hochofen + Amboss (TARGET, prop_shape=FURNACE/ANVIL, station_kind) ──

func test_station_kind_defaults_to_no_station() -> void:
	var d := BuildPieceDefinition.new()
	assert_eq(d.station_kind, "")
	assert_false(d.is_station())
	d.station_kind = "furnace"
	assert_true(d.is_station())

func test_furnace_and_anvil_enum_values_are_appended() -> void:
	# .tres speichern den Enum als Zahl (Well.tres: prop_shape = 1) — Werte dürfen sich nie verschieben.
	assert_eq(BuildPieceDefinition.PropShape.CATAPULT, 13)
	assert_eq(BuildPieceDefinition.PropShape.FURNACE, 14)
	assert_eq(BuildPieceDefinition.PropShape.ANVIL, 15)

func test_furnace_mesh_surfaces_match_roles() -> void:
	var mesh := BuildPieceDefinition.build_prop_mesh(1.6, BuildPieceDefinition.PropShape.FURNACE)
	var roles := BuildPieceDefinition.prop_surface_roles(BuildPieceDefinition.PropShape.FURNACE)
	assert_eq(mesh.get_surface_count(), roles.size())
	assert_eq(roles, [BuildPieceDefinition.PropSurface.MAIN, BuildPieceDefinition.PropSurface.ACCENT, BuildPieceDefinition.PropSurface.GLOW] as Array[int])
	assert_gt(_mesh_vertices(mesh).size(), 0)

func test_anvil_mesh_surfaces_match_roles() -> void:
	var mesh := BuildPieceDefinition.build_prop_mesh(0.85, BuildPieceDefinition.PropShape.ANVIL)
	var roles := BuildPieceDefinition.prop_surface_roles(BuildPieceDefinition.PropShape.ANVIL)
	assert_eq(mesh.get_surface_count(), roles.size())
	assert_gt(_mesh_vertices(mesh).size(), 0)

func test_furnace_mesh_top_is_height() -> void:
	var mesh := BuildPieceDefinition.build_furnace_mesh(1.6)
	assert_almost_eq(_mesh_max_y(mesh), 1.6, 0.0001)

func test_anvil_mesh_top_is_height() -> void:
	var mesh := BuildPieceDefinition.build_anvil_mesh(0.85)
	assert_almost_eq(_mesh_max_y(mesh), 0.85, 0.0001)

func test_station_mesh_height_is_clamped_to_minimum() -> void:
	var furnace := BuildPieceDefinition.build_furnace_mesh(0.1)
	assert_almost_eq(_mesh_max_y(furnace), BuildPieceDefinition.FURNACE_MIN_HEIGHT, 0.0001)
	var anvil := BuildPieceDefinition.build_anvil_mesh(0.1)
	assert_almost_eq(_mesh_max_y(anvil), BuildPieceDefinition.ANVIL_MIN_HEIGHT, 0.0001)

func test_furnace_glow_sits_in_front_mouth() -> void:
	# Die Glut-Surface (letzte) liegt in der +Z-Front (z ≈ halbe Tiefe) und zwischen Ober-/Unterkante der Öffnung.
	var mesh := BuildPieceDefinition.build_furnace_mesh(1.6)
	var mouth := BuildPieceDefinition.furnace_mouth_bounds(1.6)
	var verts: PackedVector3Array = mesh.surface_get_arrays(2)[Mesh.ARRAY_VERTEX]
	assert_gt(verts.size(), 0)
	var max_z: float = -INF
	for v: Vector3 in verts:
		max_z = maxf(max_z, v.z)
		assert_true(v.y >= mouth.x - 0.0001 and v.y <= mouth.y + 0.0001, "Glut außerhalb der Öffnung: %s" % v)
	assert_almost_eq(max_z, BuildPieceDefinition.FURNACE_HALF_DEPTH + 0.02, 0.0001)

func test_furnace_light_offset_is_in_front_of_mouth() -> void:
	var off := BuildPieceDefinition.prop_light_offset(BuildPieceDefinition.PropShape.FURNACE, 1.6)
	var mouth := BuildPieceDefinition.furnace_mouth_bounds(1.6)
	assert_almost_eq(off.y, (mouth.x + mouth.y) * 0.5, 0.0001)
	assert_gt(off.z, BuildPieceDefinition.FURNACE_HALF_DEPTH)
	assert_eq(BuildPieceDefinition.prop_light_offset(BuildPieceDefinition.PropShape.ANVIL, 0.85), Vector3.ZERO)

func test_station_collision_boxes_cover_the_mesh() -> void:
	for shape in [BuildPieceDefinition.PropShape.FURNACE, BuildPieceDefinition.PropShape.ANVIL]:
		var d := _prop_def(shape, 1.6 if shape == BuildPieceDefinition.PropShape.FURNACE else 0.85)
		var size := d.get_box_size(BuildGrid.CELL)
		var center := d.get_box_center()
		var mesh := BuildPieceDefinition.build_prop_mesh(d.height, shape)
		var lo := center - size * 0.5
		var hi := center + size * 0.5
		for v: Vector3 in _mesh_vertices(mesh):
			if v.y < 0.0:
				continue  # Sockel taucht unter y=0 ein (wie bei den anderen Requisiten)
			assert_true(v.x >= lo.x - 0.1 and v.x <= hi.x + 0.1, "shape %d: x %f außerhalb der Hüllbox" % [shape, v.x])
			assert_true(v.z >= lo.z - 0.1 and v.z <= hi.z + 0.1, "shape %d: z %f außerhalb der Hüllbox" % [shape, v.z])
			assert_true(v.y <= hi.y + 0.0001, "shape %d: y %f über der Hüllbox" % [shape, v.y])

func test_station_pieces_fit_in_one_cell() -> void:
	for shape in [BuildPieceDefinition.PropShape.FURNACE, BuildPieceDefinition.PropShape.ANVIL]:
		var d := _prop_def(shape, 1.6)
		var size := d.get_box_size(BuildGrid.CELL)
		assert_lt(size.x, BuildGrid.CELL, "shape %d breiter als eine Zelle" % shape)
		assert_lt(size.z, BuildGrid.CELL, "shape %d tiefer als eine Zelle" % shape)

func test_furnace_has_light_only_with_range() -> void:
	var d := _prop_def(BuildPieceDefinition.PropShape.FURNACE, 1.6)
	assert_false(d.has_light())
	d.light_range = 4.5
	assert_true(d.has_light())

# ─────────────────────────────────────────────────────────────────────────────────────────────
# Handwerks-Requisiten (BARREL/MARKET_STALL/BAKE_OVEN/WORKBENCH) + Berufs-Gebäude
# ─────────────────────────────────────────────────────────────────────────────────────────────

## Die zwölf Handwerks-/Kleinigkeiten-PropShapes (Hochofen/Amboss sind Schmiede-Stationen und haben eigene Tests) (Wunsch "mehr Strukturen, was es im Mittelalter an Berufen gab").
func _craft_shapes() -> Array[int]:
	var out: Array[int] = []
	for s: int in [
		BuildPieceDefinition.PropShape.BARREL, BuildPieceDefinition.PropShape.MARKET_STALL,
		BuildPieceDefinition.PropShape.BAKE_OVEN, BuildPieceDefinition.PropShape.WORKBENCH,
		BuildPieceDefinition.PropShape.CRATE, BuildPieceDefinition.PropShape.SACKS,
		BuildPieceDefinition.PropShape.BENCH, BuildPieceDefinition.PropShape.TABLE,
		BuildPieceDefinition.PropShape.CART, BuildPieceDefinition.PropShape.BANNER,
		BuildPieceDefinition.PropShape.PILLAR, BuildPieceDefinition.PropShape.FIREPIT,
		BuildPieceDefinition.PropShape.TROUGH, BuildPieceDefinition.PropShape.WOODPILE,
		BuildPieceDefinition.PropShape.GARDEN_BED, BuildPieceDefinition.PropShape.SCARECROW,
		BuildPieceDefinition.PropShape.WEAPON_RACK,
	]:
		out.append(s)
	return out

func test_craft_props_are_registered_and_valid() -> void:
	var expected: Dictionary = {
		"barrel": BuildPieceDefinition.PropShape.BARREL,
		"market_stall_red": BuildPieceDefinition.PropShape.MARKET_STALL,
		"market_stall_blue": BuildPieceDefinition.PropShape.MARKET_STALL,
		"bake_oven": BuildPieceDefinition.PropShape.BAKE_OVEN,
		"workbench": BuildPieceDefinition.PropShape.WORKBENCH,
		"crate": BuildPieceDefinition.PropShape.CRATE,
		"sacks": BuildPieceDefinition.PropShape.SACKS,
		"bench_wood": BuildPieceDefinition.PropShape.BENCH,
		"table_wood": BuildPieceDefinition.PropShape.TABLE,
		"hand_cart": BuildPieceDefinition.PropShape.CART,
		"banner_red": BuildPieceDefinition.PropShape.BANNER,
		"banner_blue": BuildPieceDefinition.PropShape.BANNER,
		"pillar_stone": BuildPieceDefinition.PropShape.PILLAR,
		"pillar_wood": BuildPieceDefinition.PropShape.PILLAR,
		"firepit": BuildPieceDefinition.PropShape.FIREPIT,
		"trough_water": BuildPieceDefinition.PropShape.TROUGH,
		"trough_feed": BuildPieceDefinition.PropShape.TROUGH,
		"woodpile": BuildPieceDefinition.PropShape.WOODPILE,
		"garden_bed_herbs": BuildPieceDefinition.PropShape.GARDEN_BED,
		"garden_bed_flowers": BuildPieceDefinition.PropShape.GARDEN_BED,
		"scarecrow": BuildPieceDefinition.PropShape.SCARECROW,
		"weapon_rack": BuildPieceDefinition.PropShape.WEAPON_RACK,
	}
	var found: Dictionary = {}
	for path: String in DataManifest.BUILD_PIECES:
		var def := load(path) as BuildPieceDefinition
		if def != null and expected.has(def.id):
			found[def.id] = def
	for id: String in expected.keys():
		assert_true(found.has(id), "%s fehlt in DataManifest.BUILD_PIECES" % id)
		if not found.has(id):
			continue
		var d: BuildPieceDefinition = found[id]
		assert_eq(d.kind, TARGET, id)
		assert_eq(d.prop_shape, expected[id], id)
		assert_false(d.cost.is_empty(), "%s ohne Baukosten" % id)
		assert_false(d.has_light(), "%s soll kein Licht werfen" % id)
		# Die .tres-Höhe darf nicht unter der Mindesthöhe liegen (sonst wirkt sie gar nicht).
		assert_true(d.height >= BuildPieceDefinition.craft_prop_height(d.prop_shape, 0.0) - 0.0001, "%s unter Mindesthöhe" % id)
		var fp: Vector2 = BuildPieceDefinition.craft_prop_footprint(d.prop_shape)
		assert_true(fp.x <= BuildGrid.CELL and fp.y <= BuildGrid.CELL, "%s passt nicht in eine Zelle" % id)

func test_is_craft_prop_only_for_the_craft_shapes() -> void:
	for shape: int in BuildPieceDefinition.PropShape.values():
		assert_eq(BuildPieceDefinition.is_craft_prop(shape), _craft_shapes().has(shape), "PropShape %d" % shape)

func test_craft_prop_surface_roles() -> void:
	var main: int = BuildPieceDefinition.PropSurface.MAIN
	var accent: int = BuildPieceDefinition.PropSurface.ACCENT
	var glow: int = BuildPieceDefinition.PropSurface.GLOW
	for shape: int in [BuildPieceDefinition.PropShape.BARREL, BuildPieceDefinition.PropShape.MARKET_STALL,
			BuildPieceDefinition.PropShape.WORKBENCH, BuildPieceDefinition.PropShape.CRATE,
			BuildPieceDefinition.PropShape.SACKS, BuildPieceDefinition.PropShape.TABLE,
			BuildPieceDefinition.PropShape.CART, BuildPieceDefinition.PropShape.BANNER,
			BuildPieceDefinition.PropShape.TROUGH, BuildPieceDefinition.PropShape.WOODPILE,
			BuildPieceDefinition.PropShape.GARDEN_BED, BuildPieceDefinition.PropShape.SCARECROW,
			BuildPieceDefinition.PropShape.WEAPON_RACK]:
		var roles := BuildPieceDefinition.prop_surface_roles(shape)
		assert_eq(roles.size(), 2, "PropShape %d" % shape)
		assert_eq(roles[0], main, "PropShape %d" % shape)
		assert_eq(roles[1], accent, "PropShape %d" % shape)
	var oven := BuildPieceDefinition.prop_surface_roles(BuildPieceDefinition.PropShape.BAKE_OVEN)
	assert_eq(oven.size(), 2)
	assert_eq(oven[1], glow, "Backofen: letzte Fläche ist die Glut")
	# Bank und Säule haben nur eine Fläche, die Feuerstelle drei (Stein, Scheite, Glut).
	assert_eq(BuildPieceDefinition.prop_surface_roles(BuildPieceDefinition.PropShape.BENCH).size(), 1)
	assert_eq(BuildPieceDefinition.prop_surface_roles(BuildPieceDefinition.PropShape.PILLAR).size(), 1)
	var fire := BuildPieceDefinition.prop_surface_roles(BuildPieceDefinition.PropShape.FIREPIT)
	assert_eq(fire.size(), 3)
	assert_eq(fire[2], glow, "Feuerstelle: letzte Fläche ist die Glut")

func test_craft_props_mesh_top_matches_height_and_clamps_to_minimum() -> void:
	# Gesamthöhe = höchster Mesh-Punkt (Hüllbox kann nie kürzer sein als die sichtbare Geometrie);
	# ein zu kleines `height` wird auf die Mindesthöhe angehoben, Mesh UND Hüllbox gleichermaßen.
	for shape: int in _craft_shapes():
		for requested: float in [0.1, 1.0, 2.0, 3.0]:
			var expected_h: float = BuildPieceDefinition.craft_prop_height(shape, requested)
			var mesh := BuildPieceDefinition.build_prop_mesh(requested, shape)
			assert_almost_eq(_mesh_max_y(mesh), expected_h, 0.001, "PropShape %d, height %.1f" % [shape, requested])
			var def := _prop_def(shape, requested)
			assert_almost_eq(def.get_box_size(BuildGrid.CELL).y, expected_h, 0.0001, "Hüllbox PropShape %d" % shape)
			assert_almost_eq(def.get_box_center().y * 2.0, expected_h, 0.0001, "Hüllbox-Mitte PropShape %d" % shape)

func test_craft_props_mesh_stays_inside_footprint() -> void:
	for shape: int in _craft_shapes():
		var fp: Vector2 = BuildPieceDefinition.craft_prop_footprint(shape)
		var def := _prop_def(shape, 2.0)
		var box: Vector3 = def.get_box_size(BuildGrid.CELL)
		assert_almost_eq(box.x, fp.x, 0.0001, "Hüllbox-Breite PropShape %d" % shape)
		assert_almost_eq(box.z, fp.y, 0.0001, "Hüllbox-Tiefe PropShape %d" % shape)
		for v: Vector3 in _mesh_vertices(BuildPieceDefinition.build_prop_mesh(2.0, shape)):
			assert_true(absf(v.x) <= fp.x * 0.5 + 0.001, "PropShape %d: x=%.3f außerhalb" % [shape, v.x])
			assert_true(absf(v.z) <= fp.y * 0.5 + 0.001, "PropShape %d: z=%.3f außerhalb" % [shape, v.z])
			assert_true(v.y >= -0.001, "PropShape %d: y=%.3f unter dem Boden" % [shape, v.y])

func test_craft_props_have_collision_hull_not_walkthrough() -> void:
	# Anders als die Kapelle sind alle vier massiv: keine Einzelboxen, die Hüllbox kollidiert.
	for shape: int in _craft_shapes():
		assert_true(_prop_def(shape, 2.0).get_prop_collision_boxes().is_empty(), "PropShape %d" % shape)

## Die Berufs-Gebäude (HouseTemplateDefinition) müssen als GANZES platzierbar sein — WorldBuildHandler
## ist all-or-nothing, ein einziges Teil mit Regelverstoß macht die ganze Vorlage unbaubar. Geprüft
## wird hier die reine Datenkonsistenz (dieselben Schlüsselräume wie BuildGrid): bekannte Teile mit
## passendem kind, keine doppelten Schlüssel, jedes Dach hat eine Wand/Tür/ein Fenster/einen Zaun auf einer
## seiner vier Zellkanten (BuildRegistry.walls_around_cell → sonst "unsupported"), keine Requisite
## blockiert eine Tür. Siehe tools/building_templates/generate_craft_templates.py (erzeugt + prüft dasselbe).
const CRAFT_TEMPLATE_IDS: Array[String] = [
	"smithy", "bakery", "carpenter_shop", "market_square", "tavern", "farmstead", "craft_quarter",
	"gate_arch", "city_gate", "village_square", "wall_walk", "city_gate_grand",
	"herb_garden", "stable", "barn", "wall_corner", "barracks", "feast_hall", "fortress_yard",
]

func test_craft_house_templates_are_registered_and_consistent() -> void:
	var kinds: Dictionary = {}
	for path: String in DataManifest.BUILD_PIECES:
		var def := load(path) as BuildPieceDefinition
		if def != null:
			kinds[def.id] = def.kind
	var templates: Dictionary = {}
	for path: String in DataManifest.HOUSE_TEMPLATES:
		var tpl := load(path) as HouseTemplateDefinition
		assert_not_null(tpl, "%s ist keine HouseTemplateDefinition" % path)
		if tpl == null:
			continue
		assert_false(templates.has(tpl.id), "doppelte Vorlagen-ID %s" % tpl.id)
		templates[tpl.id] = tpl
	for tid: String in CRAFT_TEMPLATE_IDS:
		assert_true(templates.has(tid), "%s fehlt in DataManifest.HOUSE_TEMPLATES" % tid)
		if templates.has(tid):
			_assert_house_template_consistent(templates[tid] as HouseTemplateDefinition, kinds)

func _assert_house_template_consistent(tpl: HouseTemplateDefinition, kinds: Dictionary) -> void:
	assert_false(tpl.pieces.is_empty(), "%s ohne Teile" % tpl.id)
	var keys: Dictionary = {}
	var wall_edges: Dictionary = {}            # "W<axis>_<x>_<z>_S<ebene>" -> true
	var floor_cells: Dictionary = {}           # "<x>_<z>_S<ebene>" -> true
	var door_edges: Array[Vector3i] = []
	var prop_cells: Dictionary = {}
	var roof_cells: Array[Vector3i] = []       # x, z, ebene
	var upper_cells: Array[Vector3i] = []      # Böden/Requisiten/Treppen auf Ebene > 0
	var upper_walls: Array[Vector4i] = []      # axis, x, z, ebene (Ebene > 0)
	for e: Dictionary in tpl.pieces:
		var pid: String = String(e.get("piece_id", ""))
		assert_true(kinds.has(pid), "%s: unbekanntes Bauteil '%s'" % [tpl.id, pid])
		if not kinds.has(pid):
			continue
		var kind: int = int(e["kind"])
		assert_eq(kind, int(kinds[pid]), "%s: kind von '%s' stimmt nicht mit der Definition" % [tpl.id, pid])
		var axis: int = int(e["axis"])
		var dx: int = int(e["dx"])
		var dz: int = int(e["dz"])
		var st: int = int(e.get("storey", 0))
		var key: String
		match kind:
			WALL, DOOR, WINDOW:
				key = "W%d_%d_%d_S%d" % [posmod(axis, 2), dx, dz, st]
				wall_edges[key] = true
				if kind == DOOR and st == 0:
					door_edges.append(Vector3i(posmod(axis, 2), dx, dz))
				if st > 0:
					upper_walls.append(Vector4i(posmod(axis, 2), dx, dz, st))
			FLOOR:
				key = "F_%d_%d_S%d" % [dx, dz, st]
				floor_cells["%d_%d_S%d" % [dx, dz, st]] = true
				if st > 0:
					upper_cells.append(Vector3i(dx, dz, st))
			ROOF:
				key = "R_%d_%d_S%d" % [dx, dz, st]
				roof_cells.append(Vector3i(dx, dz, st))
			STAIRS:
				key = "T_%d_%d_S%d" % [dx, dz, st]
				if st > 0:
					upper_cells.append(Vector3i(dx, dz, st))
			_:
				key = "P_%d_%d_S%d" % [dx, dz, st]
				if st == 0:
					prop_cells[Vector2i(dx, dz)] = true
				else:
					upper_cells.append(Vector3i(dx, dz, st))
		assert_false(keys.has(key), "%s: doppelter Schlüssel %s" % [tpl.id, key])
		keys[key] = true
	# Dach-Regel wie BuildPlacementRules._check_roof (je Ebene): eigene Wand oder lückenlose Dachkette bis zur
	# Überhang-Reichweite.
	var roofs_by_storey: Dictionary = {}
	for c3: Vector3i in roof_cells:
		if not roofs_by_storey.has(c3.z):
			roofs_by_storey[c3.z] = []
		(roofs_by_storey[c3.z] as Array).append(Vector2i(c3.x, c3.y))
	for st: int in roofs_by_storey.keys():
		var cells_on_storey: Array = roofs_by_storey[st]
		var tier: Dictionary = {}
		for c: Vector2i in cells_on_storey:
			if _has_wall_around(wall_edges, c.x, c.y, st):
				tier[c] = 0
		for hop in range(1, BuildPlacementRules.ROOF_OVERHANG_REACH + 1):
			for c: Vector2i in cells_on_storey:
				if tier.has(c):
					continue
				for n: Vector2i in [c + Vector2i.LEFT, c + Vector2i.RIGHT, c + Vector2i.UP, c + Vector2i.DOWN]:
					if tier.get(n, -1) == hop - 1:
						tier[c] = hop
						break
		for c: Vector2i in cells_on_storey:
			assert_true(tier.has(c), "%s: Dach bei Zelle %s Ebene %d hat keine Wand rundherum (unsupported)" % [tpl.id, c, st])
	for c: Vector3i in upper_cells:
		assert_true(_has_wall_around(wall_edges, c.x, c.y, c.z - 1),
			"%s: Teil bei Zelle (%d,%d) Ebene %d hat keine Wand der Ebene darunter als Auflager" % [tpl.id, c.x, c.y, c.z])
	# Obergeschoss-Wände brauchen eine Wand darunter (gleiche Kante, Ebene − 1) oder einen Boden daneben.
	for w: Vector4i in upper_walls:
		var below: bool = wall_edges.has("W%d_%d_%d_S%d" % [w.x, w.y, w.z, w.w - 1])
		var beside: Array[Vector2i] = []
		if w.x == 0:
			beside.append(Vector2i(w.y, w.z - 1))
			beside.append(Vector2i(w.y, w.z))
		else:
			beside.append(Vector2i(w.y - 1, w.z))
			beside.append(Vector2i(w.y, w.z))
		var on_floor: bool = false
		for cell: Vector2i in beside:
			if floor_cells.has("%d_%d_S%d" % [cell.x, cell.y, w.w]):
				on_floor = true
		assert_true(below or on_floor, "%s: Wand (%d,%d,%d) Ebene %d steht weder auf einer Wand darunter noch an einem Boden" % [tpl.id, w.x, w.y, w.z, w.w])
	for d: Vector3i in door_edges:
		var door_cells: Array[Vector2i] = []
		if d.x == 0:
			door_cells.append(Vector2i(d.y, d.z - 1))
			door_cells.append(Vector2i(d.y, d.z))
		else:
			door_cells.append(Vector2i(d.y - 1, d.z))
			door_cells.append(Vector2i(d.y, d.z))
		for cell: Vector2i in door_cells:
			assert_false(prop_cells.has(cell), "%s: Requisite auf Zelle %s blockiert die Tür" % [tpl.id, cell])

## Hat die Zelle (x,z) auf `storey` eine Wand/Tür/ein Fenster auf einer ihrer vier Kanten?
func _has_wall_around(wall_edges: Dictionary, x: int, z: int, storey: int) -> bool:
	for k: String in ["W0_%d_%d_S%d" % [x, z, storey], "W0_%d_%d_S%d" % [x, z + 1, storey],
			"W1_%d_%d_S%d" % [x, z, storey], "W1_%d_%d_S%d" % [x + 1, z, storey]]:
		if wall_edges.has(k):
			return true
	return false

# ── Dach-Überhang (Wunsch "nicht jedes Dachstück braucht eine tragende Wand") ─────────────

func _add_roof_record(cx: int, cz: int, y: float, storey: int = 0) -> void:
	_registry.add({"key": BuildGrid.roof_key(Vector2i(cx, cz), storey), "piece_id": "wood_roof",
		"kind": ROOF, "x": 0.0, "y": y, "z": 0.0, "yaw": 0.0, "owner": "", "storey": storey})

func _roof_check(cx: int, cz: int, storey: int = 0) -> Dictionary:
	var snap := BuildGrid.snap_from_cell(ROOF, 0, cx, cz, storey)
	return BuildPlacementRules.check(_roof_def, snap, _registry, _flat(0.0))

func test_roof_overhangs_one_cell_beside_a_supported_roof() -> void:
	_add_wall(0, 0, 0, 1.0)              # trägt Zelle (0,0)
	_add_roof_record(0, 0, 1.0 + BuildGrid.LEVEL_HEIGHT)
	var res := _roof_check(1, 0)        # Nachbarzelle ohne eigene Wand
	assert_true(res["ok"])
	assert_almost_eq(float(res["y"]), 1.0 + BuildGrid.LEVEL_HEIGHT, 0.0001, "Traufe vom tragenden Nachbardach")

func test_roof_overhang_chains_up_to_three_cells() -> void:
	_add_wall(0, 0, 0, 0.0)
	_add_roof_record(0, 0, BuildGrid.LEVEL_HEIGHT)
	_add_roof_record(1, 0, BuildGrid.LEVEL_HEIGHT)    # selbst nur Überhang (keine Wand rundherum)
	_add_roof_record(2, 0, BuildGrid.LEVEL_HEIGHT)
	var res := _roof_check(3, 0)                      # drei Zellen vom tragenden Dach
	assert_true(res["ok"], "Kette bis Reichweite 3 ist erlaubt")
	assert_almost_eq(float(res["y"]), BuildGrid.LEVEL_HEIGHT, 0.0001, "Traufe vom tragenden Dach")

func test_roof_overhang_stops_at_reach_three() -> void:
	_add_wall(0, 0, 0, 0.0)
	_add_roof_record(0, 0, BuildGrid.LEVEL_HEIGHT)
	_add_roof_record(1, 0, BuildGrid.LEVEL_HEIGHT)
	_add_roof_record(2, 0, BuildGrid.LEVEL_HEIGHT)
	_add_roof_record(3, 0, BuildGrid.LEVEL_HEIGHT)
	var res := _roof_check(4, 0)                      # vier Zellen entfernt: zu weit
	assert_false(res["ok"], "Reichweite 3 überschritten")
	assert_eq(res["reason"], "unsupported")

func test_roof_overhang_needs_an_unbroken_roof_chain() -> void:
	_add_wall(0, 0, 0, 0.0)
	_add_roof_record(0, 0, BuildGrid.LEVEL_HEIGHT)
	var res := _roof_check(2, 0)                      # Lücke bei (1,0): kein Halt über die Lücke hinweg
	assert_false(res["ok"])
	assert_eq(res["reason"], "unsupported")

func test_roof_overhang_prefers_nearest_support_eave() -> void:
	_add_wall(0, 0, 0, 0.0)                           # tief
	_add_wall(0, 4, 0, 1.0)                           # höher, aber weiter weg
	_add_roof_record(0, 0, BuildGrid.LEVEL_HEIGHT)
	_add_roof_record(4, 0, 1.0 + BuildGrid.LEVEL_HEIGHT)
	_add_roof_record(1, 0, BuildGrid.LEVEL_HEIGHT)
	_add_roof_record(3, 0, 1.0 + BuildGrid.LEVEL_HEIGHT)
	var res := _roof_check(2, 0)                      # beidseitig 2 Zellen: das höchste der gleich nahen gewinnt
	assert_true(res["ok"])
	assert_almost_eq(float(res["y"]), 1.0 + BuildGrid.LEVEL_HEIGHT, 0.0001)

func test_roof_overhang_ignores_other_storeys() -> void:
	_add_wall(0, 0, 0, 0.0, 1)
	_add_roof_record(0, 0, BuildGrid.LEVEL_HEIGHT * 2.0, 1)
	var res := _roof_check(1, 0, 0)
	assert_false(res["ok"])
	assert_eq(res["reason"], "unsupported")

func test_roof_with_own_wall_still_uses_wall_height() -> void:
	_add_wall(0, 1, 0, 0.5)
	_add_roof_record(0, 0, 9.0)           # Nachbardach höher — darf die eigene Wand nicht überstimmen
	_add_wall(0, 0, 0, 0.0)
	var res := _roof_check(1, 0)
	assert_true(res["ok"])
	assert_almost_eq(float(res["y"]), 0.5 + BuildGrid.LEVEL_HEIGHT, 0.0001)

## Regression: VillageChurch (3×4 Zellen) hatte zwei innere Dachzellen ohne Wand → Vorlage war
## unbaubar. Mit Überhang muss jedes Dach der Vorlage in Template-Reihenfolge platzierbar sein.
func test_village_church_roofs_are_all_placeable_with_overhang() -> void:
	_assert_template_roofs_placeable("res://data/building/houses/VillageChurch.tres")

## Gleiche Prüfung für die großen Hallen mit Überhang-Dächern (Scheune, Kaserne): Dächer mit eigener
## Wand stehen in der Datei VOR den Überhängen, damit die Reihenfolge für jede Drehung des Hauses stimmt.
func test_barn_roofs_are_all_placeable_with_overhang() -> void:
	_assert_template_roofs_placeable("res://data/building/houses/Barn.tres")

## Festhalle: die mittlere Dachreihe hängt zwei Zellen von der nächsten Wand — braucht eine Überhang-Kette.
func test_feast_hall_roofs_are_all_placeable_with_overhang_chain() -> void:
	_assert_template_roofs_placeable("res://data/building/houses/FeastHall.tres")

func test_barracks_roofs_are_all_placeable_with_overhang() -> void:
	_assert_template_roofs_placeable("res://data/building/houses/Barracks.tres")

func _assert_template_roofs_placeable(path: String) -> void:
	var tpl := load(path) as HouseTemplateDefinition
	assert_not_null(tpl, path)
	if tpl == null:
		return
	for e: Dictionary in tpl.pieces:
		var kind: int = int(e["kind"])
		if kind == WALL or kind == DOOR or kind == WINDOW:
			_add_wall(int(e["axis"]), int(e["dx"]), int(e["dz"]), 0.0)
	for e: Dictionary in tpl.pieces:
		if int(e["kind"]) != ROOF:
			continue
		var cx: int = int(e["dx"])
		var cz: int = int(e["dz"])
		var res := _roof_check(cx, cz)
		assert_true(res["ok"], "Dach (%d,%d) nicht platzierbar: %s" % [cx, cz, res["reason"]])
		if res["ok"]:
			_add_roof_record(cx, cz, float(res["y"]))

# ── Torbögen (OpeningShape.ARCH) und Zinnenmauer (WallTop.CRENELLATED) ───────────────────────

func _load_piece(id: String) -> BuildPieceDefinition:
	for path: String in DataManifest.BUILD_PIECES:
		var def := load(path) as BuildPieceDefinition
		if def != null and def.id == id:
			return def
	return null

func _boxes_cover(boxes: Array[Dictionary], x: float, y: float) -> bool:
	for b: Dictionary in boxes:
		var size: Vector3 = b["size"]
		var center: Vector3 = b["center"]
		if absf(x - center.x) <= size.x * 0.5 + 0.0001 and absf(y - center.y) <= size.y * 0.5 + 0.0001:
			return true
	return false

func test_arch_pieces_are_registered_with_the_right_kind() -> void:
	var expected: Dictionary = {
		"stone_gate_arch": DOOR, "stone_arch_door": DOOR, "wood_arch_door": DOOR,
		"stone_arch_window": WINDOW, "wood_arch_window": WINDOW,
	}
	for id: String in expected.keys():
		var def := _load_piece(id)
		assert_not_null(def, "%s fehlt in DataManifest.BUILD_PIECES" % id)
		if def == null:
			continue
		assert_eq(def.kind, expected[id], id)
		assert_eq(def.opening_shape, BuildPieceDefinition.OpeningShape.ARCH, id)
		assert_true(def.opening_width > 0.0 and def.opening_width < BuildGrid.CELL, "%s: Breite" % id)
		assert_true(def.opening_height > 0.0 and def.opening_height <= def.height, "%s: Scheitelhöhe" % id)

func test_arch_openings_are_free_inside_and_wall_is_sealed_outside() -> void:
	# Dieselbe Stichprobe wie die Python-Nachrechnung beim Bau: innerhalb der Treppen-Öffnung darf
	# keine Box stehen, außerhalb der echten Bogenkurve muss die Wand dicht sein (Tür: der Bereich
	# unter dem Boden zwischen den Pfosten bleibt bewusst offen, wir tasten nur y >= 0 ab).
	var cell: float = BuildGrid.CELL
	for id: String in ["stone_gate_arch", "stone_arch_door", "wood_arch_door", "stone_arch_window", "wood_arch_window"]:
		var def := _load_piece(id)
		if def == null:
			fail_test("%s fehlt" % id)
			continue
		var boxes: Array[Dictionary] = def.get_window_boxes(cell) if def.is_window() else def.get_door_boxes(cell)
		for b: Dictionary in boxes:
			var size: Vector3 = b["size"]
			var center: Vector3 = b["center"]
			assert_true(absf(center.x) + size.x * 0.5 <= cell * 0.5 + 0.0001, "%s: Box ragt seitlich aus der Zelle" % id)
			assert_true(center.y - size.y * 0.5 >= -def.skirt - 0.0001, "%s: Box ragt unter den Mauerfuß" % id)
			assert_true(center.y + size.y * 0.5 <= def.height + 0.0001, "%s: Box ragt über die Wandhöhe" % id)
		var half_w: float = def.opening_width * 0.5
		var sill: float = BuildPieceDefinition.WINDOW_SILL if def.is_window() else 0.0
		var apex: float = def.opening_height
		var rise: float = minf(half_w, apex - sill - 0.1)
		var spring: float = apex - rise
		var steps: int = BuildPieceDefinition.ARCH_STEPS
		for xi in range(-99, 100, 3):
			var x: float = float(xi) / 100.0
			# Proben bewusst NEben den Kanten (Brüstung, Stufenränder liegen auf Vielfachen von 0,09 m):
			# genau auf einer geteilten Kante ist "frei" vs. "von Box bedeckt" reine Gleitkomma-Frage.
			for yi in range(0, int(def.height * 100.0), 3):
				var y: float = (float(yi) + 0.7) / 100.0
				var free_width: float = -1.0   # Halbbreite der Treppen-Öffnung auf dieser Höhe (<0 = Wand)
				if y >= sill and y <= spring:
					free_width = half_w
				elif y > spring and y < apex:
					var band: int = mini(int((y - spring) / rise * float(steps)), steps - 1)
					var t: float = float(band + 1) / float(steps)
					free_width = half_w * sqrt(maxf(1.0 - t * t, 0.0))
				if free_width > 0.0 and absf(x) < free_width - 0.001:
					assert_false(_boxes_cover(boxes, x, y), "%s: Öffnung blockiert bei x=%.2f y=%.2f" % [id, x, y])
				var outside: bool = absf(x) > half_w + 0.001 or y < sill - 0.001 or y > apex + 0.001
				if not outside and y > spring:
					var e: float = pow(x / half_w, 2.0) + pow((y - spring) / rise, 2.0)
					outside = e > 1.001
				if outside:
					assert_true(_boxes_cover(boxes, x, y), "%s: Loch in der Wand bei x=%.2f y=%.2f" % [id, x, y])

func test_rect_door_and_window_boxes_ignore_the_new_fields_by_default() -> void:
	# Regression: ohne opening_* / ARCH bleibt alles wie vor dem Torbogen-Umbau.
	var door := _load_piece("wood_door")
	var window := _load_piece("wood_window")
	assert_eq(door.opening_shape, BuildPieceDefinition.OpeningShape.RECT)
	assert_eq(window.opening_shape, BuildPieceDefinition.OpeningShape.RECT)
	var d: Array[Dictionary] = door.get_door_boxes(BuildGrid.CELL)
	assert_eq(d.size(), 3, "Tür: zwei Pfosten + Sturz")
	assert_almost_eq((d[2]["size"] as Vector3).x, BuildPieceDefinition.DOOR_WIDTH, 0.0001)
	var w: Array[Dictionary] = window.get_window_boxes(BuildGrid.CELL)
	assert_eq(w.size(), 4, "Fenster: zwei Pfosten, Brüstung, Sturz")
	assert_almost_eq((w[2]["size"] as Vector3).x, BuildPieceDefinition.WINDOW_WIDTH, 0.0001)

func test_crenellated_wall_has_merlons_inside_the_wall_height() -> void:
	var def := _load_piece("stone_wall_crenel")
	assert_not_null(def)
	if def == null:
		return
	assert_eq(def.kind, WALL)
	assert_true(def.has_crenellations())
	assert_false(_load_piece("stone_wall").has_crenellations(), "glatte Wand bleibt glatt")
	var boxes: Array[Dictionary] = def.get_wall_boxes(BuildGrid.CELL)
	assert_eq(boxes.size(), 4, "Körper + halbe Zinne + ganze Zinne + halbe Zinne")
	var top: float = -INF
	for b: Dictionary in boxes:
		var size: Vector3 = b["size"]
		var center: Vector3 = b["center"]
		top = maxf(top, center.y + size.y * 0.5)
		assert_true(absf(center.x) + size.x * 0.5 <= BuildGrid.CELL * 0.5 + 0.0001)
	assert_almost_eq(top, def.height, 0.0001, "Zinnen enden genau auf der Wandhöhe")
	var y_gap: float = def.height - 0.1
	assert_false(_boxes_cover(boxes, -0.5, y_gap), "Lücke links")
	assert_false(_boxes_cover(boxes, 0.5, y_gap), "Lücke rechts")
	assert_true(_boxes_cover(boxes, 0.0, y_gap), "ganze Zinne in der Mitte")
	assert_true(_boxes_cover(boxes, -0.99, y_gap), "halbe Zinne an der linken Zellkante")
	assert_true(_boxes_cover(boxes, 0.99, y_gap), "halbe Zinne an der rechten Zellkante")
	assert_true(_boxes_cover(boxes, 0.5, def.height - BuildPieceDefinition.WALL_MERLON_HEIGHT - 0.05), "Mauerkörper unter den Zinnen ist durchgehend")

# ── Torflügel (LeafState), Wehrgang-Teile ────────────────────────────────────────────────────

## Blockiert irgendeine Box den Punkt (x, y) in der Durchgangsebene z? (3D-Variante von _boxes_cover —
## offene Flügel liegen versetzt in z und sperren den Durchgang NICHT.)
func _boxes_block(boxes: Array[Dictionary], x: float, y: float, z: float) -> bool:
	for b: Dictionary in boxes:
		var size: Vector3 = b["size"]
		var center: Vector3 = b["center"]
		if absf(x - center.x) <= size.x * 0.5 + 0.0001 and absf(y - center.y) <= size.y * 0.5 + 0.0001 \
				and absf(z - center.z) <= size.z * 0.5 + 0.0001:
			return true
	return false

func test_gate_leaf_pieces_are_registered() -> void:
	var expected: Dictionary = {
		"wood_door_open": BuildPieceDefinition.LeafState.OPEN, "wood_door_closed": BuildPieceDefinition.LeafState.CLOSED,
		"wood_gate_open": BuildPieceDefinition.LeafState.OPEN, "wood_gate_closed": BuildPieceDefinition.LeafState.CLOSED,
		"stone_gate_open": BuildPieceDefinition.LeafState.OPEN, "stone_gate_closed": BuildPieceDefinition.LeafState.CLOSED,
	}
	for id: String in expected.keys():
		var def := _load_piece(id)
		assert_not_null(def, "%s fehlt in DataManifest.BUILD_PIECES" % id)
		if def != null:
			assert_eq(def.kind, DOOR, id)
			assert_eq(def.leaf_state, expected[id], id)
	assert_eq(_load_piece("wood_door").leaf_state, BuildPieceDefinition.LeafState.NONE, "alte Tür bleibt ein offener Durchgang")
	assert_eq(_load_piece("stone_gate_arch").leaf_state, BuildPieceDefinition.LeafState.NONE)

func test_open_gate_leaves_keep_the_passage_free_and_stay_in_the_cell() -> void:
	for id: String in ["wood_gate_open", "stone_gate_open", "wood_door_open"]:
		var def := _load_piece(id)
		var plain := _load_piece("wood_door") if def.opening_shape == BuildPieceDefinition.OpeningShape.RECT else _load_piece("stone_gate_arch")
		var boxes: Array[Dictionary] = def.get_door_boxes(BuildGrid.CELL)
		assert_eq(boxes.size(), plain.get_door_boxes(BuildGrid.CELL).size() + 2, "%s: Rahmen + zwei Flügel" % id)
		for b: Dictionary in boxes:
			var size: Vector3 = b["size"]
			var center: Vector3 = b["center"]
			assert_true(absf(center.z) + size.z * 0.5 <= BuildGrid.CELL * 0.5 + 0.0001, "%s: Flügel ragt aus der Zelle" % id)
		for xi in range(-40, 41, 5):
			for yi in range(5, 190, 10):
				assert_false(_boxes_block(boxes, float(xi) / 100.0, float(yi) / 100.0, 0.0),
					"%s: Durchgang blockiert bei x=%.2f y=%.2f" % [id, float(xi) / 100.0, float(yi) / 100.0])

func test_closed_gate_leaves_fill_the_whole_opening() -> void:
	var steps: int = BuildPieceDefinition.ARCH_STEPS
	for id: String in ["wood_gate_closed", "stone_gate_closed"]:
		var def := _load_piece(id)
		var boxes: Array[Dictionary] = def.get_door_boxes(BuildGrid.CELL)
		var half_w: float = def.opening_width * 0.5
		var rise: float = minf(half_w, def.opening_height - 0.1)
		var spring: float = def.opening_height - rise
		for xi in range(-84, 85, 4):
			var x: float = float(xi) / 100.0
			for yi in range(2, int(def.opening_height * 100.0) - 2, 4):
				var y: float = float(yi) / 100.0
				var half_open: float = half_w
				if y > spring:
					var band: int = mini(int((y - spring) / rise * float(steps)), steps - 1)
					var t: float = float(band + 1) / float(steps)
					half_open = half_w * sqrt(maxf(1.0 - t * t, 0.0))
				if absf(x) < half_open - 0.001:
					assert_true(_boxes_block(boxes, x, y, 0.0), "%s: Lücke im geschlossenen Tor bei x=%.2f y=%.2f" % [id, x, y])
	var door := _load_piece("wood_door_closed")
	assert_true(_boxes_block(door.get_door_boxes(BuildGrid.CELL), 0.0, 1.0, 0.0), "geschlossene Tür sperrt die Mitte")
	assert_false(_boxes_block(_load_piece("wood_door_open").get_door_boxes(BuildGrid.CELL), 0.0, 1.0, 0.0), "offene Tür nicht")

func test_walkway_and_parapet_pieces() -> void:
	var walkway := _load_piece("stone_walkway")
	assert_not_null(walkway)
	assert_eq(walkway.kind, FLOOR)
	assert_true(walkway.skirt > BuildGrid.LEVEL_HEIGHT * 0.8, "Wehrgang trägt einen massiven Mauerkörper nach unten")
	var parapet := _load_piece("stone_parapet")
	assert_not_null(parapet)
	assert_eq(parapet.kind, WALL)
	assert_true(parapet.has_crenellations())
	assert_true(parapet.height < BuildGrid.LEVEL_HEIGHT, "Brüstung ist niedriger als eine Mauer")
	assert_true(parapet.get_wall_boxes(BuildGrid.CELL).size() == 4)
	var wide := _load_piece("stone_gate_arch_wide")
	assert_true(wide.opening_width > _load_piece("stone_gate_arch").opening_width, "breiterer Bogen")
