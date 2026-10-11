# res://tests/unit/test_character_creation_controller.gd
extends GutTest

## Tests für CharacterCreationController (Round 105, ADR-048). Round 106:
## request_submit_answers()/request_skip_creation() + character_creation_
## confirmed-Signal ersetzen den vorher synchron angenommenen Ablauf — die
## bestehenden Tests unten bleiben unverändert in ihren Assertions
## (funktionieren identisch, weil GDScript-Signale ohne echten Peer
## synchron ausgeliefert werden), neuer Abschnitt am Ende für den
## asynchronen Bestätigungspfad selbst (player_id-Filter).
##
## Strategie: echte, konfigurierte CharacterCreationService-Instanz (analog
## test_achievement_panel_controller.gd). NICHT abgedeckt hier: die
## tatsächliche Farb-Anwendung auf einen echten Player-Node
## (`_apply_current_appearance()` → `ctx.get_local_player()` →
## `PlayerVisuals.apply_appearance()`) — `IUIContext.get_local_player()`
## scannt die Gruppe "player" der echten SceneTree; einen vollständigen
## `Player`-Node (CharacterBody3D mit Kamera/Input/Physik-Setup) dafür in
## einem Unit-Test zu konstruieren wäre selbst ein ungetesteter, riskanter
## Pfad. In der Testumgebung ist die Gruppe "player" leer, `get_local_player()`
## liefert also null — `_apply_current_appearance()` ist dadurch ein
## garantiertes No-Op, genau das wird hier (indirekt, über "kein Crash")
## mitgeprüft. `PlayerVisuals.apply_appearance()` selbst hat einen eigenen,
## isolierten Test in `test_player_visuals.gd`.

const P1 := "p1"
const P2 := "p2"

var _ctrl: CharacterCreationController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: CharacterCreationVisuals
var _svc: CharacterCreationService

func _make_ctx(local_player_id: String) -> UIContext:
	var ctx := UIContext.for_test()
	ctx._bus = _bus
	ctx._character_creation = _svc
	ctx._local_player_id = local_player_id
	return ctx

func before_each() -> void:
	_canvas = autofree(CanvasLayer.new())
	_visuals = CharacterCreationVisuals.new(_canvas)
	_bus = MockEventBus.new()
	var save := SaveSystem.new()
	save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	_svc = CharacterCreationService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: save}))

func _setup_ctrl(local_player_id: String = P1) -> void:
	_ctx = _make_ctx(local_player_id)
	_ctrl = add_child_autofree(CharacterCreationController.new())
	_ctrl.setup(_visuals, _ctx)

func test_setup_shows_wizard_for_player_who_has_not_seen_creation() -> void:
	_setup_ctrl()

	assert_true(_visuals.panel.visible)

func test_setup_does_not_show_wizard_for_player_who_already_completed_creation() -> void:
	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	_setup_ctrl()

	assert_false(_visuals.panel.visible)

func test_setup_does_not_show_wizard_for_player_who_already_skipped() -> void:
	_svc.request_skip_creation(P1)

	_setup_ctrl()

	assert_false(_visuals.panel.visible)

func test_setup_does_not_crash_without_local_player_node_in_scene() -> void:
	# _apply_current_appearance() sucht über get_local_player() in der Gruppe
	# "player" -- in der Testumgebung leer, siehe Dateikommentar oben.
	_setup_ctrl()
	# Kein Crash bis hierhin ist die eigentliche Prüfung.
	assert_true(true)

func test_answering_all_four_questions_completes_creation() -> void:
	_setup_ctrl()

	_visuals.option_selected.emit("a")  # free_day
	_visuals.option_selected.emit("c")  # challenge
	_visuals.option_selected.emit("c")  # company
	_visuals.option_selected.emit("b")  # value

	assert_true(_svc.has_seen_creation(P1))
	assert_true(_svc.is_completed(P1))
	assert_eq(_svc.get_appearance_preset_id(P1), "wald")

func test_answering_all_questions_hides_the_wizard() -> void:
	_setup_ctrl()

	_visuals.option_selected.emit("a")
	_visuals.option_selected.emit("c")
	_visuals.option_selected.emit("c")
	_visuals.option_selected.emit("b")

	assert_false(_visuals.panel.visible)

func test_answering_all_questions_shows_welcome_toast() -> void:
	var notifications: Array = []
	_bus.ui().notification_requested.connect(func(text: String) -> void: notifications.append(text))

	_setup_ctrl()
	_visuals.option_selected.emit("a")
	_visuals.option_selected.emit("c")
	_visuals.option_selected.emit("c")
	_visuals.option_selected.emit("b")

	assert_eq(notifications.size(), 1)
	assert_true(String(notifications[0]).contains("Willkommen"))

func test_partial_answers_do_not_complete_creation() -> void:
	_setup_ctrl()

	_visuals.option_selected.emit("a")
	_visuals.option_selected.emit("c")

	assert_false(_svc.has_seen_creation(P1))
	assert_true(_visuals.panel.visible)

func test_skip_pressed_skips_creation() -> void:
	_setup_ctrl()

	_visuals.skip_pressed.emit()

	assert_true(_svc.has_seen_creation(P1))
	assert_false(_svc.is_completed(P1))

func test_skip_pressed_hides_the_wizard() -> void:
	_setup_ctrl()

	_visuals.skip_pressed.emit()

	assert_false(_visuals.panel.visible)

func test_skip_pressed_shows_toast() -> void:
	var notifications: Array = []
	_bus.ui().notification_requested.connect(func(text: String) -> void: notifications.append(text))

	_setup_ctrl()
	_visuals.skip_pressed.emit()

	assert_eq(notifications.size(), 1)
	assert_true(String(notifications[0]).contains("übersprungen"))

func test_skip_after_partial_answers_still_skips() -> void:
	_setup_ctrl()

	_visuals.option_selected.emit("a")
	_visuals.skip_pressed.emit()

	assert_true(_svc.has_seen_creation(P1))
	assert_false(_svc.is_completed(P1))

func test_other_players_progress_does_not_leak() -> void:
	_svc.request_submit_answers(P2, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	_setup_ctrl(P1)

	assert_true(_visuals.panel.visible, "P1 hat noch keine eigene Erstellung -- Wizard muss trotzdem erscheinen.")

# ─────────────────────────────────────────────────────────────────────────────
# Round 106 (ADR-048): asynchroner Bestätigungspfad — auf einem
# Nicht-Host-Client feuert character_creation_confirmed() erst NACH dem
# request_*()-Aufruf zurückkehrt (RPC-Rückkanal), nicht mehr synchron
# innerhalb davon. Hier simuliert, indem das Signal manuell und VERZÖGERT
# zum request_*()-Aufruf emittiert wird (ohne echten Peer im Test läuft
# request_submit_answers() selbst zwar synchron, aber der Controller darf
# sich nicht darauf verlassen — er muss ausschließlich auf das Signal
# reagieren).
# ─────────────────────────────────────────────────────────────────────────────

func test_creation_confirmed_for_other_player_is_ignored() -> void:
	_setup_ctrl(P1)

	_svc.character_creation_confirmed.emit(P2)

	assert_true(_visuals.panel.visible, "Ein character_creation_confirmed() für einen ANDEREN Spieler darf den lokalen Wizard nicht schließen.")

func test_creation_confirmed_for_local_player_closes_wizard_and_applies_appearance() -> void:
	_setup_ctrl(P1)
	# Service-Zustand wird extern gesetzt (simuliert den bereits erfolgten
	# RPC-Rückkanal, siehe CharacterCreationService._on_remote_creation_
	# completed_received()) -- der Controller selbst mutiert hier nichts,
	# er reagiert nur auf das Signal.
	_svc._seen[P1] = true
	_svc._completed[P1] = true
	_svc._appearance[P1] = "wald"

	_svc.character_creation_confirmed.emit(P1)

	assert_false(_visuals.panel.visible)
