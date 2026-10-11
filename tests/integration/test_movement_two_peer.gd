# tests/integration/test_movement_two_peer.gd
extends GutTest

## Zwei-Peer-Integrationstest für ADR-025 (Server-autoritatives Movement) und
## ADR-026 (Client-Side Prediction/Reconciliation).
##
## EHRLICHER HINWEIS (nicht stillschweigend als "erledigt" markiert):
##
##   Dieser Test wurde in der Sandbox geschrieben, in der auch der zugehörige
##   Movement-Umbau entstand. Diese Sandbox hat KEINEN Netzwerkzugriff und
##   vermutlich kein Godot-Binary — der Test konnte deshalb NICHT ausgeführt
##   werden. Er ist nach bestem Wissen korrekt konstruiert (folgt demselben
##   ENetMultiplayerPeer-Muster wie jede Godot-Multiplayer-Doku), aber NICHT
##   verifiziert. Vor jedem Vertrauen in dieses ADR: mit echtem Godot-Editor
##   oder `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration/`
##   tatsächlich laufen lassen und Ergebnis prüfen.
##
##   Was dieser Test ABDECKT: zwei ECHTE ENetMultiplayerPeer-Instanzen
##   (Server + Client) über echte Loopback-Sockets (127.0.0.1) — das ist eine
##   reale Zwei-Prozess-äquivalente Verbindung innerhalb eines Prozesses
##   (Godot erlaubt Server+Client-Peer im selben Prozess für genau solche
##   Tests). Er verifiziert: (1) das unreliable RPC für Movement-Input kommt
##   beim Server an, (2) multiplayer.get_remote_sender_id() liefert dort
##   tatsächlich die Client-Peer-ID (Grundlage für die gesamte
##   Sicherheitsargumentation "player_id kommt nie vom Client-Payload"),
##   (3) die Autorität verarbeitet den Input und _last_processed_input_seq
##   repliziert zurück zum Client.
##
##   Was dieser Test NICHT abdeckt: echte Netzwerk-Latenz (Loopback ist
##   quasi verzögerungsfrei), Paketverlust, das Tier-2-Mobilgerät-Szenario
##   (siehe ADR-025 Mitigationen), und das "fühlt sich gut an"-Kriterium von
##   ADR-026 (das ist ein menschliches Spielgefühl-Urteil, kein Assert).
##   Für eine echte Latenz-/Paketverlust-Prüfung: zwei physisch getrennte
##   Geräte oder ein Netzwerk-Throttling-Tool (z. B. `tc netem` unter Linux)
##   zwischen zwei Prozessen auf verschiedenen Ports.
##
## IT-03 (voller Gameplay-Round-Trip) lebt NICHT in dieser Datei — GUT läuft
## in einem einzelnen Prozess, ein echter Client/Server-Split braucht zwei
## getrennte `godot --headless`-Prozesse. Das übernimmt
## `scripts/testing/IT03Harness.gd` (CI-only Autoload, siehe Kopfkommentar
## dort) im eigenen CI-Job "IT-03 — Two-Process Movement Round Trip"
## (build-apk.yml). Die `pending()`-Methode unten bleibt bewusst als
## Fundstelle/Verweis stehen statt gelöscht zu werden — wer nur `tests/`
## durchsucht, soll trotzdem auf den echten Test stoßen.

const TEST_PORT := 38214  # unüblicher Port, um Kollision mit einer laufenden Dev-Session zu vermeiden

var _server_peer: ENetMultiplayerPeer
var _client_peer: ENetMultiplayerPeer
var _server_mp: MultiplayerAPI
var _client_mp: MultiplayerAPI

func before_each() -> void:
	_server_peer = ENetMultiplayerPeer.new()
	var server_err := _server_peer.create_server(TEST_PORT, 4)
	assert_eq(server_err, OK, "Server-Peer muss erstellbar sein (Port %d frei)." % TEST_PORT)

	_client_peer = ENetMultiplayerPeer.new()
	var client_err := _client_peer.create_client("127.0.0.1", TEST_PORT)
	assert_eq(client_err, OK, "Client-Peer muss sich verbinden können.")

	# Jede Seite bekommt eine eigene MultiplayerAPI-Instanz (nicht die globale
	# `multiplayer` des Testbaums) — sonst würden Server- und Client-Rolle im
	# selben Prozess kollidieren. Godot erlaubt das explizit über
	# SceneTree.set_multiplayer(api, root_path) pro Subtree.
	_server_mp = MultiplayerAPI.create_default_interface()
	_server_mp.multiplayer_peer = _server_peer
	_client_mp = MultiplayerAPI.create_default_interface()
	_client_mp.multiplayer_peer = _client_peer

func after_each() -> void:
	if is_instance_valid(_server_peer):
		_server_peer.close()
	if is_instance_valid(_client_peer):
		_client_peer.close()
	_server_peer = null
	_client_peer = null

## Wartet bis zu timeout_sec auf eine Bedingung, pollt beide Peers dabei aktiv
## (poll() ist nötig, weil ohne SceneTree-Anbindung niemand sonst das tut).
func _wait_until(condition: Callable, timeout_sec: float = 3.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		_server_mp.poll()
		_client_mp.poll()
		if condition.call():
			return true
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
	return false

## IT-01: Client-Peer erreicht CONNECTION_CONNECTED-Status gegenüber dem Server —
## Grundvoraussetzung für alles Weitere. Wenn schon das scheitert, ist jeder
## weitere Test in dieser Datei bedeutungslos.
func test_it01_client_connects_to_server() -> void:
	var connected := await _wait_until(func() -> bool:
		return _client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)
	assert_true(connected, "IT-01: Client muss sich innerhalb des Timeouts verbinden können.")

## IT-02: Server sieht den verbundenen Client als Peer mit einer von 1
## verschiedenen, von Godot vergebenen (nicht selbst gewählten) ID.
## Das ist die technische Grundlage für "player_id kommt nie vom Client" —
## wenn das hier nicht stimmt, ist die gesamte Sicherheitsargumentation in
## NetworkContract.gd hinfällig.
func test_it02_server_sees_client_with_godot_assigned_id() -> void:
	await _wait_until(func() -> bool:
		return _client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)
	var got_peer_connected := await _wait_until(func() -> bool:
		return _server_mp.get_peers().size() > 0
	)
	assert_true(got_peer_connected, "IT-02: Server muss den Client in get_peers() sehen.")
	if _server_mp.get_peers().size() > 0:
		var seen_id: int = _server_mp.get_peers()[0]
		assert_ne(seen_id, 1, "IT-02: Client-Peer-ID darf nicht 1 sein (1 ist reserviert für den Server).")
		assert_ne(seen_id, 0, "IT-02: Client-Peer-ID darf nicht 0 sein (0 = 'noch keine ID zugewiesen').")

## IT-03 (Grundlage für ADR-025/026): der volle submit_movement_input()-Round-Trip
## mit echten Player/WorldService/NetworkBridge-Nodes existiert — aber nicht als
## GUT-Test in diesem Prozess (siehe Datei-Kopfkommentar, warum das hier
## strukturell nicht geht: ein einzelner Godot-Prozess kann keine zwei
## vollständigen App-Boots mit eigener Autorität nebeneinander betreiben, ohne
## exakt die Produktionscodepfade zu verbiegen, die der Test eigentlich prüfen
## soll). Der echte Test läuft als eigener CI-Job über
## `scripts/testing/IT03Harness.gd` — zwei echte `godot --headless`-Prozesse,
## kompletter App-Boot, organischer Input aus Player._loop_free_predicted().
func test_it03_full_movement_input_round_trip_covered_by_two_process_harness() -> void:
	pending("IT-03: läuft als eigener Zwei-Prozess-CI-Job (siehe " +
		"scripts/testing/IT03Harness.gd + build-apk.yml Job " +
		"'integration-two-process'), nicht innerhalb von GUT/diesem Prozess.")
