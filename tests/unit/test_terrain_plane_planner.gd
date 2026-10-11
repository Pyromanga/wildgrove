# res://tests/unit/test_terrain_plane_planner.gd
extends GutTest

## Tests für TerrainPlanePlanner (Ebnen-Planung) und WorldTerrainEditor.plan_plane/edit_plane.
## Gelände wird per Callable gefaket: Basis = Funktion, Höhe = Basis + Edit-Delta.

const R := WorldTerrainEditor.BRUSH_RADIUS
const CORE := WorldTerrainEditor.CORE_RADIUS
const STEP := WorldTerrainEditor.DIG_STEP_ABS

var _layer: TerrainEditLayer
var _base_height: float = 0.0
var _refreshed: Array = []
var _registry: BuildRegistry
var _editor: WorldTerrainEditor

func before_each() -> void:
	_layer = TerrainEditLayer.new()
	_base_height = 0.0
	_refreshed = []
	_registry = BuildRegistry.new()
	_editor = WorldTerrainEditor.new(_layer, _registry, func(points: Array) -> void: _refreshed.append(points))
	_editor.set_height_fn(_height)

func _height(x: float, z: float) -> float:
	return _base_height + _layer.get_delta_at(x, z)

func _plan(plane_y: float, direction: String = TerrainPlanePlanner.DIR_BOTH) -> Dictionary:
	return TerrainPlanePlanner.plan(_layer, _height, Vector2.ZERO, R, CORE, plane_y, STEP, direction)

# ── Planung ─────────────────────────────────────

func test_flat_ground_on_plane_is_already_level() -> void:
	var plan := _plan(0.0)
	assert_false(plan["ok"])
	assert_eq(plan["reason"], "already_level")

func test_reason_depends_on_direction() -> void:
	assert_eq(_plan(0.0, TerrainPlanePlanner.DIR_DOWN)["reason"], "nothing_to_cut")
	assert_eq(_plan(0.0, TerrainPlanePlanner.DIR_UP)["reason"], "nothing_to_fill")

func test_high_ground_is_lowered_toward_plane_by_one_step() -> void:
	_base_height = 2.0
	var plan := _plan(0.0)
	assert_true(plan["ok"])
	assert_gt(float(plan["lowered"]), 0.0)
	assert_eq(float(plan["raised"]), 0.0)
	var center_delta := float((plan["changes"] as Dictionary)[Vector2i(0, 0)])
	assert_almost_eq(center_delta, -STEP, 0.0001, "Am Kern genau ein Schritt, nicht bis zur Ebene.")

func test_low_ground_is_raised() -> void:
	_base_height = -2.0
	var plan := _plan(0.0)
	assert_true(plan["ok"])
	assert_gt(float(plan["raised"]), 0.0)
	assert_eq(float(plan["lowered"]), 0.0)

func test_never_overshoots_plane() -> void:
	_base_height = 0.2   # nur 0,2 m über der Ebene, Schritt wäre 0,5
	var plan := _plan(0.0)
	var center_delta := float((plan["changes"] as Dictionary)[Vector2i(0, 0)])
	assert_almost_eq(center_delta, -0.2, 0.0001)

func test_direction_down_ignores_low_points() -> void:
	_layer.set_delta(Vector2i(0, 0), -1.0)    # Mulde in der Mitte, Rest auf Höhe 1,0 über Ebene
	_base_height = 1.0
	var plan := _plan(0.0, TerrainPlanePlanner.DIR_DOWN)
	assert_true(plan["ok"])
	assert_eq(float(plan["raised"]), 0.0)
	assert_false((plan["changes"] as Dictionary).has(Vector2i(0, 0)), "Mulde liegt auf der Ebene → unberührt.")

func test_direction_up_ignores_high_points() -> void:
	_base_height = 1.0
	var plan := _plan(0.0, TerrainPlanePlanner.DIR_UP)
	assert_false(plan["ok"])
	assert_eq(plan["reason"], "nothing_to_fill")

func test_mixed_ground_lowers_and_raises() -> void:
	_layer.set_delta(Vector2i(1, 0), 1.0)
	_layer.set_delta(Vector2i(-1, 0), -1.0)
	var plan := _plan(0.0)
	assert_true(plan["ok"])
	assert_gt(float(plan["lowered"]), 0.0)
	assert_gt(float(plan["raised"]), 0.0)
	assert_true((plan["lowered_points"] as Array).has(Vector2i(1, 0)))
	assert_true((plan["raised_points"] as Array).has(Vector2i(-1, 0)))

func test_plan_does_not_mutate_layer() -> void:
	_base_height = 2.0
	_plan(0.0)
	assert_true(_layer.is_empty())

func test_limit_reported_when_all_points_at_limit() -> void:
	# Punkte stehen schon am unteren Limit; Ebene liegt tiefer als das Gelände erreichen kann.
	_base_height = 0.0
	for p in TerrainEditLayer.lattice_points_in_radius(0.0, 0.0, R):
		_layer.set_delta(p, TerrainEditLayer.MAX_DELTA_DOWN)
	var plan := _plan(-100.0)
	assert_false(plan["ok"])
	assert_eq(plan["reason"], "limit")

func test_invalid_input_is_rejected() -> void:
	assert_false(_plan(NAN)["ok"])
	assert_false(_plan(0.0, "sideways")["ok"])

func test_repeated_application_converges_to_plane() -> void:
	_base_height = 1.3
	for i in 80:
		var plan := _plan(0.0)
		if not plan["ok"]:
			break
		_layer.apply_changes(plan["changes"])
	var h := _height(0.0, 0.0)
	assert_almost_eq(h, 0.0, 0.06, "Kern liegt nach mehreren Zügen auf der Ebene (±Quantum).")
	assert_false(_plan(0.0)["ok"], "Danach gibt es nichts mehr zu tun — kein Hin und Her.")

func test_unit_volume_matches_full_dig_brush() -> void:
	var expected := 0.0
	var probe := TerrainEditLayer.new()
	for p in probe.apply_brush(0.0, 0.0, R, -STEP, CORE):
		expected += absf(probe.get_delta_lattice(p.x, p.y))
	assert_almost_eq(TerrainPlanePlanner.unit_volume(R, CORE, STEP), expected, 0.3,
		"Einheit ≈ Volumen einer normalen Grabaktion (Quantisierung erlaubt kleine Abweichung).")

# ── Editor ──────────────────────────────────────

func test_editor_edit_plane_changes_terrain_and_refreshes() -> void:
	_base_height = 1.0
	var result := _editor.edit_plane(Vector3(0, 0, 0), 0.0)
	assert_true(result["ok"])
	assert_gt((result["changed"] as Array).size(), 0)
	assert_eq(_refreshed.size(), 1)
	assert_lt(_layer.get_delta_lattice(0, 0), 0.0)

func test_editor_blocks_near_building() -> void:
	_base_height = 1.0
	var snap := BuildGrid.snap(BuildPieceDefinition.Kind.FLOOR, Vector3(1, 0, 1), 0, 0)
	_registry.add({"key": snap["key"], "piece_id": "f", "kind": BuildPieceDefinition.Kind.FLOOR,
		"cell": snap["cell"], "axis": 0, "y": 0.0, "storey": 0})
	var result := _editor.edit_plane(Vector3(0, 0, 0), 0.0)
	assert_false(result["ok"])
	assert_eq(result["reason"], "building_nearby")
	assert_true(_layer.is_empty())

func test_editor_without_height_fn_reports_no_ground() -> void:
	var bare := WorldTerrainEditor.new(_layer, _registry, Callable())
	assert_eq(bare.plan_plane(Vector3.ZERO, 0.0)["reason"], "no_ground")

func test_editor_bad_direction() -> void:
	assert_eq(_editor.plan_plane(Vector3.ZERO, 0.0, "x")["reason"], "bad_mode")

func test_editor_preview_is_red_when_already_level() -> void:
	var preview := _editor.preview_plane(Vector3.ZERO, 0.0)
	assert_false(preview["ok"])
	assert_eq(preview["reason"], "already_level")

func test_reason_texts_exist() -> void:
	for r in ["no_plane", "already_level", "nothing_to_cut", "nothing_to_fill"]:
		assert_ne(WorldTerrainEditor.reason_text(r), WorldTerrainEditor.reason_text(""), r)
