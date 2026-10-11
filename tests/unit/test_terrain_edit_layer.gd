# res://tests/unit/test_terrain_edit_layer.gd
extends GutTest

## Tests für TerrainEditLayer (Delta-Schicht für "Umgraben").

var _layer: TerrainEditLayer

func before_each() -> void:
	_layer = TerrainEditLayer.new()

# ── Grundverhalten ──────────────────────────────

func test_new_layer_is_empty_and_delta_zero() -> void:
	assert_true(_layer.is_empty())
	assert_eq(_layer.get_delta_at(13.7, -4.2), 0.0)

func test_add_delta_stores_value_on_lattice() -> void:
	assert_true(_layer.add_delta(Vector2i(3, -2), -0.5))
	assert_eq(_layer.get_delta_lattice(3, -2), -0.5)
	assert_eq(_layer.get_edit_count(), 1)

func test_delta_is_exact_on_lattice_point_world_position() -> void:
	_layer.add_delta(Vector2i(3, -2), -1.0)
	var w := TerrainEditLayer.lattice_to_world(Vector2i(3, -2))
	assert_almost_eq(_layer.get_delta_at(w.x, w.y), -1.0, 0.0001)

func test_delta_is_interpolated_between_points() -> void:
	_layer.set_delta(Vector2i(0, 0), -1.0)
	# Mitte zwischen (0,0) und (1,0) → halber Wert.
	assert_almost_eq(_layer.get_delta_at(TerrainEditLayer.SPACING * 0.5, 0.0), -0.5, 0.0001)

func test_delta_falls_back_to_zero_far_away() -> void:
	_layer.set_delta(Vector2i(0, 0), -1.0)
	assert_almost_eq(_layer.get_delta_at(TerrainEditLayer.SPACING * 5.0, 0.0), 0.0, 0.0001)

func test_delta_is_clamped_to_limits() -> void:
	_layer.add_delta(Vector2i(1, 1), -100.0)
	assert_eq(_layer.get_delta_lattice(1, 1), TerrainEditLayer.MAX_DELTA_DOWN)
	_layer.set_delta(Vector2i(2, 2), 100.0)
	assert_eq(_layer.get_delta_lattice(2, 2), TerrainEditLayer.MAX_DELTA_UP)

func test_adding_beyond_limit_reports_no_change() -> void:
	_layer.set_delta(Vector2i(1, 1), TerrainEditLayer.MAX_DELTA_DOWN)
	assert_false(_layer.add_delta(Vector2i(1, 1), -1.0), "Am Limit ändert sich nichts mehr.")

func test_tiny_delta_is_dropped() -> void:
	assert_false(_layer.add_delta(Vector2i(0, 0), 0.001))
	assert_true(_layer.is_empty())

func test_delta_returning_to_zero_removes_entry() -> void:
	_layer.add_delta(Vector2i(0, 0), -0.5)
	assert_true(_layer.add_delta(Vector2i(0, 0), 0.5))
	assert_true(_layer.is_empty(), "Rückkehr auf 0 darf keinen toten Eintrag hinterlassen.")

# ── Pinsel ──────────────────────────────────────

func test_brush_digs_center_most() -> void:
	var changed := _layer.apply_brush(0.0, 0.0, 3.5, -0.5)
	assert_gt(changed.size(), 1)
	var center := _layer.get_delta_lattice(0, 0)
	var neighbor := _layer.get_delta_lattice(1, 0)
	assert_lt(center, 0.0)
	assert_lt(neighbor, 0.0)
	assert_lt(center, neighbor, "Zentrum wird tiefer als Nachbarn (weicher Verlauf).")

func test_brush_positive_amount_raises() -> void:
	_layer.apply_brush(0.0, 0.0, 3.5, 0.5)
	assert_gt(_layer.get_delta_lattice(0, 0), 0.0)

func test_brush_dig_then_fill_cancels_out() -> void:
	_layer.apply_brush(0.0, 0.0, 3.5, -0.5)
	_layer.apply_brush(0.0, 0.0, 3.5, 0.5)
	assert_true(_layer.is_empty())

func test_brush_repeated_digs_stop_at_limit() -> void:
	for i in 40:
		_layer.apply_brush(0.0, 0.0, 3.5, -0.5)
	assert_eq(_layer.get_delta_lattice(0, 0), TerrainEditLayer.MAX_DELTA_DOWN)
	var again := _layer.apply_brush(0.0, 0.0, 3.5, -0.5)
	assert_false(again.has(Vector2i(0, 0)), "Punkt am Limit wird nicht mehr als verändert gemeldet.")

func test_brush_with_zero_radius_changes_nothing() -> void:
	assert_eq(_layer.apply_brush(0.0, 0.0, 0.0, -0.5).size(), 0)
	assert_true(_layer.is_empty())

func test_falloff_is_one_at_center_and_zero_at_edge() -> void:
	assert_almost_eq(TerrainEditLayer.falloff(0.0, 3.0), 1.0, 0.0001)
	assert_eq(TerrainEditLayer.falloff(3.0, 3.0), 0.0)
	assert_eq(TerrainEditLayer.falloff(5.0, 3.0), 0.0)

func test_lattice_points_in_radius_contains_center_and_respects_radius() -> void:
	var pts := TerrainEditLayer.lattice_points_in_radius(0.0, 0.0, 3.0)
	assert_true(pts.has(Vector2i(0, 0)))
	assert_true(pts.has(Vector2i(1, 0)))   # 2 m entfernt
	assert_false(pts.has(Vector2i(2, 0)))  # 4 m entfernt

# ── Chunk-Zuordnung ─────────────────────────────

func test_point_inside_chunk_belongs_only_to_that_chunk() -> void:
	# Weltposition (10, 10) → Chunk (0,0) (Zentrum 0, Halbgröße 32).
	var pts: Array[Vector2i] = [TerrainEditLayer.world_to_lattice(10.0, 10.0)]
	var chunks := TerrainEditLayer.chunks_for_points(pts, 64.0)
	assert_eq(chunks.size(), 1)
	assert_true(chunks.has(Vector2i(0, 0)))

func test_point_on_chunk_border_belongs_to_two_chunks() -> void:
	# x = 32 ist die gemeinsame Grenze der Chunks (0,0) und (1,0).
	var pts: Array[Vector2i] = [TerrainEditLayer.world_to_lattice(32.0, 0.0)]
	var chunks := TerrainEditLayer.chunks_for_points(pts, 64.0)
	assert_eq(chunks.size(), 2)
	assert_true(chunks.has(Vector2i(0, 0)))
	assert_true(chunks.has(Vector2i(1, 0)))

func test_point_on_chunk_corner_belongs_to_four_chunks() -> void:
	var pts: Array[Vector2i] = [TerrainEditLayer.world_to_lattice(32.0, 32.0)]
	assert_eq(TerrainEditLayer.chunks_for_points(pts, 64.0).size(), 4)

func test_negative_coordinates_map_to_correct_chunk() -> void:
	var pts: Array[Vector2i] = [TerrainEditLayer.world_to_lattice(-70.0, 5.0)]
	var chunks := TerrainEditLayer.chunks_for_points(pts, 64.0)
	assert_true(chunks.has(Vector2i(-1, 0)))

# ── Einebnen ────────────────────────────────────

func test_plan_level_computes_delta_from_current_ground() -> void:
	var pts: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var ground := func(_x: float, _z: float) -> float: return 2.0
	var plan := _layer.plan_level(pts, 3.0, ground)
	assert_true(plan["ok"])
	assert_eq((plan["changes"] as Dictionary)[Vector2i(0, 0)], 1.0)

func test_plan_level_does_not_mutate_layer() -> void:
	var pts: Array[Vector2i] = [Vector2i(0, 0)]
	_layer.plan_level(pts, 3.0, func(_x: float, _z: float) -> float: return 2.0)
	assert_true(_layer.is_empty(), "Planen darf nichts verändern.")

func test_plan_level_rejects_too_steep() -> void:
	var pts: Array[Vector2i] = [Vector2i(0, 0)]
	var plan := _layer.plan_level(pts, 20.0, func(_x: float, _z: float) -> float: return 0.0)
	assert_false(plan["ok"])
	assert_eq(plan["reason"], "too_steep")

func test_plan_level_rejects_missing_ground() -> void:
	var pts: Array[Vector2i] = [Vector2i(0, 0)]
	var plan := _layer.plan_level(pts, 1.0, func(_x: float, _z: float) -> float: return NAN)
	assert_false(plan["ok"])
	assert_eq(plan["reason"], "no_ground")

func test_plan_level_builds_on_existing_delta() -> void:
	_layer.set_delta(Vector2i(0, 0), -1.0)
	var pts: Array[Vector2i] = [Vector2i(0, 0)]
	# Gelände liegt (inkl. Delta) bei 1.0, Ziel 2.0 → Delta muss von -1.0 auf 0.0 steigen.
	var plan := _layer.plan_level(pts, 2.0, func(_x: float, _z: float) -> float: return 1.0)
	assert_true(plan["ok"])
	assert_eq((plan["changes"] as Dictionary)[Vector2i(0, 0)], 0.0)

func test_apply_changes_writes_planned_deltas() -> void:
	var pts: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1)]
	var plan := _layer.plan_level(pts, 1.5, func(_x: float, _z: float) -> float: return 1.0)
	var changed := _layer.apply_changes(plan["changes"])
	assert_eq(changed.size(), 2)
	assert_eq(_layer.get_delta_lattice(1, 1), 0.5)

# ── Persistenz ──────────────────────────────────

func test_save_load_roundtrip() -> void:
	_layer.apply_brush(4.0, -6.0, 3.5, -0.5)
	_layer.set_delta(Vector2i(-7, 9), 1.25)
	var restored := TerrainEditLayer.new()
	restored.load_save(_layer.to_save())
	assert_eq(restored.get_edit_count(), _layer.get_edit_count())
	assert_eq(restored.get_delta_lattice(-7, 9), 1.25)

func test_save_survives_var_to_str_roundtrip() -> void:
	_layer.set_delta(Vector2i(2, 3), -0.75)
	var text := var_to_str(_layer.to_save())
	var restored := TerrainEditLayer.new()
	restored.load_save(str_to_var(text))
	assert_eq(restored.get_delta_lattice(2, 3), -0.75)

func test_load_accepts_plain_array() -> void:
	_layer.load_save([1, 2, -0.5])
	assert_eq(_layer.get_delta_lattice(1, 2), -0.5)

func test_load_ignores_garbage() -> void:
	_layer.set_delta(Vector2i(0, 0), -1.0)
	_layer.load_save("kaputt")
	assert_true(_layer.is_empty(), "Ungültige Eingabe → leere Schicht, kein Crash.")
	_layer.load_save([1, 2])          # unvollständiges Tripel
	assert_true(_layer.is_empty())
	_layer.load_save([1, "x", 3, 4, 5, -1.0])
	assert_eq(_layer.get_edit_count(), 1, "Nur das gültige Tripel wird übernommen.")

func test_load_clamps_out_of_range_values() -> void:
	_layer.load_save([0, 0, -999.0])
	assert_eq(_layer.get_delta_lattice(0, 0), TerrainEditLayer.MAX_DELTA_DOWN)

# ── Flachbödiger Pinsel (Schächte) ──────────────

func test_falloff_core_is_full_weight_then_fades() -> void:
	assert_eq(TerrainEditLayer.falloff(2.0, 5.0, 2.9), 1.0)
	assert_eq(TerrainEditLayer.falloff(5.0, 5.0, 2.9), 0.0)
	var mid: float = TerrainEditLayer.falloff(4.0, 5.0, 2.9)
	assert_gt(mid, 0.0)
	assert_lt(mid, 1.0)

func test_falloff_without_core_is_unchanged() -> void:
	assert_eq(TerrainEditLayer.falloff(0.0, 3.5), 1.0)
	assert_almost_eq(TerrainEditLayer.falloff(1.75, 3.5), 0.5, 0.0001)

func test_brush_with_core_digs_3x3_evenly() -> void:
	_layer.apply_brush(0.0, 0.0, 5.0, -0.5, 2.9)
	for ix in [-1, 0, 1]:
		for iz in [-1, 0, 1]:
			assert_eq(_layer.get_delta_lattice(ix, iz), -0.5)
	assert_gt(_layer.get_delta_lattice(2, 0), -0.5, "Wandpunkt bekommt weniger.")
