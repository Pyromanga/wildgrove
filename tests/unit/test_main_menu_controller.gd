# res://tests/unit/test_main_menu_controller.gd
extends GutTest

## Regression BUG-21: inject_save_system() existierte als DI-Punkt, hatte aber
## nie einen Aufrufer — _save_system blieb dauerhaft null, die Charakterliste
## im Hauptmenü war deshalb immer leer (_refresh_character_list() loggte
## "SaveSystem nicht injiziert." und brach ab).
##
## Testet die Controller-Seite der DI direkt (kein Disk-I/O — Double überschreibt
## list_local_saves() statt der echten Datei-Implementierung in SaveSystem).

class SaveSystemDouble extends SaveSystem:
	var _fake_saves: Array[String] = []
	## ADR-029 Phase 1 (Round 62): Tracking für den Join-Handshake-Flow.
	## Überschreibt begin_session()/end_session() komplett statt der echten
	## Disk-I/O-Implementierung — analog list_local_saves() oben, gleicher
	## Grund: kein Test darf gegen die echte user://saves/-Datei laufen.
	var begin_session_calls: Array[String] = []
	var end_session_call_count: int = 0
	var fake_uuid: String = "fake-uuid"
	var fake_secret: String = "fake-secret"

	func list_local_saves() -> Array[String]:
		return _fake_saves
	func begin_session(player_id: String) -> void:
		begin_session_calls.append(player_id)
	func end_session() -> void:
		end_session_call_count += 1
	func get_active_player_uuid() -> String:
		return fake_uuid
	func get_active_player_secret() -> String:
		return fake_secret

## ADR-029 Phase 1 (Round 62): Spy für SessionManager.send_join_handshake() —
## kein echter ENet-Peer nötig, ruft direkt (die echte Methode würde ohne
## aktiven Client-Peer ohnehin nur loggen und zurückkehren, siehe
## SessionManager.send_join_handshake()-Guard).
class SessionManagerDouble extends SessionManager:
	var handshake_calls: Array = []
	func send_join_handshake(player_uuid: String, player_secret: String) -> void:
		handshake_calls.append([player_uuid, player_secret])

var _menu: MainMenuController
var _save_double: SaveSystemDouble
var _session_double: SessionManagerDouble

func before_each() -> void:
	_menu = MainMenuController.new()

	var center := VBoxContainer.new()
	center.name = "CenterContainer"
	_menu.add_child(center)

	var char_list := VBoxContainer.new()
	char_list.name = "CharacterList"
	center.add_child(char_list)

	var new_btn := Button.new()
	new_btn.name = "NewGameButton"
	center.add_child(new_btn)

	var status_lbl := Label.new()
	status_lbl.name = "StatusLabel"
	center.add_child(status_lbl)

	_save_double = SaveSystemDouble.new()
	# Bewusst NICHT add_child_autofree(): SessionManager.on_ready() lädt beim
	# echten Node-Lifecycle _credentials (PlayerCredentialStore, Default-Pfad
	# user://server_credentials.json) und verbindet multiplayer.*-Signale —
	# beides für diesen reinen Method-Spy unnötig und würde echte Produktions-
	# Seiteneffekte riskieren. send_join_handshake() ist hier vollständig
	# überschrieben, braucht also nie durch den Node-Lifecycle zu laufen.
	_session_double = SessionManagerDouble.new()

	add_child_autofree(_menu)

func after_each() -> void:
	if is_instance_valid(_session_double):
		_session_double.free()

func test_inject_save_system_sets_field_and_enables_character_list() -> void:
	_save_double._fake_saves = ["charakter_1", "charakter_2"]
	_menu.inject_save_system(_save_double)

	_menu.call("_refresh_character_list")

	var char_list := _menu.get_node("CenterContainer/CharacterList")
	assert_eq(char_list.get_child_count(), 2, "Beide gespeicherten Charaktere müssen als Buttons erscheinen")

func test_refresh_character_list_without_injection_stays_empty() -> void:
	# Kein inject_save_system() Aufruf — reproduziert exakt den Log-Befund.
	# BUG-23: dies ist inzwischen ein erwarteter Zwischenzustand (WARN statt
	# ERROR), da inject_save_system() sich selbst um die Nachlieferung kümmert.
	_menu.call("_refresh_character_list")

	var char_list := _menu.get_node("CenterContainer/CharacterList")
	assert_eq(char_list.get_child_count(), 0, "Ohne SaveSystem darf keine Charakterliste aufgebaut werden")

func test_inject_save_system_after_ready_self_heals_character_list() -> void:
	# BUG-23 Regression: reproduziert den realen Log-Befund
	# (wildgrove_2026-07-02_01-53-45.log) — _ready() lief bereits (in
	# before_each via add_child_autofree), SaveSystem trifft erst danach ein.
	# inject_save_system() muss die Liste OHNE manuellen _refresh-Aufruf füllen.
	_save_double._fake_saves = ["charakter_1"]

	var char_list := _menu.get_node("CenterContainer/CharacterList")
	assert_eq(char_list.get_child_count(), 0, "Vor der Injektion muss die Liste leer sein")

	_menu.inject_save_system(_save_double)

	assert_eq(char_list.get_child_count(), 1, "Injektion nach _ready() muss die Charakterliste selbst auffüllen")

# ─────────────────────────────────────────────
# ADR-029 Phase 1 (Round 62): Join-Handshake-Flow
# ─────────────────────────────────────────────

func test_character_selection_in_join_view_starts_handshake_not_direct_boot() -> void:
	_save_double._fake_saves = ["charakter_1"]
	_menu.inject_save_system(_save_double)
	_menu.inject_session_manager(_session_double)

	var requested: Array = []
	var _on_requested := func(pid: String) -> void: requested.append(pid)
	EventBus.session.session_requested.connect(_on_requested)

	_menu.call("_on_joined_as_client")
	_menu.call("_on_character_button_pressed", "charakter_1")

	assert_eq(_save_double.begin_session_calls, ["charakter_1"],
		"Auswahl im Join-Flow muss begin_session() für den gewählten Charakter auslösen.")
	assert_eq(_session_double.handshake_calls, [[_save_double.fake_uuid, _save_double.fake_secret]],
		"Auswahl im Join-Flow muss send_join_handshake() mit der geladenen Identität auslösen.")
	assert_eq(requested.size(), 0,
		"Vor der Handshake-Antwort darf noch kein session_requested emittiert werden (kein Auto-Boot).")

	if EventBus.session.session_requested.is_connected(_on_requested):
		EventBus.session.session_requested.disconnect(_on_requested)

func test_new_game_in_join_view_also_goes_through_handshake() -> void:
	_menu.inject_save_system(_save_double)
	_menu.inject_session_manager(_session_double)

	_menu.call("_on_joined_as_client")
	_menu.call("_on_new_game_pressed")

	assert_eq(_save_double.begin_session_calls.size(), 1,
		"[Neues Spiel] im Join-Flow muss ebenfalls begin_session() auslösen statt direkt zu booten.")
	assert_eq(_session_double.handshake_calls.size(), 1,
		"[Neues Spiel] im Join-Flow muss ebenfalls den Handshake auslösen.")

func test_join_handshake_accepted_emits_session_requested_for_chosen_character() -> void:
	_menu.inject_save_system(_save_double)
	_menu.inject_session_manager(_session_double)
	_menu.call("_on_joined_as_client")
	_menu.call("_on_character_button_pressed", "charakter_5")

	var requested: Array = []
	var _on_requested := func(pid: String) -> void: requested.append(pid)
	EventBus.session.session_requested.connect(_on_requested)

	_menu.call("_on_join_handshake_result", true, "")

	assert_eq(requested, ["charakter_5"],
		"Akzeptierter Handshake muss session_requested exakt für den gewählten Charakter emittieren.")
	assert_eq(_save_double.end_session_call_count, 0,
		"Akzeptierter Handshake darf die gerade begonnene Session nicht wieder beenden.")

	EventBus.session.session_requested.disconnect(_on_requested)

func test_join_handshake_rejected_ends_session_and_shows_reason() -> void:
	_menu.inject_save_system(_save_double)
	_menu.inject_session_manager(_session_double)
	_menu.call("_on_joined_as_client")
	_menu.call("_on_character_button_pressed", "charakter_5")

	var requested: Array = []
	var _on_requested := func(pid: String) -> void: requested.append(pid)
	EventBus.session.session_requested.connect(_on_requested)

	_menu.call("_on_join_handshake_result", false, "Unbekannte Identität.")

	assert_eq(requested.size(), 0,
		"Abgelehnter Handshake darf niemals session_requested emittieren.")
	assert_eq(_save_double.end_session_call_count, 1,
		"Abgelehnter Handshake muss die tentative SaveSystem-Session wieder beenden.")

	var status_lbl := _menu.get_node("CenterContainer/StatusLabel") as Label
	assert_true(status_lbl.text.contains("Unbekannte Identität."),
		"Der Ablehnungsgrund muss dem Spieler im StatusLabel angezeigt werden.")

	EventBus.session.session_requested.disconnect(_on_requested)

func test_join_handshake_result_without_pending_join_is_ignored() -> void:
	# Kein vorheriger _on_character_button_pressed()-Aufruf — simuliert ein
	# verspätetes Signal (z.B. nach Rückkehr ins Hauptmenü, siehe Kommentar in
	# _on_join_handshake_result()).
	_menu.inject_save_system(_save_double)
	_menu.inject_session_manager(_session_double)

	var requested: Array = []
	var _on_requested := func(pid: String) -> void: requested.append(pid)
	EventBus.session.session_requested.connect(_on_requested)

	_menu.call("_on_join_handshake_result", true, "")

	assert_eq(requested.size(), 0,
		"Ohne laufenden Handshake darf ein (verspätetes) Ergebnis nichts booten.")
	assert_eq(_save_double.end_session_call_count, 0,
		"Ohne laufenden Handshake darf auch keine Session beendet werden.")

	EventBus.session.session_requested.disconnect(_on_requested)

func test_character_selection_without_session_manager_does_not_start_handshake() -> void:
	# Kein inject_session_manager() — _start_join_handshake() muss den Guard
	# VOR begin_session() greifen lassen (siehe Reihenfolge in MainMenuController).
	_menu.inject_save_system(_save_double)

	_menu.call("_on_joined_as_client")
	_menu.call("_on_character_button_pressed", "charakter_1")

	assert_eq(_save_double.begin_session_calls.size(), 0,
		"Ohne SessionManager darf begin_session() gar nicht erst aufgerufen werden.")

func test_connection_lost_during_pending_join_resets_and_ends_session() -> void:
	_menu.inject_save_system(_save_double)
	_menu.inject_session_manager(_session_double)
	_menu.call("_on_joined_as_client")
	_menu.call("_on_character_button_pressed", "charakter_1")

	_menu.call("_on_network_peer_disconnected")

	assert_eq(_save_double.end_session_call_count, 1,
		"Verbindungsverlust während eines laufenden Handshakes muss die tentative Session beenden.")

	var requested: Array = []
	var _on_requested := func(pid: String) -> void: requested.append(pid)
	EventBus.session.session_requested.connect(_on_requested)
	_menu.call("_on_join_handshake_result", true, "")
	assert_eq(requested.size(), 0,
		"Ein nach dem Reset eintreffendes (verspätetes) Handshake-Ergebnis darf nicht mehr booten.")
	EventBus.session.session_requested.disconnect(_on_requested)

func test_menu_scope_initializer_emits_parent_as_menu_root() -> void:
	var root := Control.new()
	add_child_autofree(root)
	var initializer := MenuScopeInitializer.new()

	var received: Array = []
	initializer.menu_ready.connect(func(r: Control) -> void: received.append(r))
	root.add_child(initializer)
	await get_tree().process_frame

	assert_eq(received.size(), 1, "menu_ready muss genau einmal feuern")
	assert_eq(received[0], root, "menu_ready muss den Parent (MainMenu-Root) übergeben")
