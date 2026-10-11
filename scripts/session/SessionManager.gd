extends ServiceNode
# justified: on_ready() verbindet multiplayer.*-Signale (Node-Lifecycle erforderlich); hostet
# ENetMultiplayerPeer für die gesamte App-Laufzeit (überdauert Session-Wechsel — ADR-010).
class_name SessionManager

## SessionManager — Globaler Service für den Multiplayer-Peer-Lifecycle und Player-Slot-Registry.
##
## Verantwortlichkeiten:
##   - ENetMultiplayerPeer aufbauen (Host) oder verbinden (Client) vor dem Session-Boot.
##   - Player-Slot-Registry: peer_id (int) → player_id (String).
##   - Signale emittieren wenn Peers joinen / verlassen.
##   - NetworkBridge und die Session-Services sehen denselben multiplayer.multiplayer_peer —
##     kein separater Peer-State nötig.
##
## Drei-Tier-Modell (ADR-010):
##   Tier 1 — Solo:         Kein Peer gesetzt. has_active_peer() = false.
##   Tier 2 — Hosted Coop:  create_server() → Host ist Spieler und Autorität.
##   Tier 3 — Ded. Server:  create_server() auf Headless-Instanz; Host spielt nicht.
##
## Für Join-Flow: ServiceOrchestrator verbindet sich in _ready() auf
## EventBus.networking.joined_as_client und bootet automatisch eine Session
## für den Client.
##
## SessionManager nutzt IEventBus via DI (deps.get_optional(), null-safe — siehe
## configure()) — kein AutoLoad mehr. Der frühere Dep-Loop ("event_bus kommt erst
## in Phase 3.5") existierte nur unter der alten Zwei-Registry-Architektur. Nach
## dem Three-Scope-Refactor läuft SessionManager als regulärer App-Service durch
## boot_app() — EVENT_BUS ist als Resource bereits in Phase 3.5 registriert,
## bevor configure() (Phase 4) läuft.
##
## ADR-018-Rest (Runde 53): SessionManager hatte bisher zusätzlich zu den
## EventBus.networking()-Emits eigene, rohe Godot-Signale (peer_joined,
## peer_left, peer_cleanup_requested, server_started, client_connected_to_server,
## client_connection_failed, server_connection_lost, retry_attempt) — Doppel-
## Emission für denselben Sachverhalt, und zwei verbleibende Consumer
## (WorldService, ServiceOrchestrator) verbanden sich direkt auf diese
## Service-Instanz statt über den EventBus, was denselben Locator-artigen
## Kopplungsfehler reproduzierte, den ADR-018 für SystemEvents bereits gelöst
## hatte. Alle acht Signale sind entfernt; jeder Emissionspunkt läuft jetzt
## ausschließlich über `_bus.networking().emit_*()`. Tests verbinden sich
## dafür auf eine injizierte MockEventBus-Instanz, nicht mehr auf `self`.
##
## G-03 Reconnect/Timeout:
##   join_server() startet einen JOIN_TIMEOUT_SEC-Sekunden-Timer. Läuft er ab ohne Verbindung,
##   wird EventBus.networking().connection_to_server_failed emittiert und der Peer bereinigt.
##   Das verhindert hängende Verbindungsversuche ohne UI-Feedback.
##   join_server() unterstützt konfigurierbares Retry-Budget: max. MAX_RETRIES Versuche mit
##   exponentiell wachsender Wartezeit (RETRY_BASE_DELAY_SEC * 2^n).
##   _on_peer_disconnected() emittiert peer_cleanup_requested(peer_id) damit Services
##   Spieler-Buckets sichern und Chunk-Tracking bereinigen können.

const LOG_CAT       := "SessionManager"
const DEFAULT_PORT  := 7777
const MAX_CLIENTS   := 8
## BUGFIX (2026-09-13): bei ERR_ALREADY_IN_USE (Port belegt — verwaister
## Prozess, TIME_WAIT nach vorherigem Host-Lauf, o.ä.) automatisch auf
## die nächsten Ports ausweichen statt sofort generisch zu scheitern.
const PORT_RETRY_ATTEMPTS := 5

## ADR-010 Round 55 — Tier 3 (Dedizierter Server).
## Reservierte player_id für die vom Server selbst gehaltene "Welt-Session".
## KEIN Fake-Charakter: das ist eine echte, dauerhafte Save-Identität für die
## geteilte Welt (Terrain-Harvest-State, Quest-Fortschritt etc.), die
## unabhängig von jedem einzelnen menschlichen Spieler persistieren muss —
## siehe ADR-010 "Update (Round 55)". Bewusst kein Namensmuster, das mit
## echten Charakter-IDs ("charakterN") oder Client-Auto-IDs ("client_%d",
## siehe ServiceOrchestrator._on_client_connected()) kollidieren kann.
const DEDICATED_SERVER_WORLD_ID := "__dedicated_server_world__"

## G-03: Verbindungs-Timeout in Sekunden. ENet läuft ohne Obergrenze — dieser Timer
## beendet einen hängenden Verbindungsversuch sauber.
const JOIN_TIMEOUT_SEC   := 10.0
## G-03: Maximale Anzahl automatischer Retry-Versuche nach Connection-Failure.
## 0 = kein Auto-Retry (der Spieler muss manuell erneut versuchen).
const MAX_RETRIES        := 3
## G-03: Basis-Wartezeit zwischen Retries in Sekunden. Wird exponentiell verdoppelt.
const RETRY_BASE_DELAY_SEC := 1.0

## ADR-018-Rest: keine eigenen rohen Signale mehr — alle Lifecycle-Ereignisse
## laufen über `_bus.networking().emit_*()` (peer_joined, peer_left,
## peer_cleanup_requested, hosting_started, joined_as_client,
## connection_to_server_failed, network_peer_disconnected, retry_attempt).
## Siehe Klassenkommentar oben.

## BUGFIX (2026-09-14, "zwei Welten"): der für DIESE Welt gültige world_seed.
## Server: gesetzt in create_server(), BEVOR irgendein Charakter (Host oder
## Client) gewählt wurde. Client: gesetzt aus der Handshake-Antwort in
## _rpc_join_handshake_result() — übernimmt den Wert der Autorität, würfelt
## nie selbst. Tier 1 (Solo) bleibt bei 0 — WorldService fällt dort weiterhin
## auf lokale Zeit-basierte Generierung zurück (unverändertes Verhalten).
var _world_seed: int = 0

## peer_id (int) → player_id (String). Wird vom Server befüllt.
var _peer_slots: Dictionary = {}

## ADR-029 Phase 1: welche peer_ids den Join-Handshake bereits erfolgreich
## abgeschlossen haben — verhindert doppelte Verarbeitung (peer_id → true).
## Getrennt von _peer_slots, weil _peer_slots bei _on_peer_connected() sofort
## einen synthetischen Platzhalter ("peer_%d") bekommt, lange bevor ein
## Handshake überhaupt eintreffen kann — Presence in _peer_slots allein sagt
## also nichts darüber aus, ob der ECHTE Handshake schon gelaufen ist.
var _handshake_done: Dictionary = {}

## ADR-010 Round 55: true nur auf einer Headless-Instanz, die als Tier 3
## (Dedizierter Server) läuft — gesetzt von DedicatedServerBootstrap VOR
## create_server(), nie zur Laufzeit umgeschaltet. Unterscheidet Tier 2
## (Host spielt mit) von Tier 3 (Host spielt nicht) — beide nutzen
## denselben create_server()-Pfad, das Flag ist reine Deployment-Konfiguration,
## kein zweiter Code-Fork (siehe ADR-010 Kernentscheidung).
var _is_dedicated_server: bool = false

## G-03: Retry-State
var _join_address:    String = ""
var _join_port:       int    = DEFAULT_PORT
var _retry_count:     int    = 0
var _join_timer:      SceneTreeTimer = null  # Timeout-Timer für laufenden Join-Versuch
var _bus: IEventBus = null

## ADR-029 Phase 1: TOFU-Identitätsverifikation für den Join-Handshake.
## Eigene Datei, unabhängig von Charakter-Saves — siehe PlayerCredentialStore-
## Klassenkommentar ("Entscheidung Round 60") für die Begründung. Geladen
## einmalig in on_ready(), lange bevor ein Client verbinden kann.
var _credentials := PlayerCredentialStore.new()

## Test-Seam: erlaubt Unit-Tests, eine PlayerCredentialStore-Instanz mit
## Test-Pfad einzusetzen, BEVOR ein Handshake verarbeitet wird — sonst würde
## jeder Handshake-Test (verify_or_register() → save()) in die echte
## Produktionsdatei user://server_credentials.json schreiben. Nur für Tests
## gedacht, keine Produktions-Konfigurationsmöglichkeit (kein DI-Dep, kein
## ServiceKeys-Eintrag).
func set_credentials_for_testing(store: PlayerCredentialStore) -> void:
	_credentials = store

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	# BUG-FIX (analog BUG-24 / PlayerStateService): war fälschlich .require() —
	# widersprach SM-11 ("configure() ist no-op, kein Dep erforderlich") und
	# crashte in on_ready()/on_cleanup() mit "Nonexistent function 'system'
	# in base 'Nil'" sobald deps leer waren. Jetzt optional mit Null-Guards.
	_bus = deps.get_optional(ServiceKeys.EVENT_BUS) as IEventBus
	AppLogger.log_info("SessionManager konfiguriert mit IEventBus.", LOG_CAT)

func on_ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if is_instance_valid(_bus):
		_bus.networking().host_game_requested.connect(_on_host_game_requested)
		_bus.networking().join_game_requested.connect(_on_join_game_requested)
	else:
		AppLogger.log_warn("EventBus fehlt — host_/join_game_requested nicht verbunden.", LOG_CAT)
	_credentials.load()
	AppLogger.log_info("SessionManager bereit. Tier: %s" % _tier_name(), LOG_CAT)

func on_cleanup() -> void:
	_cancel_join_timer()
	_disconnect_multiplayer_signals()
	_disconnect_bus_signals()
	close()
	AppLogger.log_info("SessionManager cleanup.", LOG_CAT)

# ─────────────────────────────────────────────
# Host / Join API
# ─────────────────────────────────────────────

## Startet einen ENet-Host auf dem angegebenen Port.
## Tier 2 (Hosted Coop) oder Tier 3 (Dedicated Server).
## Gibt true zurück wenn erfolgreich.
func create_server(port: int = DEFAULT_PORT, max_clients: int = MAX_CLIENTS) -> bool:
	# BUGFIX (2026-09-14): ohne diese Guard versucht ein zweiter Host-Klick
	# (z.B. weil die UI den Multiplayer-Button in HOST_ACTIVE nicht
	# versteckt, siehe MainMenuController) denselben Port ERNEUT zu binden,
	# während der erste Peer ihn noch hält -> kryptisches 'Couldn't create
	# an ENet host' statt einer sprechenden Meldung. Siehe auch
	# REENTRANT_HOST_OR_JOIN_WHILE_PEER_ACTIVE in analyze_runtime_log.py.
	if _has_active_peer():
		AppLogger.log_warn(
			"create_server(%d) ignoriert — es läuft bereits ein aktiver Peer (peer_id %d)."
				% [port, multiplayer.get_unique_id()], LOG_CAT
		)
		return false
	var actual_port := port
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(actual_port, max_clients)
	var attempts := 1
	# BUGFIX (2026-09-13): Port evtl. noch von einem vorherigen Lauf belegt
	# (TIME_WAIT) oder von einem zuvor fehlgeschlagenen Join auf dieselbe
	# Adresse — bisher generischer Fehlschlag ohne Ausweichmöglichkeit.
	while err == ERR_ALREADY_IN_USE and attempts < PORT_RETRY_ATTEMPTS:
		attempts += 1
		AppLogger.log_warn(
			"Port %d belegt — versuche Port %d (%d/%d)."
				% [actual_port, actual_port + 1, attempts, PORT_RETRY_ATTEMPTS],
			LOG_CAT
		)
		actual_port += 1
		peer = ENetMultiplayerPeer.new()
		err = peer.create_server(actual_port, max_clients)
	if err != OK:
		AppLogger.log_error(
			"create_server(%d) fehlgeschlagen nach %d Versuch(en): %s"
				% [port, attempts, error_string(err)], LOG_CAT
		)
		return false
	multiplayer.multiplayer_peer = peer
	AppLogger.log_info(
		"Server gestartet auf Port %d (max. %d Clients)." % [actual_port, max_clients], LOG_CAT
	)
	# BUGFIX (2026-09-14, "zwei Welten"): world_seed MUSS beim Hosten erzeugt
	# werden, nicht erst wenn der Host selbst einen Charakter wählt und sein
	# WorldService bootet — ein Client kann (und tut es laut Log regelmäßig)
	# seinen Join-Handshake abschließen, BEVOR der Host überhaupt ein
	# WorldService/WorldData besitzt. Ohne einen hier bereits feststehenden
	# Seed hätte _handle_join_handshake() nichts, was es dem Client mitgeben
	# könnte, und jede Instanz würde weiterhin ihren eigenen
	# Time.get_unix_time_from_system()-Seed würfeln (siehe WorldSpawner/
	# WorldService) → unterschiedliches Terrain/Layout pro Peer, obwohl beide
	# "verbunden" sind.
	_world_seed = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	AppLogger.log_info("world_seed für diese Welt reserviert: %d." % _world_seed, LOG_CAT)
	if is_instance_valid(_bus):
		_bus.networking().emit_hosting_started(actual_port)
	else:
		AppLogger.log_warn("EventBus fehlt — hosting_started nicht emittiert.", LOG_CAT)
	return true

## Verbindet als Client mit einem Host.
## Gibt true zurück wenn die Verbindung EINGELEITET wurde (noch nicht hergestellt).
## G-03: Startet einen JOIN_TIMEOUT_SEC-Sekunden-Timer. Läuft er ab, wird die Verbindung
## abgebrochen und client_connection_failed emittiert.
## Auf Erfolg: client_connected_to_server Signal + _bus.networking().emit_joined_as_client().
func join_server(address: String, port: int = DEFAULT_PORT) -> bool:
	if address.is_empty():
		AppLogger.log_error("join_server(): leere Adresse — Verbindung abgelehnt.", LOG_CAT)
		return false
	# BUGFIX (2026-09-14): siehe create_server() — ein Join, während der
	# eigene Prozess bereits Host ist, ERSETZT multiplayer.multiplayer_peer
	# durch einen neuen Client-Peer und reißt damit den gerade laufenden
	# Server ein (der alte Server-Peer verliert seine letzte Referenz).
	if _has_active_peer():
		# HOTFIX (2026-09-14): die zwei String-Literale standen vorher ohne
		# '+' nebeneinander (Python-Gewohnheit) — GDScript konkateniert
		# adjazente String-Literale NICHT automatisch, das war ein Parse-
		# Fehler und hat SessionManager.gd komplett kompilierunfähig gemacht
		# (Boot-Pipeline-Totalausfall, 'Registrierte Keys: []' in GUT).
		AppLogger.log_warn(
			("join_server(%s:%d) ignoriert — es läuft bereits ein aktiver Peer (peer_id %d). "
				+ "close() aufrufen, um erst die aktuelle Session zu beenden.")
				% [address, port, multiplayer.get_unique_id()], LOG_CAT
		)
		return false

	_join_address = address
	_join_port    = port

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		AppLogger.log_error(
			"join_server(%s:%d) fehlgeschlagen: %s" % [address, port, error_string(err)], LOG_CAT
		)
		return false
	multiplayer.multiplayer_peer = peer

	# G-03: Timeout-Timer starten — verhindert hängenden Verbindungsversuch.
	_start_join_timer()

	AppLogger.log_info("Verbindung zu %s:%d eingeleitet (Timeout: %.0fs)." % [address, port, JOIN_TIMEOUT_SEC], LOG_CAT)
	return true

## Trennt Peer und kehrt zu Tier 1 (Solo) zurück.
func close() -> void:
	_cancel_join_timer()
	if _has_active_peer():
		multiplayer.multiplayer_peer = null
		AppLogger.log_info("Multiplayer-Peer geschlossen — zurück zu Tier 1 (Solo).", LOG_CAT)
	_peer_slots.clear()
	_retry_count = 0

# ─────────────────────────────────────────────
# Player-Slot-Registry
# ─────────────────────────────────────────────

## Registriert peer_id ↔ player_id. Wird von BootPipeline.boot_session() für den lokalen
## Spieler aufgerufen (Phase S8.7) und von _on_peer_connected() für Remote-Clients.
func register_player_slot(peer_id: int, player_id: String) -> void:
	_peer_slots[peer_id] = player_id
	AppLogger.log_debug(
		"Slot registriert: peer=%d → player='%s'" % [peer_id, player_id], LOG_CAT
	)

## Gibt die player_id für eine peer_id zurück. Leer wenn kein Slot bekannt.
func get_player_id_for_peer(peer_id: int) -> String:
	return _peer_slots.get(peer_id, "")

## Gibt eine Kopie aller bekannten Slots zurück.
func get_all_slots() -> Dictionary:
	return _peer_slots.duplicate()

## ADR-029 Plan-Schritt 4: player_id (String, stabile Save-Identität) DIESES
## laufenden Prozesses — Pendant zu get_local_peer_id() (int, Routing-Identität,
## ADR-015). Löst über denselben _peer_slots-Registry auf: die lokale peer_id
## ist für den eigenen Prozess immer registriert (BootPipeline.boot_character()
## Phase S8.7 ruft register_player_slot(get_local_peer_id(), player_id) für
## JEDEN Tier, inkl. Tier 1 — siehe dortigen Kommentar), ein separater
## Tier-1-Sonderfall ist deshalb hier nicht nötig.
##
## Leerer String nur wenn VOR Phase S8.7 aufgerufen (Boot-Reihenfolge-Fehler) —
## bewusst kein geratener Platzhalter-Wert, ein Aufrufer der das ignoriert
## würde sonst still einen falschen Bucket befüllen (siehe ADR-029
## "Kein Migrationscode" — derselbe Grundsatz wie bei InventorySystem's
## player_id ohne Default).
func get_local_player_id() -> String:
	var player_id := get_player_id_for_peer(get_local_peer_id())
	if player_id.is_empty():
		AppLogger.log_warn(
			"get_local_player_id(): kein Slot für lokale peer_id %d registriert — zu früh aufgerufen (vor BootPipeline Phase S8.7)?" % get_local_peer_id(),
			LOG_CAT
		)
	return player_id

## Rückwärts-Auflösung zu get_player_id_for_peer(): welcher (aktuell
## verbundene) Peer eine gegebene player_id gerade hält. Gebraucht für
## Rücksync-Routing (NetworkBridge.send_economy_update_for_player()) — dort
## ist die Zielidentität die stabile player_id, aber rpc_id() braucht die
## tatsächliche ENet-peer_id für das Transport-Routing (ADR-015 bleibt für
## den Routing-Teil zuständig, auch wenn die Absicht als player_id ankommt).
##
## -1 wenn player_id gerade keinem verbundenen Peer zugeordnet ist (z. B.
## Spieler offline) — 0 ist bewusst nicht der Sentinel, weil
## multiplayer.get_remote_sender_id() 0 als "kein Remote-Aufruf" nutzt und
## eine Verwechslung hier besonders leicht zu übersehen wäre.
func get_peer_id_for_player(player_id: String) -> int:
	for peer_id in _peer_slots:
		if _peer_slots[peer_id] == player_id:
			return peer_id
	return -1

## ADR-040: erster echter Aufrufer der seit ADR-031 bestehenden
## kick_player-Capability (bisher nur Stub). Trennt einen verbundenen Peer
## hart über ENet — kein sanftes "bitte trenne dich selbst"-RPC, da ein
## administrativ zu entfernender Client per Definition nicht vertrauenswürdig
## kooperativ sein muss. Nur auf der Autorität sinnvoll (is_server()); ein
## Client hat kein multiplayer_peer, über das er andere trennen könnte.
## Gibt false zurück, wenn player_id gerade keinem verbundenen Peer
## zugeordnet ist (z.B. bereits offline) oder dieser Prozess keine Autorität ist.
func kick_player(player_id: String) -> bool:
	if not is_server():
		AppLogger.log_warn("kick_player('%s') ignoriert — dieser Prozess ist keine Autorität." % player_id, LOG_CAT)
		return false
	var peer_id := get_peer_id_for_player(player_id)
	if peer_id <= 0:
		AppLogger.log_warn("kick_player('%s') — kein verbundener Peer gefunden." % player_id, LOG_CAT)
		return false
	if not is_instance_valid(multiplayer.multiplayer_peer):
		AppLogger.log_warn("kick_player('%s') — kein aktiver multiplayer_peer." % player_id, LOG_CAT)
		return false
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)
	AppLogger.log_info("Peer %d ('%s') administrativ getrennt (kick_player)." % [peer_id, player_id], LOG_CAT)
	return true

# ─────────────────────────────────────────────
# ADR-029 Phase 1: Join-Handshake
# ─────────────────────────────────────────────

## Client-seitig: nach Charakterauswahl im MainMenu aufgerufen (siehe geplante
## MainMenuController-Änderung, Checkliste-Punkt 4). Muss VOR dem eigentlichen
## Session-Boot laufen — der Client erfährt erst durch handshake_accepted/
## handshake_rejected (EventBus.networking), ob er weiterbooten darf.
func send_join_handshake(player_uuid: String, player_secret: String) -> void:
	if not _has_active_peer() or multiplayer.is_server():
		AppLogger.log_warn("send_join_handshake() ohne aktiven Client-Peer aufgerufen — ignoriert.", LOG_CAT)
		return
	rpc_id(1, "_rpc_join_handshake", player_uuid, player_secret)

## Server-Seite: Client beweist seine player_uuid (oder registriert sie beim
## ersten Kontakt, TOFU — siehe PlayerCredentialStore). Läuft hier statt auf
## NetworkBridge, weil NetworkBridge erst innerhalb einer bereits gebooteten
## CharacterScope existiert — der Handshake muss aber VOR der Charakterwahl
## laufen (siehe ADR-029 "Korrektur Round 59").
@rpc("any_peer", "call_remote", "reliable")
func _rpc_join_handshake(player_uuid: String, player_secret: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_handle_join_handshake(sender, player_uuid, player_secret)

## Testbare Kernlogik, getrennt von der @rpc-Hülle — analog zu
## NetworkBridge._is_rate_limited(rpc_name, peer_id), das denselben Grund hat:
## multiplayer.get_remote_sender_id() liefert außerhalb eines echten
## eingehenden RPC-Aufrufs immer 0, ein Unit-Test kann also nie einen
## "echten" Sender simulieren, wenn die Logik direkt in der @rpc-Methode steckt.
##
## Bewusst KEIN Rate-Limiting hier (anders als NetworkBridge._rpc_*, die
## _is_rate_limited() nutzen) — SessionManager hat diese Infrastruktur nicht,
## ein Duplizieren nur für einen Aufrufer war für Phase 1 nicht gerechtfertigt.
## _handshake_done verhindert Wiederholung NACH Erfolg, schützt aber nicht vor
## wiederholten FEHLGESCHLAGENEN Versuchen (kein Brute-Force-Risiko dank
## 128-Bit-Secret, aber ein Compute-/Log-Spam-Vektor). Als TODO vermerkt.
func _handle_join_handshake(sender: int, player_uuid: String, player_secret: String) -> void:
	if _handshake_done.has(sender):
		AppLogger.log_warn(
			"Handshake von peer %d, der bereits erfolgreich gehandshaked hat — ignoriert." % sender,
			LOG_CAT
		)
		return

	if _credentials.verify_or_register(player_uuid, player_secret):
		_handshake_done[sender] = true
		register_player_slot(sender, player_uuid)
		# Re-Emit mit der ECHTEN Identität — _on_peer_connected() hat beim rohen
		# ENet-Connect bereits einen synthetischen "peer_%d"-Platzhalter emittiert
		# (lange bevor ein Handshake überhaupt eintreffen konnte). Listener, die
		# den Platzhalter gecacht haben, bekommen hiermit die Korrektur.
		if is_instance_valid(_bus):
			_bus.networking().emit_peer_joined(sender, player_uuid)
		# BUGFIX (2026-09-14, "zwei Welten"): world_seed der Autorität mitschicken,
		# damit der Client seine WorldData damit initialisiert statt selbst einen
		# neuen Seed zu würfeln (siehe create_server()-Kommentar oben). _world_seed
		# ist hier nie mehr 0 — wird bereits beim Hosten reserviert.
		rpc_id(sender, "_rpc_join_handshake_result", true, "", _world_seed)
	else:
		rpc_id(sender, "_rpc_join_handshake_result", false, "Identität konnte nicht verifiziert werden.", 0)

## Client-Seite: Ergebnis des Handshakes. `@rpc("authority", ...)` — nur die
## Autorität darf das senden (Godot verweigert sonst), analog dem Muster bei
## _rpc_receive_initial_state() in NetworkBridge.
## world_seed: BUGFIX (2026-09-14, "zwei Welten") — der von der Autorität
## reservierte Seed dieser Welt. Wird übernommen, NIE lokal überschrieben,
## damit Host und Client dasselbe Terrain/Layout generieren.
@rpc("authority", "call_remote", "reliable")
func _rpc_join_handshake_result(accepted: bool, reason: String, world_seed: int = 0) -> void:
	if accepted:
		AppLogger.log_info("Join-Handshake akzeptiert.", LOG_CAT)
		if world_seed != 0:
			_world_seed = world_seed
			AppLogger.log_info("world_seed von Autorität übernommen: %d." % _world_seed, LOG_CAT)
	else:
		AppLogger.log_warn("Join-Handshake abgelehnt: %s" % reason, LOG_CAT)
	if is_instance_valid(_bus):
		_bus.networking().emit_join_handshake_result(accepted, reason, world_seed)

## BUGFIX (2026-09-14, "zwei Welten"): öffentlicher Zugriff für WorldService.configure() —
## liefert den von der Autorität reservierten Seed (Client/Host) oder 0 (Tier 1 Solo,
## oder Autorität hat noch keinen reserviert — sollte praktisch nie vorkommen, siehe
## create_server()). WorldService fällt bei 0 weiterhin auf lokale Zeit-Generierung zurück.
func get_world_seed() -> int:
	return _world_seed

# ─────────────────────────────────────────────
# Status-Helfer
# ─────────────────────────────────────────────

## true wenn ein echter ENet-Peer gesetzt ist (Tier 2 oder 3).
func has_active_peer() -> bool:
	return _has_active_peer()

## true wenn dieser Prozess Autorität ist (Solo oder Host).
func is_server() -> bool:
	return not _has_active_peer() or multiplayer.is_server()

## ADR-010 Round 55: von DedicatedServerBootstrap aufgerufen, bevor
## create_server() läuft. Muss VOR dem Hosten gesetzt sein — WorldService
## liest is_dedicated_server() beim Welt-Boot (Phase W2), um zu entscheiden,
## ob für den lokalen Peer ein Spieler-Entity gespawnt wird.
func enable_dedicated_server_mode() -> void:
	_is_dedicated_server = true
	AppLogger.log_info("Dedizierter-Server-Modus aktiviert (Tier 3).", LOG_CAT)

## true nur auf einer Headless-Instanz, die als Tier 3 (Dedizierter Server)
## läuft — nicht zu verwechseln mit is_server() (auch Tier 1/2 sind "Server"
## im Sinne von Autorität). Siehe ADR-010 "Update (Round 55)".
func is_dedicated_server() -> bool:
	return _is_dedicated_server

## true wenn kein Multiplayer-Peer aktiv ist (Tier 1 — Solo). Öffentlicher
## Wrapper um das private _has_active_peer(), gedacht für Aufrufer außerhalb
## dieser Klasse, die tier-abhängige Defaults setzen müssen (z.B. ADR-031
## "Rollenzuweisung nach Tier" — PermissionService.ensure_default_role()).
func is_solo() -> bool:
	return not _has_active_peer()

## Lokale peer_id. Ohne Peer immer 1.
func get_local_peer_id() -> int:
	return multiplayer.get_unique_id() if _has_active_peer() else 1

# ─────────────────────────────────────────────
# Multiplayer-Signal-Handler
# ─────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		# Clients bekommen peer_connected wenn der Server ihnen andere Clients bekannt gibt.
		# Wir führen hier keine eigene Slot-Registry auf Client-Seite.
		AppLogger.log_debug("Client: peer %d bekannt gegeben." % peer_id, LOG_CAT)
		return
	var player_id := "peer_%d" % peer_id
	register_player_slot(peer_id, player_id)
	AppLogger.log_info("Peer %d verbunden → '%s'." % [peer_id, player_id], LOG_CAT)
	if is_instance_valid(_bus):
		_bus.networking().emit_peer_joined(peer_id, player_id)
	else:
		AppLogger.log_warn("EventBus fehlt — peer_joined nicht emittiert.", LOG_CAT)

func _on_peer_disconnected(peer_id: int) -> void:
	_peer_slots.erase(peer_id)
	_handshake_done.erase(peer_id)
	AppLogger.log_info("Peer %d getrennt." % peer_id, LOG_CAT)
	# G-03: Services informieren dass Ressourcen für diesen Peer bereinigt werden sollen.
	# InventorySystem/QuestService/SkillSystem können Spieler-Buckets sichern;
	# WorldService/ChunkManager entfernen den Spieler aus dem Tracking.
	# peer_cleanup_requested muss vor peer_left emittiert werden (siehe Test).
	if is_instance_valid(_bus):
		_bus.networking().emit_peer_cleanup_requested(peer_id)
		_bus.networking().emit_peer_left(peer_id)
	else:
		AppLogger.log_warn(
			"EventBus fehlt — peer_cleanup_requested/peer_left nicht emittiert.", LOG_CAT
		)

func _on_connected_to_server() -> void:
	# G-03: Verbindung hergestellt — Timer und Retry-Zähler zurücksetzen.
	_cancel_join_timer()
	_retry_count = 0
	var local_id := multiplayer.get_unique_id()
	AppLogger.log_info("Mit Server verbunden. Lokale peer_id: %d" % local_id, LOG_CAT)
	if is_instance_valid(_bus):
		_bus.networking().emit_joined_as_client()
	else:
		AppLogger.log_warn("EventBus fehlt — joined_as_client nicht emittiert.", LOG_CAT)

func _on_connection_failed() -> void:
	_cancel_join_timer()
	AppLogger.log_error("Verbindung zum Server fehlgeschlagen (Versuch %d/%d)." % [_retry_count + 1, MAX_RETRIES + 1], LOG_CAT)
	# Fehlgeschlagenen Peer bereinigen.
	if _has_active_peer():
		multiplayer.multiplayer_peer = null

	if _retry_count < MAX_RETRIES and not _join_address.is_empty():
		_retry_count += 1
		var delay := RETRY_BASE_DELAY_SEC * pow(2.0, _retry_count - 1)
		AppLogger.log_info(
			"Retry %d/%d in %.1f Sekunden..." % [_retry_count, MAX_RETRIES, delay], LOG_CAT
		)
		if is_instance_valid(_bus):
			_bus.networking().emit_retry_attempt(_retry_count, MAX_RETRIES)
		else:
			AppLogger.log_warn("EventBus fehlt — retry_attempt nicht emittiert.", LOG_CAT)
		get_tree().create_timer(delay).timeout.connect(
			func() -> void: join_server(_join_address, _join_port),
			CONNECT_ONE_SHOT
		)
	else:
		_retry_count = 0
		if is_instance_valid(_bus):
			_bus.networking().emit_connection_to_server_failed()
		else:
			AppLogger.log_warn("EventBus fehlt — connection_to_server_failed nicht emittiert.", LOG_CAT)

func _on_server_disconnected() -> void:
	AppLogger.log_warn("Server-Verbindung verloren.", LOG_CAT)
	close()
	if is_instance_valid(_bus):
		_bus.networking().emit_network_peer_disconnected()
	else:
		AppLogger.log_warn("EventBus fehlt — network_peer_disconnected nicht emittiert.", LOG_CAT)

# ─────────────────────────────────────────────
# G-03: Join-Timeout-Helpers
# ─────────────────────────────────────────────

func _start_join_timer() -> void:
	_cancel_join_timer()
	_join_timer = get_tree().create_timer(JOIN_TIMEOUT_SEC)
	_join_timer.timeout.connect(_on_join_timeout, CONNECT_ONE_SHOT)

func _cancel_join_timer() -> void:
	if is_instance_valid(_join_timer):
		if _join_timer.timeout.is_connected(_on_join_timeout):
			_join_timer.timeout.disconnect(_on_join_timeout)
	_join_timer = null

func _on_join_timeout() -> void:
	_join_timer = null
	if not _has_active_peer():
		return  # Verbindung wurde inzwischen hergestellt oder bereits abgebrochen.
	AppLogger.log_warn(
		"Verbindungs-Timeout nach %.0f Sekunden — Peer wird bereinigt." % JOIN_TIMEOUT_SEC,
		LOG_CAT
	)
	multiplayer.multiplayer_peer = null
	if is_instance_valid(_bus):
		_bus.networking().emit_connection_to_server_failed()
	else:
		AppLogger.log_warn("EventBus fehlt — connection_to_server_failed nicht emittiert.", LOG_CAT)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _has_active_peer() -> bool:
	if not is_instance_valid(multiplayer):
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	var peer := multiplayer.multiplayer_peer
	return is_instance_valid(peer) and peer.get_class() != "OfflineMultiplayerPeer"

func _tier_name() -> String:
	if not _has_active_peer():
		return "Tier 1 (Solo)"
	if multiplayer.is_server():
		return "Tier 3 (Dedizierter Server)" if _is_dedicated_server else "Tier 2 (Hosted Coop — Host)"
	return "Tier 2/3 (Client)"

func _disconnect_multiplayer_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)

func _disconnect_bus_signals() -> void:
	if not is_instance_valid(_bus):
		return
	if _bus.networking().host_game_requested.is_connected(_on_host_game_requested):
		_bus.networking().host_game_requested.disconnect(_on_host_game_requested)
	if _bus.networking().join_game_requested.is_connected(_on_join_game_requested):
		_bus.networking().join_game_requested.disconnect(_on_join_game_requested)

func _on_host_game_requested(port: int) -> void:
	create_server(port)

func _on_join_game_requested(address: String, port: int) -> void:
	join_server(address, port)
