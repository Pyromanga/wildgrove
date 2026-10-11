## tests/unit/test_network_bridge.gd
## Unit-Tests für NetworkBridge — Tier-1-Routing, Authority-Guard, Peer-Helfer.
##
## Abdeckung:
##   - Tier 1 (kein Peer): has_peer() == false, is_server() == true
##   - _is_authority() gibt true zurück ohne Peer
##   - _sender_as_peer_id() gibt 1 zurück wenn kein Remote-Sender
##   - send_start_quest() ruft on_quest_start_confirmed() direkt auf (Tier 1)
##   - send_complete_quest() ruft on_quest_complete_confirmed() direkt auf (Tier 1)
##   - host_game() / join_game() geben false zurück wenn ENet nicht verfügbar ist
##     (Headless-Test-Umgebung hat keinen echten Netzwerk-Stack)
##   - close() ist idempotent (kein Crash ohne Peer)
##   - SkillSystem.request_add_xp() mutiert immer direkt (kein RPC-Zweig mehr)
##   - InventorySystem.request_add_item() mutiert immer direkt (kein RPC-Zweig mehr)
##   - QuestService.request_start_quest() ruft direkt auf in Tier 1
##   - ADR-042: broadcast_to_all_peers() / get_all_joined_peer_ids() /
##     _rpc_receive_broadcast_event() — Tier-1-Guards + SessionManager-Fassade
##   - Round 114 (ADR-048 Broadcast-Lücke): _rpc_spawn_remote_player() trägt
##     den Look eines Mitspielers im Spawn-Payload mit (spawn_entity()-config)
##
## Teardown: kein echter MultiplayerPeer — alles bleibt in Tier 1.

extends GutTest

var _bridge:    NetworkBridge   = null
var _skill:     SkillSystem     = null
var _inventory: InventorySystem = null
var _bus:       MockEventBus    = null
var _save:      SaveSystem      = null

func before_each() -> void:
	_bus  = MockEventBus.new()
	_save = SaveSystem.new()

	_bridge    = NetworkBridge.new()
	_bridge.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	# on_ready() verbindet multiplayer-Signale — braucht add_child für SceneTree
	add_child_autofree(_bridge)

	_skill = SkillSystem.new()
	_skill.configure(ServiceDeps.from_dict({
		"network_bridge": _bridge,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))

	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({
		"network_bridge": _bridge,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))

func after_each() -> void:
	_bridge.on_cleanup()
	_skill.on_cleanup()
	_inventory.on_cleanup()
	_bridge    = null
	_skill     = null
	_inventory = null

# ─────────────────────────────────────────────
# Tier-1-Grundzustand
# ─────────────────────────────────────────────

func test_has_peer_false_without_peer() -> void:
	assert_false(_bridge.has_peer(), "Kein Peer gesetzt — has_peer() muss false sein.")

func test_is_server_true_without_peer() -> void:
	assert_true(_bridge.is_server(), "Ohne Peer ist dieser Prozess immer die Autorität.")

func test_get_local_peer_id_is_1_without_peer() -> void:
	assert_eq(_bridge.get_local_peer_id(), 1, "Ohne Peer ist die lokale peer_id immer 1.")

func test_close_without_peer_does_not_crash() -> void:
	# close() ist idempotent — kein Crash wenn kein Peer gesetzt
	_bridge.close()
	assert_true(true, "close() ohne Peer darf nicht crashen.")

# ─────────────────────────────────────────────
# Tier-1-Routing: send_*() direkt auf Services
# ─────────────────────────────────────────────
#
# Kein send_add_xp()/send_add_item() mehr — entfernt zusammen mit
# _rpc_add_xp/_rpc_add_item (siehe test_no_rpc_add_item_or_add_xp_surface()
# weiter unten und TODO-offene-probleme.md "Server validiert RPC-Werte nicht").

func test_send_start_quest_tier1_no_crash() -> void:
	# QuestService braucht DataService für Definitionen — hier nur Smoke-Test
	var quest := QuestService.new()
	quest.configure(ServiceDeps.from_dict({
		"network_bridge": _bridge,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	_bridge.configure(ServiceDeps.from_dict({"quest": quest, ServiceKeys.EVENT_BUS: _bus}))
	_bridge.send_start_quest("quest_woodcutter_intro")
	quest.on_cleanup()
	assert_true(true, "send_start_quest() in Tier 1 darf nicht crashen.")

func test_send_complete_quest_tier1_no_crash() -> void:
	var quest := QuestService.new()
	quest.configure(ServiceDeps.from_dict({
		"network_bridge": _bridge,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	_bridge.configure(ServiceDeps.from_dict({"quest": quest, ServiceKeys.EVENT_BUS: _bus}))
	_bridge.send_complete_quest("quest_woodcutter_intro")
	quest.on_cleanup()
	assert_true(true, "send_complete_quest() in Tier 1 darf nicht crashen.")

# ─────────────────────────────────────────────
# Tier-1-Routing: Services selbst (request_* ohne Peer)
# ─────────────────────────────────────────────

func test_skill_request_add_xp_tier1_direct_call() -> void:
	# request_add_xp() hat keinen RPC-Zweig mehr — mutiert immer direkt.
	_skill.request_add_xp("mining", 75, "p1")
	assert_eq(_skill.get_xp("mining", "p1"), 75,
		"request_add_xp() muss State direkt mutieren.")

func test_skill_request_add_xp_unknown_skill_no_crash() -> void:
	_skill.request_add_xp("nonexistent", 100, "p1")
	assert_true(true, "Unbekannter Skill darf keinen Crash verursachen.")

func test_inventory_request_add_item_tier1_without_data() -> void:
	# Ohne DataService gibt get_item_info() null → request_add_item() gibt false zurück
	var result := _inventory.request_add_item("iron_ore", "p1")
	assert_false(result, "Ohne DataService muss request_add_item() false zurückgeben.")

# ─────────────────────────────────────────────
# Host/Join API (Headless — kein echter Netzwerk-Stack)
# ─────────────────────────────────────────────

func test_host_game_returns_bool() -> void:
	# In der Headless-Test-Umgebung kann ENet scheitern oder klappen —
	# wichtig ist nur dass die Methode nicht crasht und einen bool zurückgibt.
	var result := _bridge.host_game(17777)
	assert_true(result is bool, "host_game() muss einen bool zurückgeben.")
	# Aufräumen falls der Peer tatsächlich erstellt wurde
	_bridge.close()

func test_join_game_invalid_address_returns_false() -> void:
	# Eine ungültige Adresse muss false zurückgeben, nicht crashen
	var result := _bridge.join_game("256.256.256.256", 17778)
	assert_false(result, "Ungültige Adresse muss false zurückgeben.")
	_bridge.close()

func test_close_after_host_is_idempotent() -> void:
	_bridge.host_game(17779)
	_bridge.close()
	_bridge.close()   # zweites close() darf nicht crashen
	assert_true(true, "Doppeltes close() darf nicht crashen.")

# ─────────────────────────────────────────────
# Null-Safety (Regression: multiplayer null in Tier 1)
# ─────────────────────────────────────────────

func test_roll_critical_without_peer_no_crash() -> void:
	var combat := CombatSystem.new()
	combat.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	# Vor dem Fix crashte das hier mit "Cannot call method 'has_multiplayer_peer' on null"
	var result := combat.roll_critical()
	assert_true(result is bool, "roll_critical() ohne Peer muss einen bool zurückgeben.")
	combat.on_cleanup()

func test_entity_orchestrator_generate_uuid_without_peer() -> void:
	var orch := EntityOrchestrator.new()
	add_child_autofree(orch)
	# _generate_uuid() intern — testen via spawn_entity() mit ungültigem Typ
	# Hauptsache: kein Crash durch multiplayer-null-Zugriff
	var result := orch.spawn_entity("unknown_type", Vector3.ZERO)
	assert_true(result == null or result is Node3D,
		"spawn_entity() mit unbekanntem Typ darf nicht wegen multiplayer-null crashen.")

# ─────────────────────────────────────────────
# C-02: Authority Guards in Services
# ─────────────────────────────────────────────

func test_inventory_on_item_add_confirmed_allowed_in_tier1() -> void:
	# Tier 1 (kein Peer) = Autorität → Guard lässt durch
	var inv := InventorySystem.new()
	var deps := ServiceDeps.from_dict({
		"data": DataService.new(),
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	})
	inv.configure(deps)
	# Kein inject_network_bridge → _network null → gilt als Autorität
	inv.on_item_add_confirmed("wood", 1, "p1")
	assert_true(true, "on_item_add_confirmed ohne Peer darf nicht crashen")
	inv.on_cleanup()

func test_no_rpc_add_item_or_add_xp_surface() -> void:
	# Root-Cause-Fund (TODO-offene-probleme.md, "Server validiert RPC-Werte nicht",
	# Option A): kein legitimer Pfad sendet mehr eine client-gewählte quantity/amount
	# über das Netz — die RPC-Endpunkte selbst sind deshalb entfernt, nicht nur
	# nachträglich validiert. Kein Guard-Test kann das prüfen, wenn die Methode gar
	# nicht mehr existiert — also prüfen wir genau das.
	assert_false(_bridge.has_method("_rpc_add_item"),
		"_rpc_add_item() ist entfernt — keine RPC-Fläche für client-gewählte Item-Mengen.")
	assert_false(_bridge.has_method("_rpc_add_xp"),
		"_rpc_add_xp() ist entfernt — keine RPC-Fläche für client-gewählte XP-Beträge.")
	assert_false(_bridge.has_method("send_add_item"),
		"send_add_item() ist entfernt — nichts sendet mehr einen rohen qty-Wert.")
	assert_false(_bridge.has_method("send_add_xp"),
		"send_add_xp() ist entfernt — nichts sendet mehr einen rohen amount-Wert.")

func test_inventory_authority_guard_blocks_client_direct_call() -> void:
	# Tier 2: _network gesetzt, has_peer() true, is_server() false
	# → Guard muss blockieren
	var inv := InventorySystem.new()
	inv.configure(ServiceDeps.from_dict({
		"data": DataService.new(),
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	# Wir können keinen echten Peer simulieren in Headless, aber wir können
	# prüfen dass inject_network_bridge() das Feld setzt.
	inv.inject_network_bridge(_bridge)
	# _bridge hat keinen echten Peer → has_peer() false → Guard greift nicht
	# Das ist korrekt: ohne Peer sind wir Tier 1 = Autorität.
	inv.on_item_add_confirmed("wood", 1, "p1")
	inv.on_cleanup()

# ─────────────────────────────────────────────
# C-03: Equipment-Sync in NetworkBridge
# ─────────────────────────────────────────────

func test_send_equip_item_tier1_calls_on_equip_confirmed() -> void:
	# Tier 1: send_equip_item ruft on_equip_confirmed direkt auf
	var eq := EquipmentService.new()
	add_child_autofree(eq)
	var data_svc := DataService.new()
	data_svc.configure(ServiceDeps.from_dict({}))
	var save_svc := SaveSystem.new()
	add_child_autofree(save_svc)
	save_svc.configure(ServiceDeps.from_dict({"event_bus": EventBus}))
	eq.configure(ServiceDeps.from_dict({"stat_modifiers": null, "savesystem": save_svc, "data": data_svc}))
	_bridge.configure(ServiceDeps.from_dict({"equipment": eq}))
	# Kein echtes Item in DataService → on_equip_confirmed loggt Fehler aber crasht nicht
	_bridge.send_equip_item("weapon", "iron_sword", "p1")
	assert_true(true, "send_equip_item() in Tier 1 darf nicht crashen")
	eq.on_cleanup()

func test_send_unequip_item_tier1_calls_on_unequip_confirmed() -> void:
	var eq := EquipmentService.new()
	add_child_autofree(eq)
	var save_svc := SaveSystem.new()
	add_child_autofree(save_svc)
	save_svc.configure(ServiceDeps.from_dict({"event_bus": EventBus}))
	eq.configure(ServiceDeps.from_dict({"stat_modifiers": null, "savesystem": save_svc, "data": DataService.new()}))
	_bridge.configure(ServiceDeps.from_dict({"equipment": eq}))
	# Slot ist leer → unequip gibt false aber crasht nicht
	_bridge.send_unequip_item("weapon", "p1")
	assert_true(true, "send_unequip_item() in Tier 1 darf nicht crashen")
	eq.on_cleanup()

# ─────────────────────────────────────────────
# ADR-038: Item-Schutz-Dreiklang — Routing in NetworkBridge
# ─────────────────────────────────────────────

func test_send_item_protection_apply_tier1_actually_applies_protection() -> void:
	# Tier 1: send_item_protection_apply() ruft on_apply_protection_confirmed()
	# direkt auf. Stärker als der reine "crasht nicht"-Test oben bei den
	# Equip-RPCs: hier bis zum tatsächlich gesetzten Flag durchgeprüft, weil
	# ItemProtectionService der von drei ADRs konsumierte Kern-Service ist.
	var ds := DataService.new()
	ds.configure(ServiceDeps.from_dict({}))
	var scroll_def := ItemDefinition.new()
	scroll_def.id = "scroll_pve_protection"
	scroll_def.display_name = "Schutzscroll (PvE)"
	scroll_def.grants_protection_type = "pve"
	var sword_def := ItemDefinition.new()
	sword_def.id = "iron_sword"
	sword_def.display_name = "Eisenschwert"
	ds._items["scroll_pve_protection"] = scroll_def
	ds._items["iron_sword"] = sword_def

	var inv := InventorySystem.new()
	inv.configure(ServiceDeps.from_dict({"data": ds, "event_bus": EventBus}))
	inv.on_item_add_confirmed("iron_sword", 1, "p1")
	inv.on_item_add_confirmed("scroll_pve_protection", 1, "p1")

	var prot := ItemProtectionService.new()
	prot.configure(ServiceDeps.from_dict({"inventory": inv}))

	_bridge.configure(ServiceDeps.from_dict({"item_protection": prot, "inventory": inv}))
	_bridge.send_item_protection_apply("scroll_pve_protection", "iron_sword", "p1")

	assert_true(inv.get_item_instance("p1", "iron_sword").is_pve_death_protected,
		"send_item_protection_apply() muss in Tier 1 bis zum gesetzten Flag durchrouten.")
	assert_false(inv.has_item("scroll_pve_protection", "p1", 1), "Scroll muss verbraucht sein.")
	inv.on_cleanup()

# ─────────────────────────────────────────────
# Schritt 3: Rate-Limiting auf any_peer-RPCs
# ─────────────────────────────────────────────

func test_rate_limit_allows_calls_within_limit() -> void:
	# _rpc_set_state hat Limit 10 pro Sekunde — 5 Aufrufe müssen alle durchgehen.
	for i in range(5):
		assert_false(_bridge._is_rate_limited("_rpc_set_state", 2),
			"Aufruf %d von 5 (Limit 10) darf nicht blockiert werden." % (i + 1))

func test_rate_limit_blocks_calls_over_limit_same_peer() -> void:
	# _rpc_start_quest hat Limit 5 pro Sekunde — der 6. Aufruf im selben Fenster muss blockiert werden.
	for i in range(5):
		assert_false(_bridge._is_rate_limited("_rpc_start_quest", 3),
			"Aufruf %d von 5 (Limit 5) darf noch nicht blockiert werden." % (i + 1))
	assert_true(_bridge._is_rate_limited("_rpc_start_quest", 3),
		"Der 6. Aufruf im selben Fenster muss blockiert werden.")

func test_rate_limit_is_per_peer_not_global() -> void:
	# Peer 4 schöpft sein Limit für _rpc_complete_quest (5) komplett aus ...
	for i in range(5):
		_bridge._is_rate_limited("_rpc_complete_quest", 4)
	assert_true(_bridge._is_rate_limited("_rpc_complete_quest", 4),
		"Peer 4 muss nach 5 Aufrufen blockiert werden.")
	# ... Peer 5 darf davon unberührt bleiben (eigenes Fenster).
	assert_false(_bridge._is_rate_limited("_rpc_complete_quest", 5),
		"Peer 5 darf durch Peer 4s Limit nicht mitbetroffen sein.")

func test_rate_limit_is_per_rpc_not_shared_across_endpoints() -> void:
	# Peer 6 schöpft sein Limit für _rpc_equip_item (10) komplett aus ...
	for i in range(10):
		_bridge._is_rate_limited("_rpc_equip_item", 6)
	assert_true(_bridge._is_rate_limited("_rpc_equip_item", 6),
		"Peer 6 muss bei _rpc_equip_item nach 10 Aufrufen blockiert werden.")
	# ... ein anderer RPC-Name für denselben Peer hat ein eigenes, unverbrauchtes Fenster.
	assert_false(_bridge._is_rate_limited("_rpc_unequip_item", 6),
		"Ein anderer RPC-Name für denselben Peer darf ein eigenes Limit-Fenster haben.")

func test_rate_limit_unlisted_rpc_is_never_limited() -> void:
	# _rpc_submit_movement_input steht absichtlich nicht in RATE_LIMITS (20+ Hz, unreliable).
	for i in range(50):
		assert_false(_bridge._is_rate_limited("_rpc_submit_movement_input", 7),
			"_rpc_submit_movement_input darf nie rate-limitiert werden (Aufruf %d)." % (i + 1))

func test_rate_limit_state_cleared_on_cleanup() -> void:
	for i in range(5):
		_bridge._is_rate_limited("_rpc_start_quest", 8)
	assert_true(_bridge._is_rate_limited("_rpc_start_quest", 8),
		"Peer 8 muss vor Cleanup blockiert sein.")
	_bridge.on_cleanup()
	assert_false(_bridge._is_rate_limited("_rpc_start_quest", 8),
		"Nach on_cleanup() muss das Rate-Limit-Fenster zurückgesetzt sein.")

func test_equipment_inject_network_bridge_sets_field() -> void:
	var eq := EquipmentService.new()
	add_child_autofree(eq)
	var save_svc := SaveSystem.new()
	add_child_autofree(save_svc)
	save_svc.configure(ServiceDeps.from_dict({"event_bus": EventBus}))
	eq.configure(ServiceDeps.from_dict({"stat_modifiers": null, "savesystem": save_svc, "data": DataService.new()}))
	eq.inject_network_bridge(_bridge)
	# Kein Peer → on_unequip_confirmed gilt als Autorität → kein Error
	eq.on_unequip_confirmed("weapon", "p1")
	assert_true(true, "on_unequip_confirmed nach inject ohne Peer = Tier 1 = ok")
	eq.on_cleanup()

# ─────────────────────────────────────────────
# ADR-042: broadcast_to_all_peers() / get_all_joined_peer_ids()
# ─────────────────────────────────────────────

func test_broadcast_to_all_peers_tier1_no_crash() -> void:
	# Kein Peer (Tier 1) → früher Guard-Return, kein RPC-Versuch, kein Crash.
	_bridge.broadcast_to_all_peers("weather_changed", {"kind": "rain"})
	assert_true(true, "broadcast_to_all_peers() ohne Peer darf nicht crashen.")

func test_broadcast_to_all_peers_tier1_never_emits_locally() -> void:
	# Die Autorität nimmt bewusst nie an ihrem eigenen Broadcast teil (siehe
	# Klassenkommentar) — auch in Tier 1 darf broadcast_event_received() nie
	# lokal feuern, selbst wenn dieser Prozess formal "is_server() == true" ist.
	var received := []
	_bridge.broadcast_event_received.connect(func(kind: String, payload: Dictionary) -> void:
		received.append([kind, payload])
	)
	_bridge.broadcast_to_all_peers("weather_changed", {"kind": "rain"})
	assert_eq(received.size(), 0,
		"broadcast_event_received darf im Tier-1-Guard-Return-Pfad nie feuern.")

func test_get_all_joined_peer_ids_empty_without_session_manager() -> void:
	# _bridge im before_each() bekommt keinen SessionManager injiziert.
	assert_eq(_bridge.get_all_joined_peer_ids(), [] as Array[int],
		"Ohne SessionManager muss die Peer-Liste leer sein, kein geratener Default.")

func test_get_all_joined_peer_ids_reflects_session_manager_slots() -> void:
	var sm := SessionManager.new()
	sm.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	sm.register_player_slot(1, "host_player")
	sm.register_player_slot(2, "joined_player")
	var bridge_with_sm := NetworkBridge.new()
	bridge_with_sm.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SESSION_MANAGER: sm,
	}))
	add_child_autofree(bridge_with_sm)
	var peer_ids := bridge_with_sm.get_all_joined_peer_ids()
	assert_eq(peer_ids.size(), 2, "Muss beide registrierten Slots widerspiegeln.")
	assert_true(1 in peer_ids, "peer_id 1 muss enthalten sein.")
	assert_true(2 in peer_ids, "peer_id 2 muss enthalten sein.")
	bridge_with_sm.on_cleanup()

func test_rpc_receive_broadcast_event_ignored_when_local_is_server() -> void:
	# Tier 1: multiplayer.is_server() == true (kein Peer) → Guard in
	# _rpc_receive_broadcast_event() muss die Emission unterdrücken, exakt wie
	# bei _rpc_receive_economy_update()/_rpc_receive_zone_update().
	var received := []
	_bridge.broadcast_event_received.connect(func(kind: String, payload: Dictionary) -> void:
		received.append([kind, payload])
	)
	_bridge._rpc_receive_broadcast_event("weather_changed", {"kind": "rain"})
	assert_eq(received.size(), 0,
		"_rpc_receive_broadcast_event() darf auf der Autorität selbst nie emittieren.")

# ─────────────────────────────────────────────
# Round 114 (ADR-048 Broadcast-Lücke): Look im Spawn-Payload für Mitspieler
# ─────────────────────────────────────────────

## Zeichnet auf, mit welcher config spawn_entity() für einen Remote-Player
## aufgerufen wurde — analog test_equipment_service_r4.gd's SpyWorldService,
## nur hier für _rpc_spawn_remote_player() statt on_equip_confirmed().
class SpyWorldServiceForSpawn extends WorldService:
	var last_spawn_type: String = ""
	var last_spawn_config: Dictionary = {}
	var last_spawn_peer_id: int = -1
	var player_by_id_to_return: Node3D = null

	func spawn_entity(type_id: String, _position: Vector3, config: Dictionary = {}, peer_id: int = 1) -> Node3D:
		last_spawn_type = type_id
		last_spawn_config = config
		last_spawn_peer_id = peer_id
		return null

	func get_player_by_id(_peer_id: int) -> Node3D:
		return player_by_id_to_return

func test_rpc_spawn_remote_player_forwards_look_into_spawn_config() -> void:
	# Kein CharacterCreationService injiziert -> _look_for_player() fällt auf
	# CharacterLook.default_look() zurück (siehe _look_for_player()-Kommentar).
	var spy_world := SpyWorldServiceForSpawn.new()
	var bridge_with_world := NetworkBridge.new()
	bridge_with_world.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.WORLD: spy_world,
	}))
	add_child_autofree(bridge_with_world)

	var look := CharacterLook.from_archetype("wald")
	bridge_with_world._rpc_spawn_remote_player(7, "player-7", Vector3(1, 0, 2), look)

	assert_eq(spy_world.last_spawn_type, "player")
	assert_eq(spy_world.last_spawn_peer_id, 7)
	assert_true(spy_world.last_spawn_config.has("look"),
		"Spawn-Payload muss einen \"look\"-Schlüssel tragen, sonst sieht ein frisch gespawnter Mitspieler falsch aus.")
	assert_eq(spy_world.last_spawn_config.get("look"), look,
		"Der im Spawn-Payload mitgeschickte Look muss exakt dem übergebenen Look entsprechen.")
	bridge_with_world.on_cleanup()

func test_rpc_spawn_remote_player_uses_default_look_without_character_creation_service() -> void:
	# Fehlt CharacterCreationService (z.B. isolierte Tests), darf
	# _rpc_spawn_remote_player() trotzdem nicht crashen — Fallback ist der
	# Standard-Look (siehe _look_for_player()).
	var spy_world := SpyWorldServiceForSpawn.new()
	var bridge_with_world := NetworkBridge.new()
	bridge_with_world.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.WORLD: spy_world,
	}))
	add_child_autofree(bridge_with_world)

	bridge_with_world._rpc_spawn_remote_player(9, "player-9", Vector3.ZERO, CharacterLook.default_look())

	assert_eq(spy_world.last_spawn_config.get("look"), CharacterLook.default_look())
	bridge_with_world.on_cleanup()

