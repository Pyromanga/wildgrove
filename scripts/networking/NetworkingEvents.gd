class_name NetworkingEvents extends BaseEvents

## NetworkingEvents — EventBus-Namespace für Netzwerk-Lifecycle-Signale
## (ADR-010 / Sprint B).
##
## ADR-018: Aus SystemEvents herausgelöst. Gehört fachlich zu
## scripts/networking/ (wo NetworkBridge bereits lebt), nicht in den
## domänenlosen eventbus/-Ordner.
##
## Einbinden in EventBus.gd:
##   var networking: NetworkingEvents
##   # in _ready():
##   networking = NetworkingEvents.new()
##
## Verwendung:
##   EventBus.networking.hosting_started.connect(_on_hosting_started)
##   EventBus.networking.emit_host_game_requested(7777)

## Emittiert von MainMenuController wenn der Spieler einen Host starten möchte.
## SessionManager lauscht hierauf und ruft create_server(port) auf.
signal host_game_requested(port: int)
## Emittiert von MainMenuController wenn der Spieler einem Server beitreten möchte.
## SessionManager lauscht hierauf und ruft join_server(address, port) auf.
signal join_game_requested(address: String, port: int)
## Emittiert von SessionManager wenn der Server erfolgreich gestartet wurde.
signal hosting_started(port: int)
## Emittiert von SessionManager wenn dieser Client erfolgreich verbunden wurde.
## ServiceOrchestrator lauscht hierauf und bootet automatisch die Client-Session.
signal joined_as_client()
## Emittiert von SessionManager wenn der Verbindungsversuch fehlschlug.
signal connection_to_server_failed()
## Emittiert von SessionManager wenn die Server-Verbindung verloren ging.
signal network_peer_disconnected()
## Emittiert von SessionManager wenn ein Client-Peer verbunden und im
## Slot-Register eingetragen wurde (nur auf dem Server/Host).
signal peer_joined(peer_id: int, player_id: String)
## Emittiert von SessionManager wenn ein Peer getrennt und aus dem
## Slot-Register entfernt wurde.
signal peer_left(peer_id: int)
## Emittiert von SessionManager VOR peer_left, wenn Services Ressourcen für
## peer_id bereinigen sollen (Spieler-Buckets sichern, Chunk-Tracking etc.).
signal peer_cleanup_requested(peer_id: int)
## Emittiert von SessionManager wenn ein automatischer Reconnect-Versuch
## nach einem gescheiterten join_server() gestartet wird.
signal retry_attempt(attempt: int, max_attempts: int)
## ADR-029 Phase 1: Emittiert von SessionManager (Client-Seite), wenn das
## Ergebnis des Join-Handshakes eintrifft — `accepted=false` mit `reason`
## bei TOFU-Ablehnung (Secret-Mismatch, siehe PlayerCredentialStore).
## world_seed: BUGFIX (2026-09-14, "zwei Welten") — der von der Autorität
## reservierte world_seed, bei accepted=false immer 0 (irrelevant).
signal join_handshake_result(accepted: bool, reason: String, world_seed: int)

func _init() -> void:
	super._init("Events/Networking")

func emit_host_game_requested(port: int) -> void:
	_log_info("Host angefordert auf Port %d." % port)
	host_game_requested.emit(port)

func emit_join_game_requested(address: String, port: int) -> void:
	_log_info("Join angefordert: %s:%d" % [address, port])
	join_game_requested.emit(address, port)

func emit_hosting_started(port: int) -> void:
	_log_info("Server gestartet auf Port %d." % port)
	hosting_started.emit(port)

func emit_joined_as_client() -> void:
	_log_info("Client erfolgreich mit Server verbunden.")
	joined_as_client.emit()

func emit_connection_to_server_failed() -> void:
	_log_warn("Verbindung zum Server fehlgeschlagen.")
	connection_to_server_failed.emit()

func emit_network_peer_disconnected() -> void:
	_log_warn("Netzwerkverbindung verloren.")
	network_peer_disconnected.emit()

func emit_peer_joined(peer_id: int, player_id: String) -> void:
	_log_info("Peer %d beigetreten → '%s'." % [peer_id, player_id])
	peer_joined.emit(peer_id, player_id)

func emit_peer_left(peer_id: int) -> void:
	_log_info("Peer %d verlassen." % peer_id)
	peer_left.emit(peer_id)

func emit_join_handshake_result(accepted: bool, reason: String, world_seed: int = 0) -> void:
	if accepted:
		_log_info("Join-Handshake akzeptiert.")
	else:
		_log_warn("Join-Handshake abgelehnt: %s" % reason)
	join_handshake_result.emit(accepted, reason, world_seed)

func emit_peer_cleanup_requested(peer_id: int) -> void:
	_log_info("Cleanup angefordert für Peer %d." % peer_id)
	peer_cleanup_requested.emit(peer_id)

func emit_retry_attempt(attempt: int, max_attempts: int) -> void:
	_log_info("Reconnect-Versuch %d/%d." % [attempt, max_attempts])
	retry_attempt.emit(attempt, max_attempts)
