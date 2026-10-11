# res://tests/unit/test_appearance_panel_controller.gd
extends GutTest

## Tests für AppearancePanelController — analog test_character_creation_
## controller.gd. Strategie: echte, konfigurierte CharacterCreationService-
## Instanz + nackter CanvasLayer für die Visuals (kein Player-Node in der
## Testumgebung -> _apply_to_player() ist dort ein garantiertes No-Op, siehe
## test_character_creation_controller.gd-Dateikommentar für die Begründung).

const P1 := "p1"

var _ctrl: AppearancePanelController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: AppearancePanelVisuals
var _svc: CharacterCreationService

func before_each() -> void:
	_canvas = autofree(CanvasLayer.new())
	_visuals = AppearancePanelVisuals.new(_canvas)
	_bus = MockEventBus.new()
	var save := SaveSystem.new()
	save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	_svc = CharacterCreationService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: save}))

func _make_ctx(local_player_id: String = P1) -> UIContext:
	var ctx := UIContext.for_test()
	ctx._bus = _bus
	ctx._character_creation = _svc
	ctx._local_player_id = local_player_id
	return ctx

func _setup_ctrl(local_player_id: String = P1) -> AppearancePanelController:
	_ctx = _make_ctx(local_player_id)
	var ctrl := add_child_autofree(AppearancePanelController.new())
	ctrl.setup(_visuals, _ctx)
	return ctrl

func test_setup_builds_a_row_for_every_field() -> void:
	_setup_ctrl()

	for field in CharacterLook.FIELDS:
		var key: String = String((field as Dictionary)["key"])
		# update_field() darf für jedes bekannte Feld aufgerufen werden, ohne
		# einen Fehler zu werfen -- der eigentliche Beweis, dass die Zeile
		# existiert, ist test_setup_shows_default_look_labels() unten.
		_visuals.update_field(key, "x")

func test_setup_shows_default_look_labels() -> void:
	_setup_ctrl()

	var expected := CharacterLook.label_of("hair_style", String(CharacterLook.DEFAULTS["hair_style"]))
	var lbl := _visuals._value_labels["hair_style"] as Label
	assert_eq(lbl.text, expected)

func test_setup_does_not_crash_without_local_player_node_in_scene() -> void:
	_setup_ctrl()
	assert_true(true)

func test_stepping_a_field_updates_the_service_look() -> void:
	_setup_ctrl()

	_visuals.field_stepped.emit("hair_style", 1)

	var ids := CharacterLook.option_ids("hair_style")
	var start_idx := ids.find(String(CharacterLook.DEFAULTS["hair_style"]))
	assert_eq(_svc.get_look(P1)["hair_style"], ids[(start_idx + 1) % ids.size()])

func test_stepping_a_field_updates_the_visible_label() -> void:
	_setup_ctrl()

	_visuals.field_stepped.emit("hair_style", 1)

	var ids := CharacterLook.option_ids("hair_style")
	var start_idx := ids.find(String(CharacterLook.DEFAULTS["hair_style"]))
	var expected_id: String = ids[(start_idx + 1) % ids.size()]
	var lbl := _visuals._value_labels["hair_style"] as Label
	assert_eq(lbl.text, CharacterLook.label_of("hair_style", expected_id))

func test_stepping_backward_wraps_to_last_option() -> void:
	_setup_ctrl()

	_visuals.field_stepped.emit("hair_style", -1)

	assert_eq(_svc.get_look(P1)["hair_style"], CharacterLook.option_ids("hair_style")[-1])

func test_stepping_only_changes_the_stepped_field() -> void:
	_setup_ctrl()

	_visuals.field_stepped.emit("skin", 1)

	var look := _svc.get_look(P1)
	for field in CharacterLook.FIELDS:
		var key: String = String((field as Dictionary)["key"])
		if key == "skin":
			continue
		assert_eq(look[key], CharacterLook.DEFAULTS[key], "Feld '%s' hätte sich nicht ändern dürfen." % key)

func test_opening_the_panel_refreshes_labels_from_service_state() -> void:
	_svc.request_set_look(P1, {"skin": "dark"})
	_setup_ctrl()

	var lbl := _visuals._value_labels["skin"] as Label
	assert_eq(lbl.text, CharacterLook.label_of("skin", "dark"))

func test_remote_look_change_for_local_player_refreshes_labels() -> void:
	_setup_ctrl()

	# Simuliert die Client-Übernahme eines von der Autorität bestätigten Looks
	# für den LOKALEN Spieler (z. B. nach einem RPC-Rückkanal).
	_svc.on_set_look_confirmed(P1, {"hair_color": "blue"})

	var lbl := _visuals._value_labels["hair_color"] as Label
	assert_eq(lbl.text, CharacterLook.label_of("hair_color", "blue"))

func test_look_change_for_a_different_player_is_ignored() -> void:
	_setup_ctrl(P1)

	_svc.on_set_look_confirmed("someone-else", {"skin": "dark"})

	var lbl := _visuals._value_labels["skin"] as Label
	assert_eq(lbl.text, CharacterLook.label_of("skin", String(CharacterLook.DEFAULTS["skin"])))

func test_setup_without_character_creation_service_does_not_crash() -> void:
	_ctx = UIContext.for_test()
	_ctx._bus = _bus
	_ctx._local_player_id = P1
	var ctrl := add_child_autofree(AppearancePanelController.new())

	ctrl.setup(_visuals, _ctx)
	_visuals.field_stepped.emit("skin", 1)

	assert_true(true)
