# res://tests/unit/test_build_aim.gd
extends GutTest

## Tests für BuildAim (Blick-Zielen und Richtungstasten im Baumodus) — engine-frei.

func _flat(h: float) -> Callable:
	return func(_x: float, _z: float) -> float: return h

func test_ray_hits_flat_ground_at_expected_point() -> void:
	# Von (0,10,0) unter 45° nach vorn/unten (-Z) → trifft y=0 bei z=-10.
	var hit: Variant = BuildAim.ground_hit(Vector3(0, 10, 0), Vector3(0, -1, -1), _flat(0.0), 0.0, 40.0)
	assert_true(hit is Vector3)
	assert_almost_eq((hit as Vector3).z, -10.0, 0.05)
	assert_almost_eq((hit as Vector3).y, 0.0, 0.05)

func test_ray_pointing_up_never_hits() -> void:
	assert_null(BuildAim.ground_hit(Vector3(0, 2, 0), Vector3(0, 1, -1), _flat(0.0), 0.0, 40.0))

func test_ray_out_of_range_returns_null() -> void:
	assert_null(BuildAim.ground_hit(Vector3(0, 10, 0), Vector3(0, -1, -1), _flat(0.0), 0.0, 5.0))

func test_nan_ground_is_skipped() -> void:
	assert_null(BuildAim.ground_hit(Vector3(0, 10, 0), Vector3(0, -1, -1), _flat(NAN), 0.0, 40.0))

func test_invalid_inputs_return_null() -> void:
	assert_null(BuildAim.ground_hit(Vector3.ZERO, Vector3.ZERO, _flat(0.0), 0.0, 10.0))
	assert_null(BuildAim.ground_hit(Vector3(0, 5, 0), Vector3.DOWN, Callable(), 0.0, 10.0))

func test_clamp_to_reach_limits_horizontal_distance_only() -> void:
	var p := BuildAim.clamp_to_reach(Vector3(30, 7, 0), Vector3(0, 1, 0), 9.0)
	assert_almost_eq(p.x, 9.0, 0.001)
	assert_eq(p.y, 7.0)

func test_clamp_to_reach_keeps_near_targets() -> void:
	assert_eq(BuildAim.clamp_to_reach(Vector3(3, 0, 4), Vector3.ZERO, 9.0), Vector3(3, 0, 4))

func test_nudge_forward_is_away_from_camera() -> void:
	# Kamera schaut nach -Z → "vor" ist -Z, "rechts" ist +X.
	var view := Vector3(0.1, -0.5, -1.0)
	assert_eq(BuildAim.nudge_vector(view, BuildAim.Dir.FORWARD), Vector3(0, 0, -1))
	assert_eq(BuildAim.nudge_vector(view, BuildAim.Dir.BACK), Vector3(0, 0, 1))
	assert_eq(BuildAim.nudge_vector(view, BuildAim.Dir.RIGHT), Vector3(1, 0, 0))
	assert_eq(BuildAim.nudge_vector(view, BuildAim.Dir.LEFT), Vector3(-1, 0, 0))

func test_nudge_follows_camera_yaw_snapped_to_axis() -> void:
	# Kamera schaut (überwiegend) nach +X → "vor" = +X, "rechts" = +Z.
	var view := Vector3(1.0, -0.3, 0.4)
	assert_eq(BuildAim.nudge_vector(view, BuildAim.Dir.FORWARD), Vector3(1, 0, 0))
	assert_eq(BuildAim.nudge_vector(view, BuildAim.Dir.RIGHT), Vector3(0, 0, 1))

func test_nudge_with_straight_down_view_falls_back_to_north() -> void:
	assert_eq(BuildAim.nudge_vector(Vector3.DOWN, BuildAim.Dir.FORWARD), Vector3(0, 0, -1))
