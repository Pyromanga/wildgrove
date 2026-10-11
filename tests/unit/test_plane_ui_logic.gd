# res://tests/unit/test_plane_ui_logic.gd
extends GutTest

## Tests für die UI-Bausteine von Ebnen-Modus und Wasserwagen: Aktionsbau, Knopf-Zustände,
## Geist-Modus, Overlay-Mesh. (Das Zusammenspiel im 3D-Spiel prüft man am besten im Spielstand.)

func _hud() -> CanvasLayer:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	return layer

# ── GroundToolController.build_plane_action ─────

func test_plane_action_shape() -> void:
	var a := GroundToolController.build_plane_action(
		TerrainPlanePlanner.DIR_DOWN, "Abtragen", Vector3(1, 2, 3), 1.5, "p1", 7, MockEventBus.new())
	assert_eq(a.id, "plane_down_ground")
	assert_eq(a.label, "Abtragen")
	assert_eq(a.duration, GroundToolController.DURATION)
	assert_eq(a.speed_stat_id, GroundToolController.SPEED_STAT)
	assert_eq(a.peer_id, 7)

func test_plane_action_emits_only_on_completion() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	var a := GroundToolController.build_plane_action(
		TerrainPlanePlanner.DIR_BOTH, "Ebnen", Vector3(4, 0, 5), 2.25, "p1", 1, bus)
	assert_signal_not_emitted(bus.world(), "terrain_plane_requested")
	a.on_complete.call(1)
	assert_signal_emitted_with_parameters(bus.world(), "terrain_plane_requested",
		["p1", Vector3(4, 0, 5), 2.25, "both"])

func test_plane_event_direction_defaults_to_both() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	bus.world().emit_terrain_plane_requested("p1", Vector3.ZERO, 1.0)
	assert_signal_emitted_with_parameters(bus.world(), "terrain_plane_requested", ["p1", Vector3.ZERO, 1.0, "both"])

# ── GroundToolVisuals ───────────────────────────

func test_plane_mode_shows_controls_and_relabels() -> void:
	var v := GroundToolVisuals.new(_hud())
	assert_false(v.plane_set_button.visible, "Ohne Modus nur der Schalter.")
	assert_eq(v.dig_button.text, "⬇\nGraben")
	v.set_plane_mode(true)
	assert_true(v.plane_set_button.visible)
	assert_true(v.plane_level_button.visible)
	assert_true(v.plane_toggle_button.button_pressed)
	assert_eq(v.dig_button.text, "⬇\nAbtragen")
	assert_eq(v.fill_button.text, "⬆\nAuffüllen")
	v.set_plane_mode(false)
	assert_false(v.plane_level_button.visible)
	assert_eq(v.fill_button.text, "⬆\nFüllen")

func test_plane_controls_follow_shovel_visibility_and_busy() -> void:
	var v := GroundToolVisuals.new(_hud())
	v.set_active(true)
	assert_true(v.plane_container.visible)
	v.set_active(false)
	assert_false(v.plane_container.visible)
	v.set_busy(true)
	assert_true(v.plane_level_button.disabled)
	v.set_busy(false)
	assert_false(v.plane_level_button.disabled)

# ── BuildModeVisuals ────────────────────────────

func test_build_level_button_is_toggle_and_syncs_silently() -> void:
	var v := BuildModeVisuals.new(_hud())
	assert_true(v.level_button.toggle_mode)
	watch_signals(v.level_button)
	v.set_level_on(true)
	assert_true(v.level_button.button_pressed)
	assert_true(v.level_label.visible)
	assert_signal_not_emitted(v.level_button, "toggled", "Synchronisieren darf keine Rückkopplung auslösen.")
	v.set_level_text("x")
	v.set_level_on(false)
	assert_false(v.level_label.visible)
	assert_eq(v.level_label.text, "")

# ── TerrainEditGhost ────────────────────────────

func test_plane_ghost_has_own_color_and_blocked_is_red() -> void:
	var g := TerrainEditGhost.new()
	add_child_autofree(g)
	g.configure(5.0, 2.9, TerrainEditGhost.Mode.PLANE)
	g.apply_state(Vector3.ZERO, true)
	var mat := (g.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(mat.get_shader_parameter("fill_color"), TerrainEditGhost.COL_PLANE_OK)
	g.apply_state(Vector3.ZERO, false)
	assert_eq(mat.get_shader_parameter("fill_color"), TerrainEditGhost.COL_BLOCKED)

# ── LevelGaugeOverlay ───────────────────────────

func _flat(_x: float, _z: float) -> float:
	return 3.0

func test_overlay_builds_mesh_and_reports_stats() -> void:
	var o := LevelGaugeOverlay.new()
	add_child_autofree(o)
	assert_false(o.visible)
	var stats := o.update_view(_flat, Vector2(5, 5), 3.0, 3, 4.0)
	assert_true(o.visible)
	assert_eq(float(stats["level_share"]), 1.0)
	var mesh := (o.get_child(0) as MeshInstance3D).mesh as ArrayMesh
	assert_not_null(mesh)
	assert_eq(mesh.get_surface_count(), 1)
	o.hide_view()
	assert_false(o.visible)

func test_overlay_rebuilds_when_reference_changes() -> void:
	var o := LevelGaugeOverlay.new()
	add_child_autofree(o)
	o.update_view(_flat, Vector2.ZERO, 3.0, 2, 4.0)
	var level_share_before := float(o.get_stats()["level_share"])
	o.update_view(_flat, Vector2.ZERO, 6.0, 2, 4.0)
	assert_eq(level_share_before, 1.0)
	assert_eq(float(o.get_stats()["level_share"]), 0.0, "Neue Bezugshöhe → sofort neu berechnet.")
