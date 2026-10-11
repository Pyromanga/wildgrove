# tests/integration/test_network_bridge_rpc_guards_two_peer.gd
extends GutTest

## Zwei-Peer-Integrationstest für die `is_server()`-Frühausstiegs-Guards in
## `NetworkBridge._rpc_receive_initial_state()` / `_rpc_receive_economy_update()`
## / `_rpc_receive_zone_update()` — siehe TODO-offene-probleme.md
## "Zwei-Peer-Integrationstests für alle `_rpc_receive_*`-Handler".
##
## EHRLICHER HINWEIS (wie test_movement_two_peer.gd):
##   Geschrieben ohne Zugriff auf ein Godot-Binary/eine echte Runtime in
##   dieser Sandbox — nach bestem Wissen korrekt konstruiert, aber NICHT
##   ausgeführt. Vor jedem Vertrauen in dieses Verhalten: mit echtem
##   Godot-Editor oder `godot --headless -s addons/gut/gut_cmdln.gd
##   -gdir=res://tests/integration/` tatsächlich laufen lassen. Insbesondere
##   `SceneTree.set_multiplayer(api, root_path)` (siehe unten) ist hier nach
##   bestem Wissen aus der Godot-4-API zitiert, aber nicht in dieser Sandbox
##   gegen eine echte Engine geprüft.
##
## DESIGN-ENTSCHEIDUNG — bewusst KEIN echter `rpc_id()`-Netzwerk-Dispatch:
##   `test_movement_two_peer.gd` (IT-03) hat bereits gezeigt, dass ein
##   vollständiger RPC-Dispatch über zwei Node-Subtrees im selben
##   GUT-Prozess strukturell kaum sauber hinzubekommen ist (NodePath-Matching
##   zwischen Server- und Client-Baum bräuchte zwei komplette,
##   pfadidentische App-Boots) — deshalb läuft der volle Movement-Round-Trip
##   dort bewusst über einen separaten Zwei-Prozess-CI-Job (IT03Harness.gd)
##   statt innerhalb dieser GUT-Suite.
##
##   Diese drei Guards brauchen das nicht: der Guard selbst
##   (`if multiplayer.is_server(): return`) hängt einzig vom Zustand des
##   ECHTEN `MultiplayerPeer`-Objekts ab, das am jeweiligen
##   `NetworkBridge`-Node hängt — genau der Teil, der laut TODO-Begründung
##   nicht sinnvoll mockbar ist. Es reicht deshalb, die Methode DIREKT
##   aufzurufen (kein `rpc_id()`), einmal auf einer `NetworkBridge`-Instanz,
##   deren `multiplayer` an den echten Server-Peer gebunden ist, und einmal
##   auf einer Instanz, deren `multiplayer` an den echten Client-Peer
##   gebunden ist (`get_tree().set_multiplayer(api, root_path)` bindet je
##   einen eigenen Subtree an eine eigene `MultiplayerAPI`-Instanz — analog
##   zum Kommentar in `test_movement_two_peer.gd`, dort aber nie tatsächlich
##   für einen Node-RPC-Aufruf genutzt).
##
##   Was das NICHT abdeckt: Godots eigene `@rpc("authority", …)`-Transport-
##   Durchsetzung (dass ein Nicht-Autorität-Peer den Aufruf über das Netz gar
##   nicht erst auslösen kann) — das ist Godot-Engine-Verhalten, nicht unser
##   Guard, wird hier bewusst nicht erneut geprüft.

const TEST_PORT := 38215  # anderer Port als test_movement_two_peer.gd (38214), um Kollision auszuschließen

var _server_peer: ENetMultiplayerPeer
var _client_peer: ENetMultiplayerPeer
var _server_mp: MultiplayerAPI
var _client_mp: MultiplayerAPI
var _server_root: Node
var _client_root: Node
var _server_bridge: NetworkBridge
var _client_bridge: NetworkBridge

var _server_save: _FakeSaveSystem
var _client_save: _FakeSaveSystem
var _server_zone: _FakeZoneService
var _client_zone: _FakeZoneService

## Test-Double für SaveSystem — zeichnet apply_remote_state()-Aufrufe auf,
## statt eine echte Persistenzschicht zu brauchen.
class _FakeSaveSystem extends SaveSystem:
	var apply_called: bool = false
	var applied_state: Dictionary = {}
	func apply_remote_state(state: Dictionary) -> void:
		apply_called = true
		applied_state = state

## Test-Double für ZoneService — zeichnet report_enter()/report_exit()-Aufrufe auf.
class _FakeZoneService extends ZoneService:
	var enter_calls: Array = []
	var exit_calls: Array = []
	func report_enter(peer_id: int, zone_id: StringName) -> void:
		enter_calls.append([peer_id, zone_id])
	func report_exit(peer_id: int, zone_id: StringName) -> void:
		exit_calls.append([peer_id, zone_id])

func before_each() -> void:
	_server_peer = ENetMultiplayerPeer.new()
	var server_err := _server_peer.create_server(TEST_PORT, 4)
	assert_eq(server_err, OK, "Server-Peer muss erstellbar sein (Port %d frei)." % TEST_PORT)

	_client_peer = ENetMultiplayerPeer.new()
	var client_err := _client_peer.create_client("127.0.0.1", TEST_PORT)
	assert_eq(client_err, OK, "Client-Peer muss sich verbinden können.")

	_server_mp = MultiplayerAPI.create_default_interface()
	_server_mp.multiplayer_peer = _server_peer
	_client_mp = MultiplayerAPI.create_default_interface()
	_client_mp.multiplayer_peer = _client_peer

	# Zwei getrennte Subtrees, jeweils an eine eigene MultiplayerAPI gebunden —
	# damit `multiplayer.is_server()` innerhalb von _server_bridge/_client_bridge
	# den jeweils ECHTEN, unterschiedlichen Peer-Zustand widerspiegelt statt
	# beide auf dieselbe globale Test-Baum-MultiplayerAPI zurückzufallen.
	_server_root = Node.new()
	_client_root = Node.new()
	add_child_autofree(_server_root)
	add_child_autofree(_client_root)
	get_tree().set_multiplayer(_server_mp, _server_root.get_path())
	get_tree().set_multiplayer(_client_mp, _client_root.get_path())

	_server_save = _FakeSaveSystem.new()
	_client_save = _FakeSaveSystem.new()
	_server_zone = _FakeZoneService.new()
	_client_zone = _FakeZoneService.new()

	_server_bridge = NetworkBridge.new()
	_server_root.add_child(_server_bridge)
	_server_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM:  _server_save,
		ServiceKeys.ZONE_SERVICE: _server_zone,
	}))
	_server_bridge.on_ready()

	_client_bridge = NetworkBridge.new()
	_client_root.add_child(_client_bridge)
	_client_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM:  _client_save,
		ServiceKeys.ZONE_SERVICE: _client_zone,
	}))
	_client_bridge.on_ready()

func after_each() -> void:
	if is_instance_valid(_server_bridge):
		_server_bridge.on_cleanup()
	if is_instance_valid(_client_bridge):
		_client_bridge.on_cleanup()
	if is_instance_valid(_server_peer):
		_server_peer.close()
	if is_instance_valid(_client_peer):
		_client_peer.close()
	_server_peer = null
	_client_peer = null

## Analog zu test_movement_two_peer.gd — pollt beide Peers aktiv, da ohne
## SceneTree-Anbindung niemand sonst das tut.
func _wait_until_connected() -> bool:
	var elapsed := 0.0
	while elapsed < 3.0:
		_server_peer.poll()
		_client_peer.poll()
		if _client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			return true
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
	return false

## Grundvoraussetzung für alle Guard-Tests unten: ohne echte Verbindung ist
## multiplayer.is_server() auf beiden Seiten bedeutungslos. Schlägt dieser
## Test fehl, sind alle anderen in dieser Datei ebenfalls nicht aussagekräftig.
func test_precondition_client_connects_and_is_server_differs_per_side() -> void:
	var connected := await _wait_until_connected()
	assert_true(connected, "Client muss sich innerhalb des Timeouts verbinden können.")
	assert_true(_server_mp.is_server(), "Server-MultiplayerAPI muss is_server()==true liefern.")
	assert_false(_client_mp.is_server(), "Client-MultiplayerAPI muss is_server()==false liefern.")

# ─────────────────────────────────────────────
# _rpc_receive_initial_state() — G-03
# ─────────────────────────────────────────────

func test_initial_state_guard_blocks_on_server() -> void:
	await _wait_until_connected()
	_server_bridge._rpc_receive_initial_state({"gold": 100})
	assert_false(_server_save.apply_called,
		"Guard muss auf dem Server früh returnen — apply_remote_state() darf nie serverseitig laufen.")

func test_initial_state_processes_on_client() -> void:
	await _wait_until_connected()
	_client_bridge._rpc_receive_initial_state({"gold": 100})
	assert_true(_client_save.apply_called,
		"Auf dem Client (Nicht-Autorität) muss apply_remote_state() tatsächlich laufen.")
	assert_eq(_client_save.applied_state, {"gold": 100})

# ─────────────────────────────────────────────
# _rpc_receive_economy_update() — ADR-022 R-7
# ─────────────────────────────────────────────

func test_economy_update_guard_blocks_on_server() -> void:
	await _wait_until_connected()
	watch_signals(_server_bridge)
	_server_bridge._rpc_receive_economy_update("inventory", {"slot": 1})
	assert_signal_not_emitted(_server_bridge, "economy_state_received",
		"Guard muss auf dem Server früh returnen — Signal darf serverseitig nie feuern.")

func test_economy_update_processes_on_client() -> void:
	await _wait_until_connected()
	watch_signals(_client_bridge)
	_client_bridge._rpc_receive_economy_update("inventory", {"slot": 1})
	assert_signal_emitted_with_parameters(_client_bridge, "economy_state_received", ["inventory", {"slot": 1}])

# ─────────────────────────────────────────────
# _rpc_receive_zone_update() — ADR-030
# ─────────────────────────────────────────────

func test_zone_update_guard_blocks_on_server() -> void:
	await _wait_until_connected()
	_server_bridge._rpc_receive_zone_update("pvp_desert", true)
	assert_eq(_server_zone.enter_calls.size(), 0,
		"Guard muss auf dem Server früh returnen — ZoneService darf serverseitig nie mutiert werden.")
	assert_eq(_server_zone.exit_calls.size(), 0)

func test_zone_update_processes_enter_on_client() -> void:
	await _wait_until_connected()
	_client_bridge._rpc_receive_zone_update("pvp_desert", true)
	assert_eq(_client_zone.enter_calls.size(), 1)
	assert_eq(_client_zone.exit_calls.size(), 0)

func test_zone_update_processes_exit_on_client() -> void:
	await _wait_until_connected()
	_client_bridge._rpc_receive_zone_update("pvp_desert", false)
	assert_eq(_client_zone.exit_calls.size(), 1)
	assert_eq(_client_zone.enter_calls.size(), 0)
