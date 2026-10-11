# res://tests/unit/test_world_map_view.gd
extends GutTest

## Tests für WorldMapView: Koordinaten-Mathematik (inkl. Abgleich mit der echten Kamera),
## Sichtbarkeit/Überblendung, Wiederherstellen des 3D-Renderings.

var _cam: PlayerCamera
var _player: Node3D
var _view: WorldMapView

func before_each() -> void:
	_player = add_child_autofree(Node3D.new())
	_cam = PlayerCamera.new()
	_player.add_child(_cam)
	_view = WorldMapView.new()
	add_child_autofree(_view)
	_view.setup(_cam, _player, _player, null)

func after_each() -> void:
	# Falls ein Test das 3D-Rendering abgeschaltet hat und vorzeitig fehlschlägt.
	get_viewport().disable_3d = false

# ── Mathematik ────────────────────────────────────────────────────

func test_world_to_screen_without_yaw_east_is_right_north_is_up() -> void:
	var sc := Vector2(400, 300)
	var c := Vector2(100, 100)
	var east := WorldMapView.world_to_screen(c + Vector2(10, 0), c, 0.0, 2.0, sc)
	var north := WorldMapView.world_to_screen(c + Vector2(0, -10), c, 0.0, 2.0, sc)
	assert_true(east.x > sc.x and is_equal_approx(east.y, sc.y))
	assert_true(north.y < sc.y and is_equal_approx(north.x, sc.x))
	assert_almost_eq(east.x - sc.x, 20.0, 0.001)

func test_world_screen_roundtrip() -> void:
	var sc := Vector2(540, 960)
	var c := Vector2(-250, 313)
	for yaw in [-2.5, -0.7, 0.0, 0.4, 1.9, 3.1]:
		var w := Vector2(-190, 420)
		var s := WorldMapView.world_to_screen(w, c, yaw, 1.7, sc)
		var back := WorldMapView.screen_to_world(s, c, yaw, 1.7, sc)
		assert_almost_eq(back.x, w.x, 0.001)
		assert_almost_eq(back.y, w.y, 0.001)

func test_center_world_maps_to_screen_center_for_any_yaw() -> void:
	for yaw in [0.0, 1.0, -2.0]:
		var p := WorldMapView.world_to_screen(Vector2(7, 9), Vector2(7, 9), yaw, 3.0, Vector2(100, 200))
		assert_eq(p, Vector2(100, 200))

func test_north_on_screen() -> void:
	assert_eq(WorldMapView.north_on_screen(0.0), Vector2(0.0, -1.0))
	var rotated := WorldMapView.north_on_screen(PI * 0.5)
	assert_almost_eq(rotated.x, 1.0, 0.0001)
	assert_almost_eq(rotated.y, 0.0, 0.0001)

func test_pixels_per_meter_and_visible_radius() -> void:
	assert_almost_eq(WorldMapView.pixels_per_meter(100.0, 800.0), 4.0, 0.0001)
	var r := WorldMapView.visible_radius_m(100.0, Vector2(800, 800))
	assert_almost_eq(r, 100.0 * sqrt(2.0), 0.001)
	assert_true(WorldMapView.visible_radius_m(100.0, Vector2(1600, 800)) > r)

func test_scale_bar_meters_never_exceeds_max_width() -> void:
	for ppm in [0.05, 0.3, 1.0, 4.0, 20.0]:
		var m := WorldMapView.scale_bar_meters(ppm, 200.0)
		assert_true(m * ppm <= 200.0 + 0.001 or m == 5.0)

func test_map_rotation_convention_matches_the_real_top_down_camera() -> void:
	# Stellt die Kamera senkrecht nach unten mit Yaw und prüft, dass die Bildschirmrichtung
	# eines Weltpunkts (Kamera.unproject_position) zu world_to_screen() passt.
	var yaw := 0.7
	_cam.collision_mask = 0
	_cam.rotation = Vector3(deg_to_rad(PlayerCamera.BIRDS_EYE_PITCH_DEG), yaw, 0.0)
	_cam.camera.position = Vector3(0.0, 0.0, 50.0)   # SpringArm setzt das sonst erst im Physik-Tick
	_cam.camera.current = true
	await get_tree().process_frame
	var vp := _cam.camera.get_viewport().get_visible_rect().size
	var sc := vp * 0.5
	var center := Vector2(_cam.global_position.x, _cam.global_position.z)
	for offset in [Vector2(10, 0), Vector2(0, -10), Vector2(-6, 8)]:
		var world := center + offset
		var expected := WorldMapView.world_to_screen(world, center, yaw, 1.0, sc) - sc
		var actual := _cam.camera.unproject_position(Vector3(world.x, _cam.global_position.y - 50.0, world.y)) - sc
		assert_true(expected.normalized().dot(actual.normalized()) > 0.98, "Richtung für Offset %s stimmt nicht: erwartet %s, tatsächlich %s." % [offset, expected, actual])

# ── Verhalten ─────────────────────────────────────────────────────

func test_map_layer_is_below_hud_and_ignores_input() -> void:
	assert_eq(_view.layer, WorldMapView.MAP_LAYER)
	assert_true(_view.layer < 1, "HUD liegt auf Layer 1 — Karte muss darunter bleiben.")
	assert_eq(_view._canvas.mouse_filter, Control.MOUSE_FILTER_IGNORE)

func test_map_is_hidden_in_normal_third_person() -> void:
	_cam.set_zoom_immediate(8.0)
	_view._process(0.1)
	assert_false(_view._canvas.visible)

func test_map_fades_in_with_zoom() -> void:
	_cam.set_zoom_immediate((PlayerCamera.MAP_ZOOM_START + PlayerCamera.MAP_ZOOM_FULL) * 0.5)
	_view._process(0.1)
	assert_true(_view._canvas.visible)
	assert_true(_view._canvas.modulate.a > 0.05 and _view._canvas.modulate.a < 0.95)

func test_map_is_fully_opaque_when_zoomed_far_out() -> void:
	_cam.set_zoom_immediate(200.0)
	_view._process(0.1)
	assert_true(_view._canvas.visible)
	assert_almost_eq(_view._canvas.modulate.a, 1.0, 0.0001)

func test_3d_rendering_is_disabled_only_while_map_is_fully_visible_and_restored() -> void:
	_cam.set_zoom_immediate(200.0)
	_view._process(0.1)
	assert_true(get_viewport().disable_3d)
	_cam.set_zoom_immediate(8.0)
	_view._process(0.1)
	assert_false(get_viewport().disable_3d, "Beim Heranzoomen muss das 3D-Rendering zurückkommen.")

func test_3d_rendering_is_restored_when_view_leaves_the_tree() -> void:
	_cam.set_zoom_immediate(200.0)
	_view._process(0.1)
	assert_true(get_viewport().disable_3d)
	_view.queue_free()
	await get_tree().process_frame
	assert_false(get_viewport().disable_3d)

func test_view_survives_freed_player_without_crash() -> void:
	_player.remove_child(_cam)
	_cam.free()
	_view._process(0.1)
	assert_false(_view._canvas.visible)

func test_drawing_with_markers_and_no_terrain_does_not_error() -> void:
	var npc := Node3D.new()
	npc.add_to_group("npcs")
	npc.position = Vector3(12.0, 0.0, -8.0)
	add_child_autofree(npc)
	_cam.set_zoom_immediate(120.0)
	_view._process(0.1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(_view._canvas.visible)
	assert_false(_view.is_baking(), "Ohne Gelände gibt es nichts zu backen.")
