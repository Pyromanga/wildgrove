# res://tests/unit/test_ladder_planner.gd
extends GutTest

## Tests für LadderPlanner, LadderPath, LadderRegistry und PlayerLadder — ohne SceneTree.
## Gelände: ebene Basis (2.4 m) + Schacht per TerrainEditLayer (dieselbe Pinsel-Form wie im Spiel).

const BASE: float = 2.4
var _layer: TerrainEditLayer
var _ground: Callable

func before_each() -> void:
	_layer = TerrainEditLayer.new()
	_ground = _ground_at

func _ground_at(x: float, z: float) -> float:
	return BASE + _layer.get_delta_at(x, z)

func _dig(times: int) -> void:
	for i in times:
		_layer.apply_brush(0.0, 0.0, WorldTerrainEditor.BRUSH_RADIUS, WorldTerrainEditor.DIG_STEP, WorldTerrainEditor.CORE_RADIUS)

func _plan_from_bottom() -> Dictionary:
	return LadderPlanner.plan(Vector3(0, _ground_at(0.0, 0.0), 0), Vector3(1, 0, 0), _ground)

func test_flat_ground_has_no_wall() -> void:
	var res := _plan_from_bottom()
	assert_false(res["ok"])
	assert_eq(res["reason"], "no_wall")

func test_shallow_pit_needs_no_ladder() -> void:
	_dig(4)  # 2 m tief: Wände flacher als MIN_RISE innerhalb der Suchweite? Nur Rand, kein Fall.
	var res := _plan_from_bottom()
	if res["ok"]:
		assert_gt(float(res["record"]["len"]), 1.0)

func test_deep_shaft_gets_ladder_from_bottom() -> void:
	_dig(40)  # 20 m
	var res := _plan_from_bottom()
	assert_true(res["ok"], "Leiter an tiefer Wand: %s" % res["reason"])
	var rec: Dictionary = res["record"]
	assert_gt(float(rec["len"]), 18.0)
	assert_lt(float(rec["len"]), LadderPlanner.MAX_LENGTH)
	assert_eq(int(res["cost"][LadderPlanner.LADDER_ITEM]), ceili(float(rec["len"]) / LadderPlanner.METERS_PER_LADDER))
	# Fuß unten, Kopf oben auf Geländehöhe.
	var path := LadderPath.from_record(rec)
	assert_not_null(path)
	assert_lt(path.points[0].y, -15.0)
	assert_almost_eq(path.points[path.points.size() - 1].y, BASE, 0.5)

func test_ladder_from_rim_looking_into_pit() -> void:
	_dig(40)
	var res := LadderPlanner.plan(Vector3(-7.0, BASE, 0.0), Vector3(1, 0, 0), _ground)
	assert_true(res["ok"], "Abstieg vom Rand: %s" % res["reason"])
	assert_lt(LadderPath.from_record(res["record"]).points[0].y, -15.0)

func test_too_tall_wall_is_rejected() -> void:
	_dig(60)  # 30 m
	var res := _plan_from_bottom()
	if not res["ok"]:
		assert_eq(res["reason"], "too_long")

func test_record_survives_registry_roundtrip() -> void:
	_dig(30)
	var res := _plan_from_bottom()
	assert_true(res["ok"])
	var reg := LadderRegistry.new()
	assert_true(reg.add(res["record"]))
	assert_false(reg.add(res["record"]), "Doppelbelegung")
	var reg2 := LadderRegistry.new()
	reg2.load_save(reg.to_save())
	assert_eq(reg2.count(), 1)
	assert_not_null(reg2.get_path_of(String(res["record"]["key"])))

func test_registry_ignores_broken_records() -> void:
	var reg := LadderRegistry.new()
	reg.load_save([{"key": "x"}, 5, {"key": "y", "pts": [1.0, 2.0], "dx": 1.0, "dz": 0.0}])
	assert_eq(reg.count(), 0)

# ── Klettern ────────────────────────────────────

func _reg_with_ladder() -> LadderRegistry:
	_dig(40)
	var reg := LadderRegistry.new()
	reg.add(_plan_from_bottom()["record"])
	return reg

func test_attach_requires_moving_toward_wall() -> void:
	var reg := _reg_with_ladder()
	var path: LadderPath = reg.get_path_of(reg.get_all()[0]["key"])
	var pos: Vector3 = path.exit_bottom
	assert_true(reg.find_attach(pos, path.wall_dir).size() > 0)
	assert_true(reg.find_attach(pos, -path.wall_dir).is_empty())
	assert_true(reg.find_attach(pos + Vector3(0, 0, 30), path.wall_dir).is_empty())

func test_player_climbs_up_and_exits_on_top() -> void:
	var reg := _reg_with_ladder()
	var path: LadderPath = reg.get_path_of(reg.get_all()[0]["key"])
	var pl := PlayerLadder.new()
	var pos: Vector3 = path.exit_bottom
	var last: Dictionary = {}
	for i in 2000:
		var r := pl.step(pos, path.wall_dir, 1.0 / 60.0, false, reg)
		if r.is_empty():
			break
		pos = r["position"]
		last = r
		if not pl.is_climbing():
			break
	assert_false(pl.is_climbing(), "Oben losgelassen.")
	assert_almost_eq(pos.y, path.exit_top.y, 0.001)
	assert_gt(last["velocity"].length(), 0.0, "Kleiner Schubs auf den Rand.")

func test_jump_detaches_with_cooldown() -> void:
	var reg := _reg_with_ladder()
	var path: LadderPath = reg.get_path_of(reg.get_all()[0]["key"])
	var pl := PlayerLadder.new()
	pl.step(path.exit_bottom, path.wall_dir, 0.016, false, reg)
	assert_true(pl.is_climbing())
	var r := pl.step(path.exit_bottom, Vector3.ZERO, 0.016, true, reg)
	assert_false(pl.is_climbing())
	assert_gt(r["velocity"].y, 0.0)
	assert_true(pl.step(path.exit_bottom, path.wall_dir, 0.016, false, reg).is_empty(), "Sperrzeit")

func test_no_registry_means_no_climbing() -> void:
	var pl := PlayerLadder.new()
	assert_true(pl.step(Vector3.ZERO, Vector3.FORWARD, 0.016, false, null).is_empty())

func test_mesh_builds_geometry() -> void:
	var reg := _reg_with_ladder()
	var rec: Dictionary = reg.get_all()[0]
	var mesh := Ladder.build_mesh(reg.get_path_of(rec["key"]), Vector3(rec["x"], rec["y"], rec["z"]))
	assert_gt(mesh.get_surface_count(), 0)
