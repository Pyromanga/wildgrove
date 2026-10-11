# res://tests/unit/test_character_gaze.gd
extends GutTest

## Tests für CharacterGaze — statische Rechenfunktionen + Bindung an echte Körperteile.
## Die Animation selbst (_process) wird per direktem Aufruf getrieben, damit die Tests
## unabhängig von Renderer/Headless-Modus sind.

func _make_bound_gaze() -> Dictionary:
	var parts := CharacterPartBuilder.build(CharacterLook.default_look())
	var holder: Node3D = add_child_autofree(Node3D.new())
	holder.add_child(parts["root"] as Node3D)
	var gaze := CharacterGaze.new()
	gaze.auto_focus_enabled = false
	gaze.idle_enabled = false
	gaze.breathing_enabled = false
	holder.add_child(gaze)
	gaze.bind(parts)
	return {"gaze": gaze, "parts": parts, "holder": holder}

func test_angles_to_forward_is_zero() -> void:
	var a := CharacterGaze.angles_to(Vector3(0, 0, 1))
	assert_almost_eq(a.x, 0.0, 0.0001)
	assert_almost_eq(a.y, 0.0, 0.0001)

func test_angles_to_positive_x_is_positive_yaw() -> void:
	assert_true(CharacterGaze.angles_to(Vector3(1, 0, 1)).x > 0.0)
	assert_true(CharacterGaze.angles_to(Vector3(-1, 0, 1)).x < 0.0)

func test_angles_to_up_is_positive_pitch() -> void:
	assert_true(CharacterGaze.angles_to(Vector3(0, 1, 1)).y > 0.0)
	assert_true(CharacterGaze.angles_to(Vector3(0, -1, 1)).y < 0.0)

func test_angles_to_zero_vector_is_safe() -> void:
	assert_eq(CharacterGaze.angles_to(Vector3.ZERO), Vector2.ZERO)

func test_split_gaze_respects_limits() -> void:
	var s := CharacterGaze.split_gaze(Vector2(3.0, 3.0), Vector2(0.6, 0.45))
	var h: Vector2 = s["head"]
	var e: Vector2 = s["eye"]
	assert_true(absf(h.x) <= CharacterGaze.HEAD_YAW_MAX + 0.0001)
	assert_true(h.y <= CharacterGaze.HEAD_PITCH_UP_MAX + 0.0001)
	assert_true(absf(e.x) <= CharacterGaze.EYE_YAW_MAX + 0.0001)
	assert_true(absf(e.y) <= CharacterGaze.EYE_PITCH_MAX + 0.0001)

func test_split_gaze_small_angle_is_fully_covered() -> void:
	var total := Vector2(0.2, 0.1)
	var s := CharacterGaze.split_gaze(total, Vector2(0.6, 0.45))
	var sum: Vector2 = (s["head"] as Vector2) + (s["eye"] as Vector2)
	assert_almost_eq(sum.x, total.x, 0.0001)
	assert_almost_eq(sum.y, total.y, 0.0001)

func test_eye_offset_never_exceeds_max() -> void:
	for yaw in [-2.0, -0.3, 0.0, 0.5, 2.0]:
		for pitch in [-2.0, 0.0, 2.0]:
			var o := CharacterGaze.eye_offset(Vector2(yaw, pitch), 0.01)
			assert_true(o.length() <= 0.01 + 0.00001, "Iris verlässt den Augapfel (%s, %s)." % [yaw, pitch])

func test_lid_coverage_blink_closes_and_look_down_lowers_lid() -> void:
	assert_almost_eq(CharacterGaze.lid_coverage(0.0, 1.0, 0.0), 1.0, 0.0001)
	assert_almost_eq(CharacterGaze.lid_coverage(0.0, 0.0, 0.0), 0.0, 0.0001)
	assert_true(CharacterGaze.lid_coverage(0.0, 0.0, -0.3) > 0.0)
	assert_almost_eq(CharacterGaze.lid_coverage(0.38, 0.0, 0.0), 0.38, 0.0001)

func test_blink_curve_goes_0_to_1_to_0() -> void:
	assert_almost_eq(CharacterGaze.blink_curve(0.0), 0.0, 0.0001)
	assert_almost_eq(CharacterGaze.blink_curve(0.4), 1.0, 0.0001)
	assert_almost_eq(CharacterGaze.blink_curve(1.0), 0.0, 0.0001)

func test_vergence_is_larger_for_closer_targets_and_mirrored() -> void:
	assert_true(absf(CharacterGaze.vergence(0.5, 1.0)) > absf(CharacterGaze.vergence(5.0, 1.0)))
	assert_almost_eq(CharacterGaze.vergence(2.0, 1.0), -CharacterGaze.vergence(2.0, -1.0), 0.0001)

func test_pick_idle_target_is_deterministic_for_same_seed_and_bounded() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	for i in 20:
		var ta := CharacterGaze.pick_idle_target(a)
		assert_eq(ta, CharacterGaze.pick_idle_target(b))
		assert_true(absf(ta.x) <= 0.55 + 0.0001)
		assert_true(ta.y >= -0.34 and ta.y <= 0.26)

func test_bind_finds_both_eyes_with_gaze_and_lid_children() -> void:
	var ctx := _make_bound_gaze()
	var parts: Dictionary = ctx["parts"]
	for key in ["eye_r", "eye_l"]:
		var eye := parts[key] as Node3D
		assert_not_null(eye, "%s fehlt im build()-Ergebnis." % key)
		assert_not_null(eye.get_node_or_null("Gaze"))
		assert_true(eye.has_meta("gaze_max"))
	assert_true((ctx["gaze"] as CharacterGaze).is_bound())

func test_focus_point_to_the_side_turns_head_and_shifts_iris() -> void:
	var ctx := _make_bound_gaze()
	var gaze: CharacterGaze = ctx["gaze"]
	var parts: Dictionary = ctx["parts"]
	var holder: Node3D = ctx["holder"]
	# Ziel 3 m vor und 2 m seitlich (+X) der Figur, in Kopfhöhe.
	gaze.set_focus_point(holder.global_position + Vector3(2.0, 1.65, 3.0))
	for i in 60:
		gaze._process(0.05)
	assert_true(gaze.get_head_angles().x > 0.1, "Kopf soll sich Richtung +X drehen.")
	var gaze_node := (parts["eye_r"] as Node3D).get_node("Gaze") as Node3D
	assert_true(gaze_node.position.length() <= float((parts["eye_r"] as Node3D).get_meta("gaze_max")) + 0.0001)

func test_clear_focus_without_idle_returns_head_to_center() -> void:
	var ctx := _make_bound_gaze()
	var gaze: CharacterGaze = ctx["gaze"]
	var holder: Node3D = ctx["holder"]
	gaze.set_focus_point(holder.global_position + Vector3(3.0, 1.65, 1.0))
	for i in 40:
		gaze._process(0.05)
	gaze.clear_focus()
	for i in 80:
		gaze._process(0.05)
	assert_almost_eq(gaze.get_head_angles().x, 0.0, 0.05)

func test_blink_now_closes_the_lid_briefly() -> void:
	var ctx := _make_bound_gaze()
	var gaze: CharacterGaze = ctx["gaze"]
	gaze.blink_now()
	var peak := 0.0
	for i in 12:
		gaze._process(0.02)
		peak = maxf(peak, gaze.get_blink_value())
	assert_true(peak > 0.9, "Blinzeln soll das Lid (fast) vollständig schließen.")
	for i in 20:
		gaze._process(0.02)
	assert_almost_eq(gaze.get_blink_value(), 0.0, 0.0001)

func test_idle_moves_eyes_without_a_target() -> void:
	var ctx := _make_bound_gaze()
	var gaze: CharacterGaze = ctx["gaze"]
	gaze.idle_enabled = true
	var moved := false
	for i in 400:
		gaze._process(0.05)
		if gaze.get_eye_angles().length() > 0.02 or gaze.get_head_angles().length() > 0.02:
			moved = true
	assert_true(moved, "Im Idle soll der Blick wandern.")

func test_disabled_gaze_changes_nothing() -> void:
	var ctx := _make_bound_gaze()
	var gaze: CharacterGaze = ctx["gaze"]
	var holder: Node3D = ctx["holder"]
	gaze.enabled = false
	gaze.set_focus_point(holder.global_position + Vector3(3.0, 1.65, 1.0))
	gaze._process(0.1)
	assert_eq(gaze.get_head_angles(), Vector2.ZERO)

func test_rebinding_after_rebuild_does_not_touch_freed_nodes() -> void:
	var ctx := _make_bound_gaze()
	var gaze: CharacterGaze = ctx["gaze"]
	var holder: Node3D = ctx["holder"]
	(ctx["parts"]["root"] as Node3D).free()
	gaze._process(0.05)  # darf nicht crashen: Kopf ist ungültig → is_bound() false
	assert_false(gaze.is_bound())
	var parts2 := CharacterPartBuilder.build(CharacterLook.sanitize({"hat": "cap"}))
	holder.add_child(parts2["root"] as Node3D)
	gaze.bind(parts2)
	assert_true(gaze.is_bound())

func test_gaze_point_of_prefers_custom_hook() -> void:
	var n := Node3D.new()
	n.set_script(load("res://tests/mocks/MockGazeTarget.gd"))
	add_child_autofree(n)
	assert_eq(CharacterGaze.gaze_point_of(n), Vector3(1, 2, 3))

func test_player_visuals_exposes_gaze_and_rebinds_on_look_change() -> void:
	var v: PlayerVisuals = add_child_autofree(PlayerVisuals.new())
	assert_not_null(v.gaze)
	assert_true(v.gaze.is_bound())
	var head_before := v.gaze.head
	v.apply_look(CharacterLook.sanitize({"hair_style": "long", "hat": "beanie"}))
	assert_true(v.gaze.is_bound())
	assert_ne(v.gaze.head, head_before, "Nach Neuaufbau muss der Blick am NEUEN Kopf hängen.")
