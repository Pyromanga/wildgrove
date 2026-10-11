# res://tests/unit/test_level_gauge.gd
extends GutTest

## Tests für LevelGauge (Wasserwagen-Logik) — reine Funktionen, kein SceneTree.

var _slope_x: float = 0.0

func _flat(_x: float, _z: float) -> float:
	return 5.0

func _slope(x: float, _z: float) -> float:
	return 5.0 + _slope_x * x

# ── Stufen & Farben ─────────────────────────────

func test_bands() -> void:
	assert_eq(LevelGauge.band_for(0.0), 0)
	assert_eq(LevelGauge.band_for(LevelGauge.TOL_LEVEL), 0, "Grenzwert zählt noch als eben.")
	assert_eq(LevelGauge.band_for(0.2), 1)
	assert_eq(LevelGauge.band_for(-0.2), -1)
	assert_eq(LevelGauge.band_for(0.5), 2)
	assert_eq(LevelGauge.band_for(-0.5), -2)
	assert_eq(LevelGauge.band_for(3.0), 3)
	assert_eq(LevelGauge.band_for(-3.0), -3)

func test_level_is_green_and_directions_differ() -> void:
	assert_eq(LevelGauge.color_for(0.05), LevelGauge.COL_LEVEL)
	var high := LevelGauge.color_for(0.5)
	var low := LevelGauge.color_for(-0.5)
	assert_gt(high.r, high.b, "Zu hoch = warm.")
	assert_gt(low.b, low.r, "Zu tief = kühl.")

func test_colors_are_continuous_between_medium_and_strong() -> void:
	var a := LevelGauge.color_for(LevelGauge.TOL_MEDIUM)
	var b := LevelGauge.color_for(LevelGauge.TOL_MEDIUM + 0.001)
	assert_lt(absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b), 0.05)

# ── Bezugshöhe ──────────────────────────────────

func test_reference_height_is_corner_mean() -> void:
	_slope_x = 1.0
	# Zelle (0,0): Ecken bei x = 0 und x = 2 → Mittel 5 + 1 = 6.
	assert_almost_eq(LevelGauge.reference_height(_slope, Vector2(1.0, 1.0)), 6.0, 0.0001)

# ── Netz ────────────────────────────────────────

func test_grid_has_expected_size_and_topology() -> void:
	var grid := LevelGauge.build_grid(_flat, Vector2.ZERO, 5.0, 3, 4.0)
	var side := 3 * 2 + 2
	assert_eq((grid["vertices"] as PackedVector3Array).size(), side * side)
	assert_eq((grid["colors"] as PackedColorArray).size(), side * side)
	assert_eq((grid["indices"] as PackedInt32Array).size(), (side - 1) * (side - 1) * 6)

func test_grid_vertices_follow_terrain_with_lift() -> void:
	var grid := LevelGauge.build_grid(_flat, Vector2.ZERO, 5.0, 2, 4.0)
	for v in (grid["vertices"] as PackedVector3Array):
		assert_almost_eq(v.y, 5.0 + LevelGauge.LIFT, 0.0001)

func test_indices_stay_in_range() -> void:
	var grid := LevelGauge.build_grid(_flat, Vector2(13.0, -7.0), 5.0, 4, 4.0)
	var n := (grid["vertices"] as PackedVector3Array).size()
	for i in (grid["indices"] as PackedInt32Array):
		assert_true(i >= 0 and i < n)

func test_flat_ground_is_fully_level() -> void:
	var stats: Dictionary = LevelGauge.build_grid(_flat, Vector2.ZERO, 5.0, 3, 4.0)["stats"]
	assert_gt(int(stats["count"]), 0)
	assert_eq(float(stats["level_share"]), 1.0)
	assert_eq(float(stats["max_high"]), 0.0)
	assert_eq(float(stats["max_low"]), 0.0)

func test_slope_reports_high_and_low_and_partial_share() -> void:
	_slope_x = 0.5   # 1 m Höhenunterschied je 2 m Gitter
	var stats: Dictionary = LevelGauge.build_grid(_slope, Vector2.ZERO, 5.0, 3, 4.0)["stats"]
	assert_gt(float(stats["max_high"]), 0.5)
	assert_lt(float(stats["max_low"]), -0.5)
	assert_gt(float(stats["level_share"]), 0.0)
	assert_lt(float(stats["level_share"]), 1.0)

func test_stats_only_count_points_inside_radius() -> void:
	_slope_x = 0.5
	var near: Dictionary = LevelGauge.build_grid(_slope, Vector2.ZERO, 5.0, 4, 2.5)["stats"]
	var far: Dictionary = LevelGauge.build_grid(_slope, Vector2.ZERO, 5.0, 4, 8.0)["stats"]
	assert_lt(int(near["count"]), int(far["count"]))
	assert_lt(float(near["max_high"]), float(far["max_high"]))

func test_edge_fades_out() -> void:
	var grid := LevelGauge.build_grid(_flat, Vector2.ZERO, 5.0, 4, 4.0)
	var colors: PackedColorArray = grid["colors"]
	var side := 4 * 2 + 2
	assert_almost_eq(colors[0].a, 0.0, 0.0001, "Ecke ist ausgeblendet.")
	assert_almost_eq(colors[(side / 2) * side + side / 2].a, LevelGauge.ALPHA, 0.0001, "Mitte voll sichtbar.")

# ── Text ────────────────────────────────────────

func test_summary_text() -> void:
	assert_eq(LevelGauge.summary_text({"count": 0}), "Wasserwagen: kein Gelände in der Nähe.")
	assert_eq(LevelGauge.summary_text({"count": 9, "max_high": 0.0, "max_low": 0.0, "level_share": 1.0}),
		"Wasserwagen: eben (100 %)")
	assert_eq(LevelGauge.summary_text({"count": 9, "max_high": 0.42, "max_low": -0.18, "level_share": 0.63}),
		"Wasserwagen: höher +0,42 m · tiefer −0,18 m · 63 % eben")
