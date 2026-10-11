extends Control
class_name MainMenuController

## MainMenuController — Haupt-/Character-Select- und Netzwerk-Setup-Screen.
##
## Zustände (enum _View):
##   CHARACTERS            — Standard: Character-Liste + [Neues Spiel] + [Multiplayer]-Button.
##   NET_SETUP             — Netzwerk-Panel: [Host starten] / [Beitreten] Optionen.
##   HOST_ACTIVE           — Host läuft; Character-Liste wird gezeigt mit "Host aktiv auf Port X"-Hinweis.
##   CONNECTING            — Verbindungsversuch als Client; zeigt Fortschritts-Label.
##   JOIN_CHARACTER_SELECT — Verbunden, aber noch kein Handshake; Character-Liste
##                           wird gezeigt, Auswahl löst den Join-Handshake aus statt
##                           direkt zu booten (ADR-029 Phase 1, Schritt 4).
##
## Flow Solo:
##   Charakter klicken → emit_session_requested(player_id) → GameManager → PLAYING.
##
## Flow Host:
##   [Multiplayer] → NET_SETUP → [Host starten] + Port →
##   emit_host_game_requested(port) → SessionManager.create_server() →
##   EventBus.networking.hosting_started → HOST_ACTIVE →
##   Charakter klicken → emit_session_requested(player_id) → PLAYING.
##
## Flow Join (Client) — ADR-029 Phase 1:
##   [Multiplayer] → NET_SETUP → [Beitreten] + IP:Port →
##   emit_join_game_requested(ip, port) → SessionManager.join_server() →
##   EventBus.networking.joined_as_client → JOIN_CHARACTER_SELECT (Character-Liste) →
##   Charakter klicken → SaveSystem.begin_session(player_id) (lädt/erzeugt
##   player_uuid+player_secret) → SessionManager.send_join_handshake(uuid, secret) →
##   EventBus.networking.join_handshake_result:
##     accepted → emit_session_requested(player_id) → PLAYING
##     abgelehnt → SaveSystem.end_session(), zurück zu JOIN_CHARACTER_SELECT mit Fehlertext.
##   Es gibt keinen Auto-Boot mehr — ServiceOrchestrator bootet erst nach dieser
##   UI-getriebenen Bestätigung (siehe ADR-029 Checkliste, Schritte 4+5).

const LOG_CAT      := "MainMenuController"
const NEW_CHAR_PREFIX := "charakter"

enum _View { CHARACTERS, NET_SETUP, HOST_ACTIVE, CONNECTING, JOIN_CHARACTER_SELECT }

var _save_system: SaveSystem = null
var _session_manager: SessionManager = null
## Round 109 (TODO Punkt 1): IAppContext statt direktem EventBus-AutoLoad-
## Zugriff. Siehe inject_app_context() für den Injektionspunkt und _bus() für
## den Null-sicheren Zugriff aus den Event-Handlern unten.
var _app_ctx: IAppContext = null
var _current_view: _View    = _View.CHARACTERS
var _host_port: int         = 7777

## ADR-029 Phase 1: player_id, für den gerade ein Join-Handshake läuft (zwischen
## _start_join_handshake() und der Antwort in _on_join_handshake_result()).
## Leer, solange kein Handshake unterwegs ist.
var _pending_join_player_id: String = ""

# ─────────────────────────────────────────────
# DI
# ─────────────────────────────────────────────

func inject_save_system(svc: SaveSystem) -> void:
	_save_system = svc
	# BUG-23: Self-heilende Injektion. inject_save_system() kann je nach Node-/
	# Autoload-Ready-Reihenfolge NACH dem ersten _refresh_character_list()-Aufruf
	# in _ready() ankommen (derselbe Fehler trat nach der ursprünglichen
	# BUG-21-Fix erneut auf, weil der Push-Aufruf zeitlich nicht garantiert vor
	# _ready() lag). Statt sich auf Ready-Reihenfolge zu verlassen, aktualisiert
	# die Injektion selbst die Ansicht, falls sie gerade sichtbar ist.
	if is_instance_valid(svc) and (_current_view == _View.CHARACTERS or _current_view == _View.JOIN_CHARACTER_SELECT):
		_refresh_character_list()

## ADR-029 Phase 1 (Round 62): analog inject_save_system(), gepusht von
## ServiceOrchestrator._on_menu_initializer_ready(). Wird für
## send_join_handshake() im Join-Flow gebraucht.
func inject_session_manager(svc: SessionManager) -> void:
	_session_manager = svc
	# BUGFIX (2026-09-14): siehe _show_initial_view() — falls die Injektion
	# NACH _ready() ankommt (BUG-23-Timing), zeigte _ready() bis hierhin
	# noch CHARACTERS, obwohl evtl. schon ein Peer aktiv ist. Sobald
	# _session_manager da ist, sofort neu entscheiden.
	_show_initial_view()

## Round 109 (TODO Punkt 1): löst die EventBus-Zugriffs-Konsolidierung auf
## IEventBus (ADR-012-Prinzip) für MainMenuController. Verdrahtet HIER (statt
## in _ready()) alle Listener, die vorher direkt am EventBus-AutoLoad hingen —
## die Injektion kommt per Push und ist wie bei inject_save_system() nicht
## garantiert vor _ready() da (BUG-23), die Listener können also erst
## existieren, sobald der Context wirklich eingetroffen ist.
func inject_app_context(ctx: IAppContext) -> void:
	_app_ctx = ctx
	var bus := _bus()
	if bus == null:
		AppLogger.log_error(
			"IAppContext ohne IEventBus injiziert — Netzwerk-/Session-Listener bleiben unverdrahtet.",
			LOG_CAT
		)
		return
	bus.session().session_unloaded.connect(_on_session_unloaded)
	bus.persistence().save_slot_deleted.connect(_on_save_deleted)
	bus.networking().hosting_started.connect(_on_hosting_started)
	bus.networking().connection_to_server_failed.connect(_on_connection_failed)
	bus.networking().network_peer_disconnected.connect(_on_network_peer_disconnected)
	# ADR-029 Phase 1 (Round 62): der frühere direkte joined_as_client-Connect
	# hier ("_on_client_connected()", Auto-Boot mit synthetischer
	# "client_%d"-ID) ist entfernt. Der Client wählt jetzt in
	# MainMenuController (JOIN_CHARACTER_SELECT) selbst einen Charakter und
	# durchläuft den Join-Handshake, BEVOR überhaupt session_requested
	# emittiert wird — siehe Klassenkommentar "Flow Join".
	bus.networking().joined_as_client.connect(_on_joined_as_client)
	bus.networking().join_handshake_result.connect(_on_join_handshake_result)
	# BUG-23: der einzige bisherige boot_failed-Listener saß in Main.tscn, das
	# nie geladen wird (run/main_scene ist MainMenu.tscn) — ein App-Boot-Fehler
	# war für den Spieler dadurch unsichtbar und sah aus wie ein einfaches
	# Hängenbleiben. MainMenuController ist immer geladen, also lauscht er jetzt
	# selbst und zeigt den Fehler sichtbar an statt ihn stumm zu verwerfen.
	bus.system().boot_failed.connect(_on_boot_failed)

## Null-sicherer Zugriff auf den injizierten Bus für die Event-Handler unten —
## _app_ctx kann (BUG-23-artig) fehlen, wenn dieser Handler vor dem Push feuert.
func _bus() -> IEventBus:
	return _app_ctx.bus() if is_instance_valid(_app_ctx) else null

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	_build_static_ui()
	_show_initial_view()
	AppLogger.log_info("MainMenuController bereit.", LOG_CAT)

## BUGFIX (2026-09-14): SessionManager ist App-weit persistent — ein
## laufender Host/eine Client-Verbindung überlebt eine frische
## MainMenu-Szene (z.B. nach 'Zurück zum Hauptmenü'). Ohne diesen Check
## würde _ready() immer _View.CHARACTERS zeigen, der '[Multiplayer]'-
## Button wäre wieder da, und ein erneuter Host/Join-Klick würde nur
## noch von session_manager_reentry_guard abgefangen (kein Crash mehr,
## aber ein verwirrendes 'passiert nichts'). Aufgerufen von _ready() UND
## von inject_session_manager() (Self-Healing analog inject_save_system(),
## BUG-23) — welche der beiden zuerst dran ist, ist nicht garantiert.
func _show_initial_view() -> void:
	if is_instance_valid(_session_manager) and _session_manager.has_active_peer():
		if _session_manager.is_server():
			_show_view(_View.HOST_ACTIVE)
		else:
			_show_view(_View.JOIN_CHARACTER_SELECT)
	else:
		_show_view(_View.CHARACTERS)

func _on_boot_failed(phase: String, reason: String) -> void:
	AppLogger.log_error("App-Boot fehlgeschlagen (Phase '%s'): %s" % [phase, reason], LOG_CAT)
	_set_status("Start fehlgeschlagen (%s): %s — bitte Log prüfen." % [phase, reason])

# ─────────────────────────────────────────────
# UI aufbauen (statische Buttons werden einmalig verdrahtet)
# ─────────────────────────────────────────────

func _build_static_ui() -> void:
	# Solo-Bereich
	var new_btn := _get_new_game_button()
	if new_btn:
		new_btn.pressed.connect(_on_new_game_pressed, CONNECT_ONE_SHOT)

	# Multiplayer-Button
	var mp_btn := _get_multiplayer_button()
	if mp_btn:
		mp_btn.pressed.connect(_show_net_setup)

	# Net-Setup-Panel
	var host_btn := _get_start_host_button()
	if host_btn:
		host_btn.pressed.connect(_on_start_host_pressed)

	var join_btn := _get_start_join_button()
	if join_btn:
		join_btn.pressed.connect(_on_start_join_pressed)

	var back_btn := _get_back_button()
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)

# ─────────────────────────────────────────────
# View-Switching
# ─────────────────────────────────────────────

func _show_view(view: _View) -> void:
	_current_view = view

	var center    := _get_center_container()
	var net_panel := _get_net_panel()
	# BUGFIX (2026-09-14): mp_btn lebt in 'center', der auch für
	# HOST_ACTIVE/CONNECTING/JOIN_CHARACTER_SELECT sichtbar bleibt (für die
	# Charakter-Liste). Ohne explizites Verstecken bleibt der
	# '[Multiplayer]'-Button dort erreichbar, führt zurück zu NET_SETUP und
	# erlaubt einen zweiten Host/Join-Versuch, während der erste Peer noch
	# aktiv ist -> 'Couldn't create an ENet host' (siehe SessionManager
	# create_server()/join_server() Reentry-Guard als zweite Verteidigungslinie).
	var mp_btn := _get_multiplayer_button()

	match view:
		_View.CHARACTERS:
			if center:    center.visible    = true
			if net_panel: net_panel.visible = false
			if mp_btn:    mp_btn.visible    = true
			_refresh_character_list()
			_update_new_game_button()
			_set_status("")

		_View.NET_SETUP:
			if center:    center.visible    = false
			if net_panel: net_panel.visible = true
			_set_status("")

		_View.HOST_ACTIVE:
			if center:    center.visible    = true
			if net_panel: net_panel.visible = false
			if mp_btn:    mp_btn.visible    = false
			_refresh_character_list()
			_update_new_game_button()
			_set_status("Server läuft auf Port %d — wähle einen Charakter." % _host_port)

		_View.CONNECTING:
			if center:    center.visible    = true
			if net_panel: net_panel.visible = false
			if mp_btn:    mp_btn.visible    = false
			_set_status("Verbinde mit Server…")
			_clear_character_list()

		_View.JOIN_CHARACTER_SELECT:
			if center:    center.visible    = true
			if net_panel: net_panel.visible = false
			if mp_btn:    mp_btn.visible    = false
			_refresh_character_list()
			_update_new_game_button()
			_set_status("Verbunden — wähle einen Charakter zum Beitreten.")

func _set_status(text: String) -> void:
	var lbl := _get_status_label()
	if lbl:
		lbl.text   = text
		lbl.visible = not text.is_empty()

# ─────────────────────────────────────────────
# Charakter-Liste
# ─────────────────────────────────────────────

func _refresh_character_list() -> void:
	_clear_character_list()
	if not is_instance_valid(_save_system):
		# BUG-23: kein Fehler, sondern erwarteter Zwischenzustand. Die Injektion
		# kommt per Push (MenuScopeInitializer → ServiceOrchestrator) und ist
		# nicht garantiert vor _ready() da — inject_save_system() ruft
		# _refresh_character_list() selbst erneut auf, sobald sie eintrifft
		# (Selbstheilung, siehe dort). Ein dauerhaft fehlendes SaveSystem wäre
		# nur dann ein echtes Problem, wenn danach nie injiziert wird — das
		# lässt sich hier zur Aufrufzeit nicht unterscheiden, daher WARN statt
		# ERROR.
		AppLogger.log_warn("SaveSystem noch nicht injiziert — warte auf Push.", LOG_CAT)
		return
	for player_id in _save_system.list_local_saves():
		_add_character_button(player_id)

func _clear_character_list() -> void:
	var list := _get_character_list()
	if list:
		# BUG-FIX: queue_free() ist deferred (wirkt erst am Frame-Ende). Wird
		# _refresh_character_list() zweimal im selben Frame aufgerufen (z.B.
		# inject_save_system() → Selbstheilung + expliziter Folgeaufruf), sind
		# die alten Buttons beim erneuten Aufbau noch nicht entfernt und
		# akkumulieren sich (siehe HarvestableEntity._clear_visuals() für
		# denselben Fix-Pattern). Sofortiges free() ist hier sicher, da
		# Character-Buttons keine hängenden Cross-Frame-Verbindungen halten.
		for child in list.get_children():
			list.remove_child(child)
			child.free()

func _add_character_button(player_id: String) -> void:
	var list := _get_character_list()
	if not list:
		return
	var btn := Button.new()
	btn.text = _format_character_name(player_id)
	btn.pressed.connect(func() -> void: _on_character_button_pressed(player_id))
	list.add_child(btn)

## ADR-029 Phase 1: dieselbe Character-Liste bedient zwei Flows — normale
## Auswahl (CHARACTERS/HOST_ACTIVE, direkt booten) und Join-Auswahl
## (JOIN_CHARACTER_SELECT, erst Handshake). Dispatch nach _current_view statt
## zweier separater Listen/Buttons, weil die UI in beiden Fällen identisch ist.
func _on_character_button_pressed(player_id: String) -> void:
	if _current_view == _View.JOIN_CHARACTER_SELECT:
		_start_join_handshake(player_id)
	else:
		_on_character_selected(player_id)

func _update_new_game_button() -> void:
	var btn := _get_new_game_button()
	if not btn:
		return
	if not is_instance_valid(_save_system):
		return
	var saves := _save_system.list_local_saves()
	btn.text = "Neues Spiel" if saves.is_empty() else "Neuer Charakter"
	# Neu verbinden (nach queue_free beim View-Wechsel kann der Button neu sein)
	if not btn.pressed.is_connected(_on_new_game_pressed):
		btn.pressed.connect(_on_new_game_pressed, CONNECT_ONE_SHOT)

func _format_character_name(player_id: String) -> String:
	return player_id.replace("_", " ").capitalize()

# ─────────────────────────────────────────────
# Event-Handler
# ─────────────────────────────────────────────

func _on_character_selected(player_id: String) -> void:
	AppLogger.log_info("Charakter ausgewählt: '%s'." % player_id, LOG_CAT)
	var bus := _bus()
	if bus == null:
		AppLogger.log_error("Kein IAppContext injiziert — Charakter-Boot abgebrochen.", LOG_CAT)
		return
	bus.session().emit_session_requested(player_id)

func _on_new_game_pressed() -> void:
	var new_id := "%s_%d" % [NEW_CHAR_PREFIX, Time.get_unix_time_from_system()]
	AppLogger.log_info("Neuer Charakter: '%s'." % new_id, LOG_CAT)
	if _current_view == _View.JOIN_CHARACTER_SELECT:
		_start_join_handshake(new_id)
		return
	var bus := _bus()
	if bus == null:
		AppLogger.log_error("Kein IAppContext injiziert — Charakter-Boot abgebrochen.", LOG_CAT)
		return
	bus.session().emit_session_requested(new_id)

func _on_session_unloaded() -> void:
	_show_view(_View.CHARACTERS)

func _on_save_deleted(_player_id: String) -> void:
	if _current_view == _View.CHARACTERS or _current_view == _View.HOST_ACTIVE:
		_refresh_character_list()

# ── Netzwerk-Events ───────────────────────────────────────────────────────────

func _show_net_setup() -> void:
	_show_view(_View.NET_SETUP)

func _on_back_pressed() -> void:
	_show_view(_View.CHARACTERS)

func _on_start_host_pressed() -> void:
	var port_edit := _get_host_port_edit()
	if is_instance_valid(port_edit) and port_edit.text.is_valid_int():
		_host_port = int(port_edit.text)
	AppLogger.log_info("Host angefordert auf Port %d." % _host_port, LOG_CAT)
	var bus := _bus()
	if bus == null:
		AppLogger.log_error("Kein IAppContext injiziert — Host-Anfrage abgebrochen.", LOG_CAT)
		return
	bus.networking().emit_host_game_requested(_host_port)
	# Weiter nach _on_hosting_started via bus().networking()

func _on_start_join_pressed() -> void:
	var addr_edit := _get_join_address_edit()
	var port_edit := _get_join_port_edit()
	var address   := "127.0.0.1"
	var port      := 7777
	if is_instance_valid(addr_edit) and not addr_edit.text.is_empty():
		address = addr_edit.text
	if is_instance_valid(port_edit) and port_edit.text.is_valid_int():
		port = int(port_edit.text)
	AppLogger.log_info("Join angefordert: %s:%d." % [address, port], LOG_CAT)
	var bus := _bus()
	if bus == null:
		AppLogger.log_error("Kein IAppContext injiziert — Join-Anfrage abgebrochen.", LOG_CAT)
		return
	_show_view(_View.CONNECTING)
	bus.networking().emit_join_game_requested(address, port)
	# Weiter via SessionManager → bus().networking().joined_as_client → ServiceOrchestrator

func _on_hosting_started(port: int) -> void:
	_host_port = port
	_show_view(_View.HOST_ACTIVE)

func _on_connection_failed() -> void:
	_reset_pending_join()
	_set_status("Verbindung fehlgeschlagen. Bitte erneut versuchen.")
	_show_view(_View.NET_SETUP)

func _on_network_peer_disconnected() -> void:
	_reset_pending_join()
	_set_status("Verbindung zum Server verloren.")
	_show_view(_View.CHARACTERS)

# ── ADR-029 Phase 1: Join-Handshake ───────────────────────────────────────────

## Client ist verbunden (roher ENet-Connect) — noch nicht gehandshaked.
## Ersetzt den früheren Auto-Boot (ServiceOrchestrator._on_client_connected(),
## entfernt in Round 62): der Spieler wählt jetzt selbst einen lokalen
## Charakter, bevor irgendetwas gebootet wird.
func _on_joined_as_client() -> void:
	_show_view(_View.JOIN_CHARACTER_SELECT)

## Lädt/erzeugt die stabile Identität (player_uuid/player_secret) für den
## gewählten Charakter und schickt sie als Handshake an den Server. Der
## eigentliche Session-Boot läuft erst in _on_join_handshake_result() bei
## Erfolg — vorher ist der Charakter nur "vorgeladen", nicht aktiv gebootet.
func _start_join_handshake(player_id: String) -> void:
	if not is_instance_valid(_save_system):
		AppLogger.log_error("Kein SaveSystem injiziert — Handshake abgebrochen.", LOG_CAT)
		return
	if not is_instance_valid(_session_manager):
		AppLogger.log_error("Kein SessionManager injiziert — Handshake abgebrochen.", LOG_CAT)
		return

	AppLogger.log_info("Join-Handshake gestartet für Charakter '%s'." % player_id, LOG_CAT)
	_pending_join_player_id = player_id
	# begin_session() lädt player_uuid/player_secret von Disk oder erzeugt sie
	# einmalig neu (z.B. neuer Charakter). Idempotenz-Guard in SaveSystem
	# (Round 62) sorgt dafür, dass der spätere Boot-Pipeline-Aufruf für
	# dieselbe player_id dieselbe Identität wiederverwendet statt sie erneut
	# zufällig neu zu erzeugen.
	_save_system.begin_session(player_id)
	var uuid   := _save_system.get_active_player_uuid()
	var secret := _save_system.get_active_player_secret()
	_set_status("Sende Charakter-Identität an den Server…")
	_session_manager.send_join_handshake(uuid, secret)

## BUGFIX (2026-09-15): das join_handshake_result-Signal wurde um den dritten
## Parameter world_seed erweitert (world_seed-Sync-Fix), diese Methode hatte
## aber weiterhin nur 2 Parameter — Godot verwirft überzählige Signal-Argumente
## NICHT automatisch, sondern bricht den Callback mit "Method expected 2
## argument(s), but called with 3" ab. Ergebnis: der Client bootete nach einem
## akzeptierten Handshake gar nicht mehr (dieser Callback lief nie), blieb im
## Hauptmenü hängen. world_seed selbst wird hier nicht gebraucht — SessionManager
## übernimmt ihn bereits selbst in _rpc_join_handshake_result(), bevor das
## Signal emittiert wird (siehe dort).
func _on_join_handshake_result(accepted: bool, reason: String, _world_seed: int = 0) -> void:
	if _pending_join_player_id.is_empty():
		# Kein Handshake unterwegs (z.B. verspätetes Signal nach Rückkehr ins
		# Hauptmenü) — ignorieren statt versehentlich zu booten.
		return

	var player_id := _pending_join_player_id
	_pending_join_player_id = ""

	if accepted:
		AppLogger.log_info("Join-Handshake akzeptiert — bootet '%s'." % player_id, LOG_CAT)
		var bus := _bus()
		if bus == null:
			AppLogger.log_error("Kein IAppContext injiziert — Charakter-Boot abgebrochen.", LOG_CAT)
			return
		bus.session().emit_session_requested(player_id)
	else:
		AppLogger.log_warn("Join-Handshake abgelehnt für '%s': %s" % [player_id, reason], LOG_CAT)
		if is_instance_valid(_save_system):
			_save_system.end_session()
		# BUGFIX (Round 62, gefunden beim Schreiben der Tests): _show_view()
		# setzt für JOIN_CHARACTER_SELECT selbst einen generischen Status-Text
		# ("Verbunden — wähle…") — vorher aufgerufen hätte das den Ablehnungsgrund
		# sofort wieder überschrieben, bevor der Spieler ihn lesen kann. Deshalb
		# hier ERST die View wechseln, DANN den spezifischeren Fehlertext setzen.
		_show_view(_View.JOIN_CHARACTER_SELECT)
		_set_status("Beitritt abgelehnt: %s" % reason)

## Räumt einen unterwegs befindlichen Handshake auf (Verbindung fehlgeschlagen/
## verloren, bevor eine Antwort kam). Verwirft die tentative SaveSystem-Session,
## damit kein halb-initialisierter Zustand hängen bleibt.
func _reset_pending_join() -> void:
	if _pending_join_player_id.is_empty():
		return
	if is_instance_valid(_save_system):
		_save_system.end_session()
	_pending_join_player_id = ""

# ─────────────────────────────────────────────
# Node-Referenzen
# ─────────────────────────────────────────────

func _get_center_container() -> Node:
	return get_node_or_null("CenterContainer")

func _get_character_list() -> Node:
	return get_node_or_null("CenterContainer/CharacterList")

func _get_new_game_button() -> Button:
	return get_node_or_null("CenterContainer/NewGameButton") as Button

func _get_multiplayer_button() -> Button:
	return get_node_or_null("CenterContainer/MultiplayerButton") as Button

func _get_status_label() -> Label:
	return get_node_or_null("CenterContainer/StatusLabel") as Label

func _get_net_panel() -> Node:
	return get_node_or_null("NetPanel")

func _get_host_port_edit() -> LineEdit:
	return get_node_or_null("NetPanel/HostSection/HostPortEdit") as LineEdit

func _get_start_host_button() -> Button:
	return get_node_or_null("NetPanel/HostSection/StartHostButton") as Button

func _get_join_address_edit() -> LineEdit:
	return get_node_or_null("NetPanel/JoinSection/JoinAddressEdit") as LineEdit

func _get_join_port_edit() -> LineEdit:
	return get_node_or_null("NetPanel/JoinSection/JoinPortEdit") as LineEdit

func _get_start_join_button() -> Button:
	return get_node_or_null("NetPanel/JoinSection/StartJoinButton") as Button

func _get_back_button() -> Button:
	return get_node_or_null("NetPanel/BackButton") as Button
