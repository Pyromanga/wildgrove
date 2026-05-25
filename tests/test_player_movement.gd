extends GutTest
## test_player_movement.gd
## Testet Richtungsberechnungen isoliert ohne echten Spieler

# XP-Kurve — gleiche Formel wie PlayerStats.gd
func _xp_for_level(level: int) -> int:
	var total: int = 0
	for i in range(1, level):
		total += int(i + 300.0 * pow(2.0, float(i) / 7.0))
	return total / 4


# Richtung bei cam_relative=false (Weltachsen)
func _dir_world(input_vec: Vector2) -> Vector3:
	return Vector3(input_vec.x, 0, -input_vec.y).normalized()


# Richtung bei cam_relative=true mit gegebener Kamera-Rotation
func _dir_cam(input_vec: Vector2, cam_yaw: float) -> Vector3:
	var basis: Basis   = Basis(Vector3.UP, cam_yaw)
	var fwd: Vector3   = Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	var right: Vector3 = Vector3( basis.x.x, 0,  basis.x.z).normalized()
	return (fwd * input_vec.y + right * input_vec.x).normalized()


# ── Weltachsen-Modus ───────────────────────────────────────────────────────
func test_world_up_is_minus_z() -> void:
	var dir: Vector3 = _dir_world(Vector2(0, 1))
	assert_almost_eq(dir.z, -1.0, 0.01, "Hoch = -Z")
	assert_almost_eq(dir.x,  0.0, 0.01, "Hoch = kein X")


func test_world_right_is_plus_x() -> void:
	var dir: Vector3 = _dir_world(Vector2(1, 0))
	assert_almost_eq(dir.x,  1.0, 0.01, "Rechts = +X")
	assert_almost_eq(dir.z,  0.0, 0.01, "Rechts = kein Z")


func test_world_diagonal_is_normalized() -> void:
	var dir: Vector3 = _dir_world(Vector2(1, 1).normalized())
	assert_almost_eq(dir.length(), 1.0, 0.01, "Diagonale normalisiert")
	assert_gt(dir.x, 0.0, "Diagonal hat positives X")
	assert_lt(dir.z, 0.0, "Diagonal hat negatives Z")


# ── Kamera-relativer Modus ─────────────────────────────────────────────────
func test_cam_relative_yaw0_up_is_forward() -> void:
	var dir: Vector3 = _dir_cam(Vector2(0, 1), 0.0)
	assert_almost_eq(dir.length(), 1.0, 0.01, "normalisiert")
	assert_lt(dir.z, 0.0, "yaw=0, hoch = -Z Richtung")


func test_cam_relative_yaw90_up_is_right() -> void:
	var dir: Vector3 = _dir_cam(Vector2(0, 1), deg_to_rad(90))
	assert_almost_eq(dir.length(), 1.0, 0.01, "normalisiert")
	assert_gt(dir.x, 0.5, "yaw=90°: hoch = +X Richtung")


func test_zero_input_below_threshold() -> void:
	assert_true(Vector2.ZERO.length() <= 0.05, "Zero-Input unter Threshold")


# ── XP-Kurve ──────────────────────────────────────────────────────────────
func test_level1_needs_zero_xp() -> void:
	assert_eq(_xp_for_level(1), 0, "Level 1 = 0 XP")


func test_level2_needs_positive_xp() -> void:
	assert_gt(_xp_for_level(2), 0, "Level 2 > 0 XP")


func test_higher_level_needs_more_xp() -> void:
	assert_gt(_xp_for_level(10), _xp_for_level(5), "Level 10 > Level 5 XP")


func test_xp_curve_is_monotonic() -> void:
	var prev: int = 0
	for lvl in range(1, 20):
		var curr: int = _xp_for_level(lvl)
		assert_gte(curr, prev, "XP-Kurve steigt monoton bei Level %d" % lvl)
		prev = curr
