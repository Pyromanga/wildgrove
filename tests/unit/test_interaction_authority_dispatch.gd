# res://tests/unit/test_interaction_authority_dispatch.gd
extends GutTest

## Unit-Tests für ADR-020: Interaktions-Ergebnisse werden auf der Autorität
## ausgeführt, nicht mehr nur auf dem Peer, der lokal den Tween beendet hat.
##
## Deckt ab:
##   - WorldService.resolve_and_dispatch_interaction() ruft _on_interacted() nur
##     bei erfolgreicher resolve_for_player()-Auflösung auf (ADR-023-Kette intakt)
##   - unbekannte UUID / Spieler außerhalb Reichweite → kein Aufruf
##   - max_range kommt aus der InteractableComponent.detection_radius der Entity,
##     NICHT aus einem Parameter — Kern des in dieser Runde geschlossenen
##     Cheat-Vektors (ein Client könnte sonst eine beliebige Reichweite melden)
##   - request_entity_interaction() delegiert an NetworkBridge.send_entity_interaction()
##     wenn ein Peer gesetzt UND wir nicht die Autorität sind — sonst direkt lokal
##   - NetworkBridge._rpc_request_entity_interaction() liest peer_id NIE aus einem
##     RPC-Parameter, sondern aus _sender_as_peer_id() (via get_remote_sender_id())
##
## Was NICHT hier getestet wird: die konkreten Entity-Hooks selbst (AnimalBase
## catch_animal-Guard, HarvestableEntity despawn-Guard) — die haben eigene
## Tests, hier geht es nur um den Transport-/Resolve-Mechanismus.

var _svc: WorldService
var _world_root: Node3D

func before_each() -> void:
	_svc = WorldService.new()
	add_child_autofree(_svc)
	_svc.configure(ServiceDeps.from_dict({}))
	_world_root = add_child_autofree(Node3D.new())
	_svc._entity_orchestrator.initialize(_world_root)
	_svc._entity_orchestrator.register_definition(
		"mock_interactable", "res://tests/mocks/MockInteractableEntity.gd", ""
	)

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

func _spawn_player(peer_id: int, position: Vector3) -> Node3D:
	var player := Node3D.new()
	player.position = position
	player.add_to_group("player")
	player.set_meta("owner_peer_id", peer_id)
	add_child_autofree(player)
	return player

# ─────────────────────────────────────────────────────────────────────────────
# resolve_and_dispatch_interaction() — Erfolgsfall
# ─────────────────────────────────────────────────────────────────────────────

func test_dispatch_calls_on_interacted_when_player_in_range() -> void:
	_spawn_player(1, Vector3(1, 0, 0))
	var entity := _svc._entity_orchestrator.spawn_entity("mock_interactable", Vector3.ZERO) as MockInteractableEntity
	entity.attach_interactable_component(5.0, "chop")
	var uuid: String = entity.get_meta("entity_uuid")

	_svc.resolve_and_dispatch_interaction(uuid, "chop", 1)

	assert_eq(entity.interacted_calls.size(), 1, "_on_interacted() muss genau einmal aufgerufen werden.")
	assert_eq(entity.interacted_calls[0], ["chop", 1], "action_id/peer_id müssen unverändert durchgereicht werden.")

# ─────────────────────────────────────────────────────────────────────────────
# resolve_and_dispatch_interaction() — Ablehnungsfälle (ADR-023-Kette)
# ─────────────────────────────────────────────────────────────────────────────

func test_dispatch_does_nothing_for_unknown_uuid() -> void:
	_svc.resolve_and_dispatch_interaction("does-not-exist", "chop", 1)
	assert_true(true, "Darf bei unbekannter UUID nicht crashen (kein Aufruf möglich, keine Entity zum Prüfen).")

func test_dispatch_does_nothing_when_player_out_of_range() -> void:
	_spawn_player(1, Vector3(500, 0, 0))  # weit weg
	var entity := _svc._entity_orchestrator.spawn_entity("mock_interactable", Vector3.ZERO) as MockInteractableEntity
	entity.attach_interactable_component(5.0, "chop")
	var uuid: String = entity.get_meta("entity_uuid")

	_svc.resolve_and_dispatch_interaction(uuid, "chop", 1)

	assert_eq(entity.interacted_calls.size(), 0, "Spieler außerhalb Reichweite darf _on_interacted() nicht auslösen.")

func test_dispatch_does_nothing_without_matching_player() -> void:
	# Kein Player-Node mit peer_id=1 gespawnt.
	var entity := _svc._entity_orchestrator.spawn_entity("mock_interactable", Vector3.ZERO) as MockInteractableEntity
	entity.attach_interactable_component(5.0, "chop")
	var uuid: String = entity.get_meta("entity_uuid")

	_svc.resolve_and_dispatch_interaction(uuid, "chop", 1)

	assert_eq(entity.interacted_calls.size(), 0, "Ohne passenden Player-Node darf nichts ausgelöst werden.")

# ─────────────────────────────────────────────────────────────────────────────
# max_range kommt aus der Entity selbst — Kern-Fix dieser Runde
# ─────────────────────────────────────────────────────────────────────────────

func test_dispatch_uses_entitys_own_detection_radius_not_a_generous_default() -> void:
	# Spieler 6m entfernt: außerhalb eines enger konfigurierten Radius (3.0 + 1.5
	# Marge = 4.5 max), aber INNERHALB des Fallback-Radius (5.0) — würde also mit
	# der Fallback-Konstante fälschlich durchgehen, wenn die Entity-eigene
	# InteractableComponent nicht tatsächlich gelesen würde.
	_spawn_player(1, Vector3(6, 0, 0))
	var entity := _svc._entity_orchestrator.spawn_entity("mock_interactable", Vector3.ZERO) as MockInteractableEntity
	entity.attach_interactable_component(3.0, "chop")
	var uuid: String = entity.get_meta("entity_uuid")

	_svc.resolve_and_dispatch_interaction(uuid, "chop", 1)

	assert_eq(
		entity.interacted_calls.size(), 0,
		"Reichweite muss aus der Entity's eigener detection_radius (3.0) kommen, nicht aus einem großzügigen Fallback."
	)

func test_dispatch_falls_back_to_fixed_range_without_interactable_component() -> void:
	# Entity ohne angehängte InteractableComponent (kein "interactable_component"-Meta).
	# Defensive Deckung, kein Normalfall — Reichweite muss trotzdem endlich/geprüft sein.
	_spawn_player(1, Vector3(1, 0, 0))
	var entity := _svc._entity_orchestrator.spawn_entity("mock_interactable", Vector3.ZERO) as MockInteractableEntity
	var uuid: String = entity.get_meta("entity_uuid")

	_svc.resolve_and_dispatch_interaction(uuid, "chop", 1)

	assert_eq(entity.interacted_calls.size(), 1, "Fallback-Reichweite muss einen nahen Spieler weiterhin zulassen.")

# ─────────────────────────────────────────────────────────────────────────────
# request_entity_interaction() — Tier 1 (kein Peer): direkt auflösen
# ─────────────────────────────────────────────────────────────────────────────

func test_request_without_peer_resolves_directly() -> void:
	_spawn_player(1, Vector3(1, 0, 0))
	var entity := _svc._entity_orchestrator.spawn_entity("mock_interactable", Vector3.ZERO) as MockInteractableEntity
	entity.attach_interactable_component(5.0, "chop")
	var uuid: String = entity.get_meta("entity_uuid")

	_svc.request_entity_interaction(uuid, "chop", 1)

	assert_eq(
		entity.interacted_calls.size(), 1,
		"Ohne NetworkBridge/Peer (Tier 1) muss request_entity_interaction() denselben Pfad wie die Autorität nehmen."
	)

# ─────────────────────────────────────────────────────────────────────────────
# request_entity_interaction() — Tier 2 (Peer gesetzt, wir sind Client): via RPC
# ─────────────────────────────────────────────────────────────────────────────

## Überschreibt nur send_entity_interaction() um den RPC-Aufruf zu verfolgen,
## ohne einen echten MultiplayerPeer zu brauchen — identisches Muster zu
## MockNetworkBridgeAsPeer in test_network_bridge_contract.gd.
class MockBridgeAsClient extends NetworkBridge:
	var sent_calls: Array = []  # [[entity_uuid, action_id], ...]
	func has_peer() -> bool:
		return true
	func is_server() -> bool:
		return false
	func send_entity_interaction(entity_uuid: String, action_id: String) -> void:
		sent_calls.append([entity_uuid, action_id])

func test_request_with_peer_as_client_routes_via_network_not_local() -> void:
	_spawn_player(1, Vector3(1, 0, 0))
	var entity := _svc._entity_orchestrator.spawn_entity("mock_interactable", Vector3.ZERO) as MockInteractableEntity
	entity.attach_interactable_component(5.0, "chop")
	var uuid: String = entity.get_meta("entity_uuid")

	var mock_bridge := MockBridgeAsClient.new()
	add_child_autofree(mock_bridge)
	_svc.inject_network_bridge(mock_bridge)

	_svc.request_entity_interaction(uuid, "chop", 1)

	assert_eq(
		entity.interacted_calls.size(), 0,
		"Als Nicht-Autorität-Client darf request_entity_interaction() NICHT lokal wirken — sonst Doppel-Wirkung."
	)
	assert_eq(mock_bridge.sent_calls.size(), 1, "Muss genau einen RPC-Request an die Autorität senden.")
	assert_eq(mock_bridge.sent_calls[0], [uuid, "chop"], "RPC-Request muss uuid + action_id unverändert übertragen.")

# ─────────────────────────────────────────────────────────────────────────────
# NetworkBridge._rpc_request_entity_interaction() — peer_id kommt vom Sender,
# nie von einem Client-Parameter (Kern des in dieser Runde geschlossenen Lochs)
# ─────────────────────────────────────────────────────────────────────────────

func test_rpc_handler_delegates_to_world_with_authoritative_peer_id() -> void:
	_spawn_player(1, Vector3(1, 0, 0))
	var entity := _svc._entity_orchestrator.spawn_entity("mock_interactable", Vector3.ZERO) as MockInteractableEntity
	entity.attach_interactable_component(5.0, "chop")
	var uuid: String = entity.get_meta("entity_uuid")

	var bridge := NetworkBridge.new()
	add_child_autofree(bridge)
	bridge.configure(ServiceDeps.from_dict({"world": _svc}))

	# Kein echter MultiplayerPeer gesetzt → _is_authority() ist true (Solo-Fallback)
	# und _sender_as_peer_id() fällt auf 1 zurück (get_remote_sender_id() == 0
	# außerhalb eines echten RPC-Empfangs) — spiegelt exakt den Tier-1/Host-Fall.
	# Das RPC selbst nimmt NIE einen peer_id-Parameter entgegen (siehe Signatur).
	bridge._rpc_request_entity_interaction(uuid, "chop")

	assert_eq(entity.interacted_calls.size(), 1, "RPC-Handler muss über WorldService dispatchen.")
	assert_eq(entity.interacted_calls[0], ["chop", 1], "peer_id muss aus dem Sender kommen, nicht aus einem Parameter.")
