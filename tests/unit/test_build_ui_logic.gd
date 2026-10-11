# res://tests/unit/test_build_ui_logic.gd
extends GutTest

## Tests für die testbare Logik hinter der Bau-/Graben-UI: Aktionsbau der Schaufel, Kosten-Text und
## Leistbarkeit im Bau-Menü, Geist-Zustände/-Geometrie, neue WorldEvents, Fehlertext-Zuordnung.
## (Die Node-Verdrahtung selbst — Buttons, Geist im 3D-Baum — prüft man am besten im Spiel.)

# ── GroundToolController.build_action ───────────

func test_dig_action_has_expected_shape() -> void:
	var bus := MockEventBus.new()
	var a := GroundToolController.build_action("dig", "Graben", Vector3(1, 2, 3), "p1", 7, bus)
	assert_eq(a.id, "dig_ground")
	assert_eq(a.label, "Graben")
	assert_eq(a.duration, GroundToolController.DURATION)
	assert_eq(a.speed_stat_id, GroundToolController.SPEED_STAT, "Schaufel-Tempo läuft über den Stat.")
	assert_eq(a.peer_id, 7)

func test_fill_action_id_differs() -> void:
	var a := GroundToolController.build_action("fill", "Füllen", Vector3.ZERO, "p1", 1, MockEventBus.new())
	assert_eq(a.id, "fill_ground")

func test_action_completion_emits_terrain_edit_request() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	var a := GroundToolController.build_action("dig", "Graben", Vector3(4, 0, 5), "p1", 1, bus)
	a.on_complete.call(1)
	assert_signal_emitted_with_parameters(bus.world(), "terrain_edit_requested", ["p1", "dig", Vector3(4, 0, 5)])

func test_action_does_not_emit_before_completion() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	GroundToolController.build_action("dig", "Graben", Vector3.ZERO, "p1", 1, bus)
	assert_signal_not_emitted(bus.world(), "terrain_edit_requested")

# ── WorldEvents ─────────────────────────────────

func test_build_place_event_carries_all_arguments() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	bus.world().emit_build_place_requested("p1", "wood_wall", Vector3(1, 2, 3), 3, 2)
	assert_signal_emitted_with_parameters(bus.world(), "build_place_requested", ["p1", "wood_wall", Vector3(1, 2, 3), 3, 2])

func test_build_place_event_defaults_to_ground_storey() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	bus.world().emit_build_place_requested("p1", "wood_wall", Vector3(1, 2, 3), 3)
	assert_signal_emitted_with_parameters(bus.world(), "build_place_requested", ["p1", "wood_wall", Vector3(1, 2, 3), 3, 0])

func test_build_house_place_event_carries_all_arguments() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	bus.world().emit_build_house_place_requested("p1", "test_hut", Vector3(1, 2, 3), 3, 2)
	assert_signal_emitted_with_parameters(
		bus.world(), "build_house_place_requested", ["p1", "test_hut", Vector3(1, 2, 3), 3, 2]
	)

func test_build_house_place_event_defaults_to_ground_storey() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	bus.world().emit_build_house_place_requested("p1", "test_hut", Vector3(1, 2, 3), 3)
	assert_signal_emitted_with_parameters(
		bus.world(), "build_house_place_requested", ["p1", "test_hut", Vector3(1, 2, 3), 3, 0]
	)

func test_build_remove_event() -> void:
	var bus := MockEventBus.new()
	watch_signals(bus.world())
	bus.world().emit_build_remove_requested("p1", "F_0_0")
	assert_signal_emitted_with_parameters(bus.world(), "build_remove_requested", ["p1", "F_0_0"])

# ── BuildPanelController ────────────────────────

func test_format_cost_without_inventory_falls_back_to_ids() -> void:
	assert_eq(BuildPanelController.format_cost({"log_normal": 3}, null), "3× log_normal")

func test_format_cost_lists_all_items() -> void:
	var text := BuildPanelController.format_cost({"log_normal": 3, "stone": 5}, null)
	assert_string_contains(text, "3× log_normal")
	assert_string_contains(text, "5× stone")

func test_can_afford_is_false_without_inventory() -> void:
	assert_false(BuildPanelController.can_afford({"log_normal": 1}, null, "p1"))

func test_build_entries_empty_without_data_service() -> void:
	assert_eq(BuildPanelController.build_entries(UIContext.for_test()).size(), 0)

# ── BuildPanelController: Häuser ─────────────────

## Eigene DataService-Fälschung statt MockDataService (test_wiki_panel_controller.gd) — die
## füllt andere interne Dictionaries (Quests/Skills/Loot), nicht _build_pieces/_house_templates.
class MockHouseDataService extends DataService:
	func _init() -> void:
		var floor_def := BuildPieceDefinition.new()
		floor_def.id = "wood_floor"
		floor_def.kind = BuildPieceDefinition.Kind.FLOOR
		floor_def.cost = {"log_normal": 4}
		var wall_def := BuildPieceDefinition.new()
		wall_def.id = "wood_wall"
		wall_def.kind = BuildPieceDefinition.Kind.WALL
		wall_def.cost = {"log_normal": 5, "stone": 3}
		_build_pieces = {"wood_floor": floor_def, "wood_wall": wall_def}
		_build_piece_order = ["wood_floor", "wood_wall"]

		var hut := HouseTemplateDefinition.new()
		hut.id = "test_hut"
		hut.display_name = "Testhütte"
		hut.description = "Vier Wände und ein Dach."
		hut.pieces = [
			{"piece_id": "wood_floor", "kind": BuildPieceDefinition.Kind.FLOOR, "axis": -1, "dx": 0, "dz": 0},
			{"piece_id": "wood_wall", "kind": BuildPieceDefinition.Kind.WALL, "axis": 0, "dx": 0, "dz": 0},
		]
		_house_templates = {"test_hut": hut}
		_house_template_order = ["test_hut"]

func test_build_house_entries_lists_templates_with_name_description_and_cost() -> void:
	var ctx := UIContext.for_test()
	ctx._data = MockHouseDataService.new()
	var entries: Array[Dictionary] = BuildPanelController.build_house_entries(ctx)
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["id"], "test_hut")
	assert_eq(entries[0]["name"], "Testhütte")
	assert_eq(entries[0]["description"], "Vier Wände und ein Dach.")
	# Summe über alle Teile der Vorlage (4 + 5 Holz, 3 Stein) — dieselbe Quelle wie
	# HouseTemplateDefinition.total_cost(), nicht nochmal von Hand nachgerechnet im Controller.
	assert_string_contains(entries[0]["cost_text"], "9× log_normal")
	assert_string_contains(entries[0]["cost_text"], "3× stone")

func test_build_house_entries_not_affordable_without_inventory() -> void:
	var ctx := UIContext.for_test()
	ctx._data = MockHouseDataService.new()
	var entries: Array[Dictionary] = BuildPanelController.build_house_entries(ctx)
	assert_false(entries[0]["affordable"], "Kein Inventar im Testkontext → nicht leistbar.")

func test_build_house_entries_empty_without_data_service() -> void:
	assert_eq(BuildPanelController.build_house_entries(UIContext.for_test()).size(), 0)

# ── BuildGhost ──────────────────────────────────

func test_ghost_state_from_preview() -> void:
	assert_eq(BuildGhost.state_from_preview({"ok": true, "affordable": true}), BuildGhost.State.OK)
	assert_eq(BuildGhost.state_from_preview({"ok": true, "affordable": false}), BuildGhost.State.NO_MATERIALS)
	assert_eq(BuildGhost.state_from_preview({"ok": false, "affordable": true}), BuildGhost.State.BLOCKED)
	assert_eq(BuildGhost.state_from_preview({}), BuildGhost.State.BLOCKED)

func test_ghost_colors_are_distinct() -> void:
	var ok := BuildGhost.color_for(BuildGhost.State.OK)
	var blocked := BuildGhost.color_for(BuildGhost.State.BLOCKED)
	var poor := BuildGhost.color_for(BuildGhost.State.NO_MATERIALS)
	assert_ne(ok, blocked)
	assert_ne(ok, poor)
	assert_ne(blocked, poor)

func test_ghost_uses_same_geometry_as_definition() -> void:
	var def := BuildPieceDefinition.new()
	def.kind = BuildPieceDefinition.Kind.WALL
	def.height = 2.5
	def.skirt = 0.8
	def.thickness = 0.25
	var ghost := BuildGhost.new()
	autofree(ghost)
	ghost.configure(def)
	var mesh := (ghost.get_node("GhostMesh") as MeshInstance3D)
	assert_eq((mesh.mesh as BoxMesh).size, def.get_box_size(BuildGrid.CELL))
	assert_eq(mesh.position, def.get_box_center())

func test_ghost_apply_state_moves_and_rotates() -> void:
	var def := BuildPieceDefinition.new()
	var ghost := BuildGhost.new()
	autofree(ghost)
	ghost.configure(def)
	ghost.apply_state(Vector3(3, 1, 5), PI * 0.5, BuildGhost.State.OK)
	assert_eq(ghost.position, Vector3(3, 1, 5))
	assert_almost_eq(ghost.rotation.y, PI * 0.5, 0.0001)

# ── WorldService: Fehlertext-Zuordnung ──────────

func test_reason_text_prefers_build_texts_then_terrain_texts() -> void:
	assert_eq(WorldService._reason_text("in_water"), BuildPlacementRules.reason_text("in_water"))
	assert_eq(WorldService._reason_text("limit"), WorldTerrainEditor.reason_text("limit"))
	assert_eq(WorldService._reason_text("building_nearby"), WorldTerrainEditor.reason_text("building_nearby"))
	assert_eq(WorldService._reason_text("too_far"), BuildPlacementRules.reason_text("too_far"))

# ── Leiter ──────────────────────────────────────

func test_ladder_action_sends_place_request_on_complete() -> void:
	var bus := MockEventBus.new()
	var a := GroundToolController.build_ladder_action(Vector3(1, 2, 3), Vector3(1, 0, 0), "p1", 7, bus)
	assert_eq(a.id, "place_ladder")
	assert_eq(a.duration, GroundToolController.LADDER_DURATION)
	watch_signals(bus.world())
	a.on_complete.call(7)
	assert_signal_emitted_with_parameters(bus.world(), "ladder_place_requested", ["p1", Vector3(1, 2, 3), Vector3(1, 0, 0)])

func test_ladder_reason_texts() -> void:
	assert_eq(WorldService._reason_text("no_wall"), WorldDigHandler.reason_text("no_wall"))
	assert_ne(WorldDigHandler.reason_text("too_long"), WorldDigHandler.reason_text(""))
