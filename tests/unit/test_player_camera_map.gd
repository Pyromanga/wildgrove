# res://tests/unit/test_player_camera_map.gd
extends GutTest

## Tests für Vogelperspektive + Karten-Zoom der PlayerCamera (reine Rechenfunktionen + Verhalten).

var _cam: PlayerCamera
var _inp: TouchInput

func before_each() -> void:
	_cam = add_child_autofree(PlayerCamera.new())
	_inp = TouchInput.new()
	autofree(_inp)

# ── Reine Rechenfunktionen ────────────────────────────────────────

func test_zoom_step_is_linear_in_the_near_range() -> void:
	assert_almost_eq(PlayerCamera.zoom_step(5.0, 1.0), 6.0, 0.0001)
	assert_almost_eq(PlayerCamera.zoom_step(5.0, -1.0), 4.0, 0.0001)
	assert_almost_eq(PlayerCamera.zoom_step(PlayerCamera.ZOOM_STEP_LINEAR_UNTIL, 1.0), PlayerCamera.ZOOM_STEP_LINEAR_UNTIL + 1.0, 0.0001)

func test_zoom_step_grows_proportionally_far_out() -> void:
	var near_step := PlayerCamera.zoom_step(30.0, 1.0) - 30.0
	var far_step := PlayerCamera.zoom_step(200.0, 1.0) - 200.0
	assert_true(far_step > near_step * 3.0, "Weiter draußen muss ein Schritt deutlich größer sein.")
	assert_true(PlayerCamera.zoom_step(200.0, -1.0) < 200.0)

func test_birds_eye_weight_boundaries_and_monotonic() -> void:
	assert_almost_eq(PlayerCamera.birds_eye_weight(PlayerCamera.MAX_ZOOM), 0.0, 0.0001)
	assert_almost_eq(PlayerCamera.birds_eye_weight(PlayerCamera.BIRDS_EYE_FULL), 1.0, 0.0001)
	var prev := -1.0
	for z in range(0, 60, 3):
		var w := PlayerCamera.birds_eye_weight(float(z))
		assert_true(w >= prev, "birds_eye_weight muss monoton steigen.")
		prev = w

func test_normal_third_person_range_is_unchanged() -> void:
	for z in [0.4, 1.2, 3.0, 8.0, 15.0]:
		assert_almost_eq(PlayerCamera.birds_eye_weight(z), 0.0, 0.0001, "Zoom %s darf nicht gekippt sein." % z)
		assert_almost_eq(PlayerCamera.map_blend(z), 0.0, 0.0001)
		assert_almost_eq(PlayerCamera.camera_height(z), z, 0.0001)

func test_map_blend_boundaries() -> void:
	assert_almost_eq(PlayerCamera.map_blend(PlayerCamera.MAP_ZOOM_START), 0.0, 0.0001)
	assert_almost_eq(PlayerCamera.map_blend(PlayerCamera.MAP_ZOOM_FULL), 1.0, 0.0001)
	assert_almost_eq(PlayerCamera.map_blend(PlayerCamera.MAX_ZOOM_MAP), 1.0, 0.0001)

func test_camera_height_is_capped() -> void:
	assert_almost_eq(PlayerCamera.camera_height(300.0), PlayerCamera.MAX_CAMERA_HEIGHT, 0.0001)
	assert_almost_eq(PlayerCamera.camera_height(50.0), 50.0, 0.0001)

func test_view_extent_matches_real_camera_until_map_is_full_then_keeps_growing() -> void:
	var t := tan(deg_to_rad(75.0) * 0.5)
	# Bis MAP_ZOOM_FULL: genau das, was die echte Kamera aus dieser Höhe sieht → nahtloser Übergang.
	assert_almost_eq(PlayerCamera.view_half_extent_m(40.0, 75.0), 40.0 * t, 0.001)
	assert_almost_eq(PlayerCamera.view_half_extent_m(PlayerCamera.MAP_ZOOM_FULL, 75.0), PlayerCamera.MAP_ZOOM_FULL * t, 0.001)
	# Darüber wächst die Kartenfläche weiter (Kamera bleibt oben).
	var e1 := PlayerCamera.view_half_extent_m(100.0, 75.0)
	var e2 := PlayerCamera.view_half_extent_m(300.0, 75.0)
	assert_true(e1 > PlayerCamera.view_half_extent_m(PlayerCamera.MAP_ZOOM_FULL, 75.0))
	assert_true(e2 > e1)
	assert_true(e2 > 500.0, "Ganz herausgezoomt soll die Karte mehrere hundert Meter zeigen.")

# ── Verhalten der Instanz ─────────────────────────────────────────

func test_default_state_has_no_map() -> void:
	assert_almost_eq(_cam.get_map_blend(), 0.0, 0.0001)
	assert_false(_cam.is_map_visible())

func test_far_zoom_raises_camera_tilts_down_and_shows_map() -> void:
	watch_signals(_cam)
	_cam.set_zoom_immediate(150.0)
	for i in 80:
		_cam.handle_input(_inp, 0.1)
	assert_almost_eq(_cam.spring_length, PlayerCamera.MAX_CAMERA_HEIGHT, 0.01)
	assert_eq(_cam.collision_mask, 0, "Oben darf nichts die Kamera abschneiden.")
	assert_almost_eq(_cam.rotation.x, deg_to_rad(PlayerCamera.BIRDS_EYE_PITCH_DEG), 0.02)
	assert_almost_eq(_cam.get_map_blend(), 1.0, 0.0001)
	assert_true(_cam.is_map_visible())
	assert_signal_emitted_with_parameters(_cam, "map_mode_changed", [true])

func test_zooming_back_in_restores_shoulder_camera() -> void:
	_cam.set_zoom_immediate(150.0)
	for i in 40:
		_cam.handle_input(_inp, 0.1)
	watch_signals(_cam)
	_cam.set_zoom_immediate(8.0)
	for i in 80:
		_cam.handle_input(_inp, 0.1)
	assert_eq(_cam.collision_mask, 1)
	assert_false(_cam.is_map_visible())
	assert_true(_cam.rotation.x > deg_to_rad(-60.0), "Pitch muss wieder der Schulterkamera folgen.")
	assert_signal_emitted_with_parameters(_cam, "map_mode_changed", [false])

func test_player_pitch_is_remembered_across_map_trip() -> void:
	_cam.set_zoom_immediate(8.0)
	for i in 40:
		_cam.handle_input(_inp, 0.1)
	var before := _cam.rotation.x
	_cam.set_zoom_immediate(200.0)
	for i in 40:
		_cam.handle_input(_inp, 0.1)
	_cam.set_zoom_immediate(8.0)
	for i in 80:
		_cam.handle_input(_inp, 0.1)
	assert_almost_eq(_cam.rotation.x, before, 0.02)

func test_zoom_input_is_clamped_to_map_maximum() -> void:
	_inp.zoom_delta = 100000.0
	_cam.handle_input(_inp, 0.1)
	assert_true(_cam.get_zoom() <= PlayerCamera.MAX_ZOOM_MAP + 0.001)
	_inp.zoom_delta = -100000.0
	for i in 3:
		_cam.handle_input(_inp, 0.1)
		_inp.zoom_delta = -100000.0
	assert_true(_cam.get_zoom() >= PlayerCamera.MIN_ZOOM_FIRST_PERSON - 0.001)

func test_first_person_still_works_when_zooming_in() -> void:
	watch_signals(_cam)
	_cam.set_zoom_immediate(0.5)
	_cam.handle_input(_inp, 0.1)
	assert_true(_cam.is_first_person())
	assert_signal_emitted_with_parameters(_cam, "first_person_changed", [true])
