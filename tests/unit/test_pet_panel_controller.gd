# res://tests/unit/test_pet_panel_controller.gd
extends GutTest

## Tests für PetPanelController + PetPanelVisuals — Pet-Menü (Grid aus Kopf-Kacheln,
## Detailansicht mit Fähigkeits-Toggles, Suche/Filter, Live-Status, sofortiger
## Refresh bei neu gefangenen Pets).
##
## StubWorldService liefert Fake-Pets ohne echten SceneTree-Scan (siehe
## WorldService.get_pets_for_peer() — normalerweise get_tree().get_nodes_in_group("pets")).
## StubPet ist ein echtes PetComponent (muss `is PetComponent` bestehen, siehe
## PetPanelController._on_ability_toggled()), aber nie in einen SceneTree
## eingehängt — _ready()/on_spawn() laufen dadurch nie, nur die hier
## überschriebenen Lese-/Schreib-Methoden zählen.
##
## Die Visuals hängen NICHT im SceneTree (CanvasLayer ist nur autofree) — Tests
## rufen deshalb Handler wie _on_visibility_changed()/_on_status_tick() direkt
## auf, statt sich auf visibility_changed außerhalb des Trees zu verlassen.

class StubPet extends PetComponent:
	var _stub_name: String
	var _stub_abilities: Array[String]
	var stub_activity: Dictionary = {"ability": "", "acting": false}

	func _init(pet_name: String, abilities: Array[String]) -> void:
		_stub_name = pet_name
		_stub_abilities = abilities

	func get_pet_name() -> String:
		return _stub_name

	func get_abilities() -> Array[String]:
		return _stub_abilities.duplicate()

	func set_abilities(new_abilities: Array[String]) -> void:
		_stub_abilities = PetAbilities.sanitize(new_abilities)

	func get_owner_peer_id() -> int:
		return 1

	func get_current_activity() -> Dictionary:
		return stub_activity

class StubWorldService extends WorldService:
	var pets: Array[PetComponent] = []
	func get_pets_for_peer(_peer_id: int) -> Array[PetComponent]:
		return pets

var _ctrl: PetPanelController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: PetPanelVisuals
var _world: StubWorldService
var _pet: StubPet

func before_each() -> void:
	_canvas = autofree(CanvasLayer.new())
	_visuals = PetPanelVisuals.new(_canvas)

	_pet = autofree(StubPet.new("Fluffy", [PetAbilities.GATHERING]))
	_world = StubWorldService.new()
	_world.pets = [_pet]

	_bus = MockEventBus.new()
	_ctx = UIContext.for_test()
	_ctx._world = _world
	_ctx._bus = _bus
	_ctx._local_peer_id = 1

	_ctrl = add_child_autofree(PetPanelController.new())
	_ctrl.setup(_visuals, _ctx)  # setup() ruft bereits refresh() auf

func _tile(pet: PetComponent) -> Button:
	return _visuals._tiles[pet.get_instance_id()]["button"] as Button

# ─────────────────────────────────────────────
# Liste / Grid
# ─────────────────────────────────────────────

func test_setup_lists_owned_pet() -> void:
	assert_eq(_visuals._rows.get_child_count(), 1, "Ein Pet in world.pets → eine Kachel im Grid")

func test_pets_are_shown_in_a_multi_column_grid() -> void:
	assert_true(_visuals._rows is GridContainer)
	assert_gt(_visuals._rows.columns, 1, "Grid muss mehrere Spalten haben (Köpfe nebeneinander)")

func test_empty_label_hidden_when_pets_exist() -> void:
	assert_false(_visuals._empty_label.visible)

func test_no_pets_shows_empty_label() -> void:
	_world.pets = []
	_ctrl.refresh()
	assert_true(_visuals._empty_label.visible)
	assert_eq(_visuals._rows.get_child_count(), 0)

func test_reopening_panel_refreshes_pet_list() -> void:
	var second := autofree(StubPet.new("Rex", [PetAbilities.COMBAT]))
	_world.pets = [_pet, second]

	_visuals.panel.visible = true
	_ctrl._on_visibility_changed()

	assert_eq(_visuals._rows.get_child_count(), 2, "Neu gezähmtes Pet muss beim erneuten Öffnen auftauchen")

# ─────────────────────────────────────────────
# Sofort-Refresh bei neu gefangenen / entfernten Pets (Bugfix)
# ─────────────────────────────────────────────

func test_pet_spawned_event_adds_tile_without_reopening_panel() -> void:
	_visuals.panel.visible = true   # Panel bleibt offen — kein Schließen/Öffnen
	var second := autofree(StubPet.new("Rex", [PetAbilities.COMBAT]))
	_world.pets = [_pet, second]

	_bus.world().emit_entity_spawned("pet", null, Vector3.ZERO)
	await get_tree().process_frame

	assert_eq(_visuals._rows.get_child_count(), 2, "Frisch gefangenes Pet muss sofort als Kachel erscheinen")

func test_pet_despawned_event_removes_tile() -> void:
	_world.pets = []

	_bus.world().emit_entity_despawned("pet", "uuid-1")
	await get_tree().process_frame

	assert_eq(_visuals._rows.get_child_count(), 0)
	assert_true(_visuals._empty_label.visible)

func test_non_pet_spawn_event_does_not_refresh() -> void:
	var second := autofree(StubPet.new("Rex", [PetAbilities.COMBAT]))
	_world.pets = [_pet, second]

	_bus.world().emit_entity_spawned("oak_tree", null, Vector3.ZERO)
	await get_tree().process_frame

	assert_eq(_visuals._rows.get_child_count(), 1, "Nur Pet-Events dürfen einen Refresh auslösen")

func test_spawn_events_in_same_frame_are_coalesced() -> void:
	_bus.world().emit_entity_spawned("pet", null, Vector3.ZERO)
	_bus.world().emit_entity_spawned("pet", null, Vector3.ZERO)
	assert_true(_ctrl._refresh_pending, "Refresh ist vorgemerkt")
	await get_tree().process_frame
	assert_false(_ctrl._refresh_pending, "…und nach dem Frame genau einmal ausgeführt")

func test_controller_without_event_bus_still_works() -> void:
	var ctx := UIContext.for_test()
	ctx._world = _world
	ctx._local_peer_id = 1
	var canvas: CanvasLayer = autofree(CanvasLayer.new())
	var visuals := PetPanelVisuals.new(canvas)
	var ctrl: PetPanelController = add_child_autofree(PetPanelController.new())
	ctrl.setup(visuals, ctx)
	assert_eq(visuals._rows.get_child_count(), 1, "Ohne Bus: Refresh beim Setup/Öffnen funktioniert weiterhin")

# ─────────────────────────────────────────────
# Fähigkeiten zuweisen (Controller)
# ─────────────────────────────────────────────

func test_toggling_ability_on_adds_it_without_losing_existing() -> void:
	_ctrl._on_ability_toggled(_pet.get_instance_id(), PetAbilities.COMBAT, true)
	var abilities := _pet.get_abilities()
	assert_true(abilities.has(PetAbilities.COMBAT), "Neue Fähigkeit muss hinzugefügt werden")
	assert_true(abilities.has(PetAbilities.GATHERING), "Bestehende Fähigkeit darf nicht verloren gehen")

func test_toggling_ability_off_removes_it() -> void:
	_ctrl._on_ability_toggled(_pet.get_instance_id(), PetAbilities.GATHERING, false)
	assert_eq(_pet.get_abilities(), [])

func test_toggle_on_unknown_pet_instance_is_ignored_without_crash() -> void:
	_ctrl._on_ability_toggled(999999999, PetAbilities.COMBAT, true)
	# Kein Crash + das echte Pet bleibt unangetastet.
	assert_eq(_pet.get_abilities(), [PetAbilities.GATHERING])

# ─────────────────────────────────────────────
# Detailansicht
# ─────────────────────────────────────────────

func test_tapping_tile_opens_detail_view() -> void:
	_visuals._open_detail(_pet.get_instance_id())
	assert_true(_visuals._detail_view.visible)
	assert_false(_visuals._list_view.visible)

func test_detail_toggle_reaches_pet_through_controller() -> void:
	_visuals._open_detail(_pet.get_instance_id())
	_visuals._on_detail_ability_toggled(true, _pet.get_instance_id(), PetAbilities.MINING)
	assert_true(_pet.get_abilities().has(PetAbilities.MINING), "Toggle in der Detailansicht muss am Pet ankommen")

func test_back_returns_to_grid() -> void:
	_visuals._open_detail(_pet.get_instance_id())
	_visuals._show_grid()
	assert_true(_visuals._list_view.visible)
	assert_false(_visuals._detail_view.visible)

func test_detail_stays_open_across_structural_refresh_if_pet_still_exists() -> void:
	_visuals._open_detail(_pet.get_instance_id())
	_ctrl.refresh()
	assert_true(_visuals._detail_view.visible)

func test_detail_closes_when_its_pet_disappears() -> void:
	_visuals._open_detail(_pet.get_instance_id())
	_world.pets = []
	_ctrl.refresh()
	assert_true(_visuals._list_view.visible, "Detailansicht eines verschwundenen Pets muss zum Grid zurückspringen")

func test_closing_panel_resets_to_grid() -> void:
	_visuals._open_detail(_pet.get_instance_id())
	_visuals.panel.visible = false
	_visuals._on_panel_visibility_changed()
	assert_true(_visuals._list_view.visible)

# ─────────────────────────────────────────────
# Status / Filter / Suche
# ─────────────────────────────────────────────

func test_status_tick_updates_tile_status_text() -> void:
	_pet.stub_activity = {"ability": PetAbilities.MINING, "acting": true}
	_visuals.panel.visible = true
	_ctrl._on_status_tick()
	var lbl: Label = _visuals._tiles[_pet.get_instance_id()]["status"]
	assert_string_contains(lbl.text, "arbeitet")

func test_status_tick_does_not_rebuild_tiles() -> void:
	var before := _tile(_pet)
	_pet.stub_activity = {"ability": PetAbilities.MINING, "acting": false}
	_visuals.panel.visible = true
	_ctrl._on_status_tick()
	assert_same(_tile(_pet), before, "Status-Update darf Kacheln nicht neu bauen (Scroll-Position!)")

func test_status_tick_ignored_while_panel_closed() -> void:
	_pet.stub_activity = {"ability": PetAbilities.MINING, "acting": true}
	_visuals.panel.visible = false
	_ctrl._on_status_tick()
	var lbl: Label = _visuals._tiles[_pet.get_instance_id()]["status"]
	assert_string_contains(lbl.text, "Untätig")

func test_filter_idle_hides_working_pets() -> void:
	_pet.stub_activity = {"ability": PetAbilities.GATHERING, "acting": true}
	_visuals.panel.visible = true
	_ctrl._on_status_tick()
	_visuals._on_filter_chosen(PetPanelVisuals.FILTER_IDLE)
	assert_false(_tile(_pet).visible)
	assert_true(_visuals._no_match_label.visible)

func test_filter_busy_shows_working_pets() -> void:
	_pet.stub_activity = {"ability": PetAbilities.GATHERING, "acting": false}
	_visuals.panel.visible = true
	_ctrl._on_status_tick()
	_visuals._on_filter_chosen(PetPanelVisuals.FILTER_BUSY)
	assert_true(_tile(_pet).visible)

func test_filter_follows_activity_changes_live() -> void:
	_visuals._on_filter_chosen(PetPanelVisuals.FILTER_BUSY)
	assert_false(_tile(_pet).visible, "Untätiges Pet unter 'Aktiv' ausgeblendet")
	_pet.stub_activity = {"ability": PetAbilities.GATHERING, "acting": true}
	_visuals.panel.visible = true
	_ctrl._on_status_tick()
	assert_true(_tile(_pet).visible, "Sobald es arbeitet, erscheint es live unter 'Aktiv'")

func test_search_filters_by_name_case_insensitive() -> void:
	var second := autofree(StubPet.new("Rex", [PetAbilities.COMBAT]))
	_world.pets = [_pet, second]
	_ctrl.refresh()
	_visuals._on_search_changed("REX")
	assert_false(_tile(_pet).visible)
	assert_true(_tile(second).visible)

func test_filter_and_search_survive_structural_refresh() -> void:
	_visuals._on_search_changed("zzz")
	_ctrl.refresh()
	assert_false(_tile(_pet).visible, "Suche muss nach Rebuild weiter gelten")

func test_pet_matches_specific_ability_filter() -> void:
	var d := {"name": "A", "activity": PetAbilities.WOODCUTTING}
	assert_true(PetPanelVisuals.pet_matches(d, PetAbilities.WOODCUTTING, ""))
	assert_false(PetPanelVisuals.pet_matches(d, PetAbilities.MINING, ""))

func test_status_text_variants() -> void:
	assert_eq(PetPanelVisuals.status_text("", false, true), "💤 Untätig")
	assert_eq(PetPanelVisuals.status_text("", false, false), "🐾 Begleiter")
	assert_string_contains(PetPanelVisuals.status_text(PetAbilities.MINING, true, true), "arbeitet")
	assert_string_contains(PetPanelVisuals.status_text(PetAbilities.MINING, false, true), "unterwegs")
	assert_eq(PetPanelVisuals.status_text(PetAbilities.MINING, true, true, true), "⛏ arbeitet")

func test_every_ability_has_a_filter_label_and_chip() -> void:
	for ability_id in PetAbilities.ALL:
		assert_true(PetPanelVisuals.FILTER_ORDER.has(ability_id), "Filter fehlt für %s" % ability_id)
		assert_true(PetPanelVisuals.ABILITY_LABELS.has(ability_id), "Label fehlt für %s" % ability_id)

# ─────────────────────────────────────────────
# PetHeadIcon
# ─────────────────────────────────────────────

func test_head_icon_ignores_mouse_so_tile_gets_the_tap() -> void:
	var icon: PetHeadIcon = autofree(PetHeadIcon.create({}, 80.0))
	assert_eq(icon.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(icon.custom_minimum_size, Vector2(80, 80))

func test_head_icon_accepts_every_style_combination_without_crash() -> void:
	var icon: PetHeadIcon = add_child_autofree(PetHeadIcon.create({}, 80.0))
	icon.size = Vector2(80, 80)
	for ear in AnimalVisualProfile.EarStyle.values():
		for snout in AnimalVisualProfile.SnoutStyle.values():
			for gear in AnimalVisualProfile.HeadgearStyle.values():
				icon.set_appearance({
					"color": Color(0.4, 0.3, 0.2), "ear_style": ear,
					"snout_style": snout, "headgear_style": gear,
				})
	await get_tree().process_frame
	pass_test("Alle Stil-Kombinationen zeichnen ohne Fehler")
