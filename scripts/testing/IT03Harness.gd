extends Node
# justified: Autoload, weil es vor jedem Boot-Signal (services_initialized) verbunden
# sein muss und über die App-Laufzeit hinweg lebt — exakt derselbe Grund wie bei
# SimpleTerminal. NICHT Teil des produktiven Gameplay-Codepfads.

## IT03Harness — CI-only Zwei-Prozess-Treiber für IT-03 (docs/adr/025-…,
## docs/adr/026-…, siehe tests/integration/test_movement_two_peer.gd Kopfkommentar
## für den historischen Kontext "IT-03 noch nicht implementiert").
##
## Aktivierung NUR über User-Cmdline-Argumente (OS.get_cmdline_user_args(), alles
## nach "--"):
##   --it03-server                    Rolle: Host. Startet SessionManager.create_server()
##                                     auf --it03-port (Default 38214), bootet eine eigene
##                                     Session ("it03-host") und bleibt am Leben bis
##                                     IT03_MAX_LIFETIME_SEC verstrichen sind (Fallback —
##                                     die CI-Pipeline killt den Prozess normalerweise
##                                     früher, sobald der Client fertig ist).
##   --it03-client                    Rolle: Client. Verbindet via SessionManager.join_server()
##                                     zu --it03-connect (Default 127.0.0.1:38214), durchläuft
##                                     danach den ECHTEN ADR-029-Phase-1-Client-Flow (kein
##                                     Auto-Boot mehr!): Charakter-Identität laden/erzeugen →
##                                     send_join_handshake() → bei join_handshake_result
##                                     (accepted) → emit_session_requested() → erst dann
##                                     bootet der Client seinen CharacterScope mit eigenem
##                                     Player-Node. Danach pollt get_last_processed_input_seq()
##                                     bis ein Schwellwert überschritten wird (echte
##                                     Bestätigung, dass ein vom Client gesendeter Input die
##                                     Autorität erreicht, dort verarbeitet und zurückrepliziert
##                                     wurde). Beendet sich selbst mit Exit-Code 0 (PASS) oder
##                                     1 (FAIL/Timeout) — das ist der Signal-Kanal an die CI.
##   --it03-port=<int>                Nur Server-Rolle.
##   --it03-connect=<host:port>       Nur Client-Rolle.
##
## Ohne eines dieser Argumente: _ready() kehrt sofort zurück, kein Verhalten geändert.
## Kosten in Produktion: ein Array-Scan über die (leeren) Cmdline-User-Args.
##
## FIX (2026-10-11, "IT-03 war nie grün"): der Client wartete bisher nach
## joined_as_client direkt auf sein Player-Node — seit ADR-029 Phase 1 (Round 62)
## bootet der Client nach dem rohen ENet-Connect aber NICHT mehr automatisch.
## MainMenuController._on_joined_as_client() zeigt nur die Charakter-Auswahl;
## gebootet wird erst nach send_join_handshake() + akzeptiertem
## join_handshake_result + emit_session_requested(). Das alte Harness übersprang
## diese komplette Kette → kein CharacterScope, kein WorldService, kein
## Player-Node → Timeout nach 60s → Exit 1. Jetzt durchläuft das Harness exakt
## dieselbe Sequenz wie MainMenuController._start_join_handshake() /
## _on_join_handshake_result() (siehe dort), nur ohne UI.
##
## EINSCHRÄNKUNG (Round 113 Nachtrag): dieser Harness emittiert
## session_requested DIREKT über den EventBus — nicht über den echten
## "Neues Spiel"/"Host"-Button im MainMenu. Er testet Netzwerk-Replikation
## (Input-Sync Host↔Client), NICHT den UI→Boot→Szenenwechsel-Pfad. Ein realer
## Bug in genau diesem Pfad (MainMenuController ohne IAppContext, dann
## SceneManager.STATE_SCENE_MAP mit falschem State→Szene-Mapping) wäre von
## IT-03 NICHT gefangen worden — siehe tests/integration/test_new_game_boot_flow.gd
## für die entsprechende Abdeckung des echten UI-Pfads.
##
## WICHTIG — was dieser Test NICHT synthetisiert: er ruft niemals selbst
## NetworkBridge.submit_movement_input() auf. Das eigene Player-Node des Clients
## sendet bereits organisch, jeden Physik-Tick, echten Input über
## Player._loop_free_predicted() (input.js_vec ist im Headless-Modus ohne echtes
## Eingabegerät zwar Vector2.ZERO, aber seq/RPC/Replikation laufen trotzdem exakt
## wie im echten Spiel). Der Test wartet nur darauf, dass diese bereits laufende,
## reale Kette einmal sichtbar durchläuft — kein Test-Sonderpfad im Gameplay-Code.

const LOG_CAT := "IT03Harness"

## Wie viele erfolgreich verarbeitete Input-Ticks als Beleg gelten — bewusst > 1,
## damit ein einzelner Zufallstreffer (z.B. Replikations-Rest von einer anderen
## Quelle) nicht ausreicht. 5 Ticks bei 20Hz-Sync-Rate sind < 1s Realzeit.
const SEQ_THRESHOLD := 5
const DEFAULT_PORT := 38214
const CONNECT_TIMEOUT_SEC := 30.0
## FIX (2026-10-11): Timeout für den Join-Handshake (Client-Rolle). Der Server
## antwortet synchron in _handle_join_handshake() — wenn binnen 15s kein
## join_handshake_result ankommt, ist die Kette woanders hängen geblieben und
## ein längeres Warten verbraucht nur Runner-Zeit.
const HANDSHAKE_TIMEOUT_SEC := 15.0
const PLAYER_SPAWN_TIMEOUT_SEC := 60.0
const SEQ_TIMEOUT_SEC := 20.0
const IT03_MAX_LIFETIME_SEC := 120.0  # Server-Fallback-Selbstabschaltung.

## Client-seitige Charakter-ID für den Join-Flow. Muss KEIN existierender Save
## sein — SaveSystem.begin_session() erzeugt bei Erstkontakt eine neue Identität
## (player_uuid/player_secret), exakt wie bei einem neuen Charakter im
## Hauptmenü (MainMenuController._on_new_game_pressed() → _start_join_handshake()).
const CLIENT_PLAYER_ID := "it03-client"

var _role: String = ""  # "server" | "client" | ""
var _port: int = DEFAULT_PORT
var _connect_host: String = "127.0.0.1"
var _connect_port: int = DEFAULT_PORT

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--it03-server":
			_role = "server"
		elif a == "--it03-client":
			_role = "client"
		elif a.begins_with("--it03-port="):
			_port = int(a.substr(len("--it03-port=")))
		elif a.begins_with("--it03-connect="):
			var raw := a.substr(len("--it03-connect="))
			var parts := raw.split(":")
			if parts.size() == 2:
				_connect_host = parts[0]
				_connect_port = int(parts[1])

	if _role == "":
		return  # Normales Spiel — kein Verhalten geändert.

	AppLogger.log_info("IT03Harness aktiv. Rolle=%s" % _role, LOG_CAT)
	if EventBus.system.services_initialized.is_connected(_on_services_ready):
		return
	EventBus.system.services_initialized.connect(_on_services_ready, CONNECT_ONE_SHOT)

func _on_services_ready() -> void:
	if _role == "server":
		_run_server()
	else:
		_run_client()

# ─────────────────────────────────────────────
# Server-Rolle
# ─────────────────────────────────────────────

func _run_server() -> void:
	EventBus.networking.hosting_started.connect(_on_hosting_started, CONNECT_ONE_SHOT)
	AppLogger.log_info("IT03: fordere Host auf Port %d an." % _port, LOG_CAT)
	EventBus.networking.emit_host_game_requested(_port)
	# Fallback-Selbstabschaltung — die CI-Pipeline killt den Prozess normalerweise
	# selbst, sobald der Client-Prozess fertig ist, aber ein Server, der aus
	# irgendeinem Grund nie ein Kill-Signal bekommt, soll den Runner nicht ewig
	# blockieren (Job hat ohnehin ein eigenes timeout-minutes, das ist nur Defense
	# in Depth).
	await get_tree().create_timer(IT03_MAX_LIFETIME_SEC).timeout
	AppLogger.log_info("IT03: Server-Fallback-Lifetime erreicht — beende.", LOG_CAT)
	get_tree().quit(0)

func _on_hosting_started(port: int) -> void:
	AppLogger.log_info("IT03: hosting_started(%d) — boote eigene Session." % port, LOG_CAT)
	EventBus.session.emit_session_requested("it03-host")

# ─────────────────────────────────────────────
# Client-Rolle
# ─────────────────────────────────────────────

func _run_client() -> void:
	EventBus.networking.connection_to_server_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	AppLogger.log_info(
		"IT03: verbinde zu %s:%d." % [_connect_host, _connect_port], LOG_CAT
	)
	EventBus.networking.emit_join_game_requested(_connect_host, _connect_port)

	var connected := await _wait_for_signal(
		EventBus.networking.joined_as_client, CONNECT_TIMEOUT_SEC
	)
	if not connected:
		_fail("Verbindung zum Server nicht innerhalb von %.0fs zustande gekommen." % CONNECT_TIMEOUT_SEC)
		return

	var orch := get_node("/root/ServiceOrchestrator")
	var session_mgr := orch.get_service(ServiceKeys.SESSION_MANAGER) as SessionManager
	if session_mgr == null:
		_fail("SessionManager nicht verfügbar nach Verbindung.")
		return

	# FIX (2026-10-11): ECHTEN ADR-029-Join-Flow durchlaufen. Seit Round 62
	# bootet der Client nach joined_as_client nicht mehr automatisch — die
	# komplette Handshake-Kette (MainMenuController._start_join_handshake()
	# + _on_join_handshake_result()) muss hier ohne UI nachgebaut werden,
	# sonst existieren auf dem Client nie CharacterScope/WorldService/
	# Player-Node und die alte _wait_for_player_node()-Schleife lief immer
	# in ihren 60s-Timeout (das war der IT-03-Fail-Modus).
	AppLogger.log_info("IT03: verbunden — führe Join-Handshake aus (ADR-029 Phase 1).", LOG_CAT)
	var save_system := orch.get_service(ServiceKeys.SAVE_SYSTEM) as SaveSystem
	if save_system == null:
		_fail("SaveSystem nicht verfügbar nach Verbindung.")
		return

	save_system.begin_session(CLIENT_PLAYER_ID)
	var uuid := save_system.get_active_player_uuid()
	var secret := save_system.get_active_player_secret()
	if uuid.is_empty() or secret.is_empty():
		_fail("player_uuid/player_secret für '%s' konnten nicht geladen/erzeugt werden." % CLIENT_PLAYER_ID)
		return

	# Dictionary statt erfasster Lokaler (GDScript-Lambdas kopieren äußere
	# Locals als Wert) — siehe _wait_for_signal() für denselben Grund.
	var hs := {"done": false, "accepted": false}
	var on_result := func(accepted: bool, _reason: String, _world_seed: int) -> void:
		hs["done"] = true
		hs["accepted"] = accepted
	EventBus.networking.join_handshake_result.connect(on_result, CONNECT_ONE_SHOT)
	session_mgr.send_join_handshake(uuid, secret)

	var hs_elapsed := 0.0
	while not hs["done"] and hs_elapsed < HANDSHAKE_TIMEOUT_SEC:
		await get_tree().create_timer(0.1).timeout
		hs_elapsed += 0.1
	if EventBus.networking.join_handshake_result.is_connected(on_result):
		EventBus.networking.join_handshake_result.disconnect(on_result)
	if not hs["done"] or not hs["accepted"]:
		_fail("Join-Handshake nicht innerhalb von %.0fs akzeptiert." % HANDSHAKE_TIMEOUT_SEC)
		return
	AppLogger.log_info(
		"IT03: Handshake akzeptiert — fordere Session für '%s' an." % CLIENT_PLAYER_ID, LOG_CAT
	)

	# Erst NACH akzeptiertem Handshake session_requested emittieren — exakt wie
	# MainMenuController._on_join_handshake_result() im echten Spiel.
	EventBus.session.emit_session_requested(CLIENT_PLAYER_ID)

	var local_peer_id: int = session_mgr.get_local_peer_id()

	var player_node := await _wait_for_player_node(orch, local_peer_id, PLAYER_SPAWN_TIMEOUT_SEC)
	if player_node == null:
		_fail("Eigenes Player-Node nicht innerhalb von %.0fs gefunden (peer_id=%d)." % [
			PLAYER_SPAWN_TIMEOUT_SEC, local_peer_id
		])
		return
	AppLogger.log_info("IT03: Player-Node gefunden. Warte auf server-bestätigten Input.", LOG_CAT)

	var reached := await _wait_for_seq_threshold(player_node, SEQ_THRESHOLD, SEQ_TIMEOUT_SEC)
	if not reached:
		var last: int = _read_seq(player_node)
		_fail(
			"last_processed_input_seq erreichte nie %d innerhalb von %.0fs (letzter Wert: %d)." % [
				SEQ_THRESHOLD, SEQ_TIMEOUT_SEC, last
			]
		)
		return

	AppLogger.log_info(
		"IT03_RESULT: PASS — echter Movement-Input-Round-Trip bestätigt (seq >= %d)." % SEQ_THRESHOLD,
		LOG_CAT
	)
	get_tree().quit(0)

func _on_connection_failed() -> void:
	_fail("EventBus.networking.connection_to_server_failed empfangen.")

func _fail(reason: String) -> void:
	AppLogger.log_error("IT03_RESULT: FAIL — %s" % reason, LOG_CAT)
	get_tree().quit(1)

# ─────────────────────────────────────────────
# Poll-Hilfsfunktionen
# ─────────────────────────────────────────────

func _wait_for_signal(sig: Signal, timeout_sec: float) -> bool:
	# Dictionary statt einer erfassten lokalen bool-Variable: GDScript-Lambdas
	# erfassen äußere Locals als Wert-Kopie zum Erstellungszeitpunkt, nicht als
	# lebende Referenz — eine Zuweisung in der Lambda selbst wäre für die
	# äußere Polling-Schleife unsichtbar. Dictionary/Array sind Referenztypen,
	# eine Mutation darin ist von außen sichtbar.
	var box := {"done": false}
	var on_fired := func() -> void: box["done"] = true
	sig.connect(on_fired, CONNECT_ONE_SHOT)
	var elapsed := 0.0
	while not box["done"] and elapsed < timeout_sec:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	if sig.is_connected(on_fired):
		sig.disconnect(on_fired)
	return box["done"]

func _wait_for_player_node(orch: Object, local_peer_id: int, timeout_sec: float) -> Node3D:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		var world := orch.get_service(ServiceKeys.WORLD) as WorldService
		if world != null:
			var node := world.get_player_by_id(local_peer_id)
			if is_instance_valid(node):
				return node
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25
	return null

func _wait_for_seq_threshold(player_node: Node3D, threshold: int, timeout_sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		if not is_instance_valid(player_node):
			return false
		if _read_seq(player_node) >= threshold:
			return true
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	return false

## player_node kommt aus WorldService.get_player_by_id(), typisiert als Node3D
## (nicht Player) — derselbe Grund, aus dem WorldService.route_movement_input()
## bereits has_method()+call() statt eines direkten typisierten Aufrufs nutzt.
func _read_seq(player_node: Node3D) -> int:
	if player_node.has_method("get_last_processed_input_seq"):
		return player_node.call("get_last_processed_input_seq")
	return -1
