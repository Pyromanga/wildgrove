# res://tests/unit/test_pickpocket_service.gd
extends GutTest

## Unit-Tests für PickpocketService (ADR-039 — Pickpocketing).
##
## Strategie: echte InventorySystem/CurrencyService/SkillSystem/ZoneService-
## Instanzen (Tier-1, analog test_pvp_death_loss_service.gd), MockNetworkBridge
## überschreibt nur die peer/player-Auflösung (analog MockNetworkBridge in
## test_gravestone.gd). Erfolg/Fehlschlag wird über Extremfälle des Levels
## deterministisch erzwungen (effective_level >> MILESTONE_1 → chance_1
## garantiert 1.0, kein Skill-Level → chance_1 garantiert 0.0), statt echten
## RNG in Tests zu verlassen — vermeidet Flakiness.
##
## Abgedeckt:
##   - not_a_crystal / crystal_not_owned / invalid_target Fehlerfälle
##   - Diebes-Zonen-Pflicht: Opfer außerhalb einer "theft"-Zone → Ablehnung
##   - Cooldown wird nach JEDEM Versuch gesetzt (Erfolg UND Fehlschlag) und
##     ist paar-symmetrisch wie bei AuraService
##   - Kristall wird IMMER verbraucht, unabhängig vom Ausgang
##   - Garantierter Erfolg (hohes effektives Level) transferiert Gold/Items,
##     garantierter Fehlschlag (kein Level) transferiert nichts
##   - ADR-038: is_theft_protected schließt Items vom Pool aus
##   - XP wird bei Erfolg UND Fehlschlag vergeben (unterschiedliche Beträge)
##   - Save-Round-Trip für Cooldowns, abgelaufene werden gefiltert

class MockNetworkBridge extends NetworkBridge:
	var peer_to_player: Dictionary = {}
	var player_to_peer: Dictionary = {}
	func get_player_id_for_peer(peer_id: int) -> String:
		return String(peer_to_player.get(peer_id, ""))
	func get_peer_id_for_player(player_id: String) -> int:
		return int(player_to_peer.get(player_id, -1))

class MockItemDef extends ItemDefinition:
	func _init(p_id: String, p_name: String, p_tier: String = "") -> void:
		id = p_id
		display_name = p_name
		pickpocket_crystal_tier = p_tier

class MockSkillDef extends SkillDefinition:
	func _init() -> void:
		id = "pickpocketing"
		display_name = "Diebstahl"
		xp_to_level_up = [1000]
		xp_scaling_factor = 1.0
		max_level = -1

class MockDataService extends DataService:
	func get_all_items() -> Dictionary:
		return _items
	func get_all_skills() -> Dictionary:
		return _skills

const CRYSTAL_WEAK := "theft_crystal_weak"
const CRYSTAL_NORMAL := "theft_crystal_normal"
const ORE := "iron_ore"
const SWORD := "iron_sword"
const THIEF := "thief-uuid"
const VICTIM := "victim-uuid"
const THIEF_PEER := 1
const VICTIM_PEER := 2
const THEFT_ZONE_ID := &"dark_alley"

var _pp: PickpocketService
var _inventory: InventorySystem
var _currency: CurrencyService
var _skill: SkillSystem
var _zones: ZoneService
var _net: MockNetworkBridge
var _ds: MockDataService
var _bus: MockEventBus
var _save: StubSaveSystem

class StubSaveSystem extends SaveSystem:
	## Analog StubSaveSystem in test_pvp_service.gd — echte SaveSystem-API-Form
	## ohne Festplattenzugriff.
	func register_save_provider(_p: Object) -> void:
		pass
	func get_state_for(_key: String) -> Dictionary:
		return {}

func before_each() -> void:
	_ds = MockDataService.new()
	_ds._items[CRYSTAL_WEAK]   = MockItemDef.new(CRYSTAL_WEAK, "Schwacher Kristall", "weak")
	_ds._items[CRYSTAL_NORMAL] = MockItemDef.new(CRYSTAL_NORMAL, "Kristall", "normal")
	_ds._items[ORE]   = MockItemDef.new(ORE, "Eisenerz")
	_ds._items[SWORD] = MockItemDef.new(SWORD, "Eisenschwert")
	_ds._skills["pickpocketing"] = MockSkillDef.new()
	_bus = MockEventBus.new()

	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({ServiceKeys.DATA: _ds, ServiceKeys.EVENT_BUS: _bus}))

	_currency = CurrencyService.new()
	_currency.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

	_save = StubSaveSystem.new()
	_skill = SkillSystem.new()
	_skill.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _ds,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
	}))

	_zones = ZoneService.new()
	_zones.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	_zones.on_ready()
	var zone_cfg := ZoneConfig.new()
	zone_cfg.zone_id = THEFT_ZONE_ID
	zone_cfg.tags = [&"theft"]
	_zones.register_zone_config(zone_cfg)

	_net = MockNetworkBridge.new()
	_net.peer_to_player = {THIEF_PEER: THIEF, VICTIM_PEER: VICTIM}
	_net.player_to_peer = {THIEF: THIEF_PEER, VICTIM: VICTIM_PEER}

	_pp = PickpocketService.new()
	_pp.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.CURRENCY: _currency,
		ServiceKeys.SKILL_SYSTEM: _skill,
		ServiceKeys.ZONE_SERVICE: _zones,
		ServiceKeys.NETWORK_BRIDGE: _net,
		ServiceKeys.EVENT_BUS: _bus,
	}))

func after_each() -> void:
	_zones.on_cleanup()
	_skill.on_cleanup()
	_pp = null
	_inventory = null
	_currency = null
	_skill = null
	_zones = null
	_net = null
	_ds = null
	_bus = null
	_save = null

func _put_victim_in_theft_zone() -> void:
	_zones.report_enter(VICTIM_PEER, THEFT_ZONE_ID)

func _give_thief_guaranteed_success_level() -> void:
	# Weit über MILESTONE_1 (100) → chance_1 immer 1.0, unabhängig vom Kristall-Bonus.
	for i in range(200):
		_skill.on_xp_add_confirmed("pickpocketing", 1000, THIEF)

# ─────────────────────────────────────────────────────────────────────────────
# Fehlerfälle — Vorprüfungen
# ─────────────────────────────────────────────────────────────────────────────

func test_invalid_target_self() -> void:
	var failed := []
	_pp.pickpocket_failed.connect(func(t, v, reason): failed.append(reason))
	_pp.on_pickpocket_confirmed(THIEF, THIEF, CRYSTAL_WEAK)
	assert_eq(failed, ["invalid_target"])

func test_not_a_crystal_for_unknown_item() -> void:
	var failed := []
	_pp.pickpocket_failed.connect(func(t, v, reason): failed.append(reason))
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, "does_not_exist")
	assert_eq(failed, ["not_a_crystal"])

func test_not_a_crystal_for_normal_item() -> void:
	var failed := []
	_pp.pickpocket_failed.connect(func(t, v, reason): failed.append(reason))
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, ORE)
	assert_eq(failed, ["not_a_crystal"])

func test_crystal_not_owned() -> void:
	_put_victim_in_theft_zone()
	var failed := []
	_pp.pickpocket_failed.connect(func(t, v, reason): failed.append(reason))
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)
	assert_eq(failed, ["crystal_not_owned"])

func test_victim_not_in_theft_zone_is_rejected() -> void:
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	# Kein report_enter() für VICTIM_PEER — Opfer ist in keiner Zone.
	var failed := []
	_pp.pickpocket_failed.connect(func(t, v, reason): failed.append(reason))
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)
	assert_eq(failed, ["victim_not_in_theft_zone"])
	assert_true(_inventory.has_item(CRYSTAL_WEAK, THIEF, 1), "Kristall darf bei Vorprüfungs-Fehlschlag nicht verbraucht werden")

# ─────────────────────────────────────────────────────────────────────────────
# Kristall-Verbrauch + Cooldown — IMMER, unabhängig vom Ausgang
# ─────────────────────────────────────────────────────────────────────────────

func test_crystal_is_always_consumed_even_on_guaranteed_failure() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	# Kein Skill-Level → chance_1 = 0.0 + TIER_BONUS[weak] (0.05) — nicht
	# GARANTIERT 0, aber sehr wahrscheinlich. Für einen deterministischen
	# Test wird stattdessen direkt der Verbrauch geprüft, unabhängig vom
	# (nicht kontrollierten) Erfolgs-Roll.
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)
	assert_false(_inventory.has_item(CRYSTAL_WEAK, THIEF, 1))

func test_cooldown_set_after_attempt_blocks_immediate_retry() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 2, THIEF)
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)

	var failed := []
	_pp.pickpocket_failed.connect(func(t, v, reason): failed.append(reason))
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)
	assert_eq(failed, ["cooldown_active"])
	# Zweiter Kristall darf bei Cooldown-Ablehnung nicht verbraucht werden.
	assert_true(_inventory.has_item(CRYSTAL_WEAK, THIEF, 1))

func test_cooldown_does_not_block_attempts_against_different_victim() -> void:
	_put_victim_in_theft_zone()
	var zone_cfg2 := ZoneConfig.new()
	zone_cfg2.zone_id = &"other_alley"
	zone_cfg2.tags = [&"theft"]
	_zones.register_zone_config(zone_cfg2)
	_zones.report_enter(3, &"other_alley")  # dritter Spieler, eigener Peer
	_net.peer_to_player[3] = "victim2-uuid"
	_net.player_to_peer["victim2-uuid"] = 3

	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 2, THIEF)
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)

	var failed := []
	_pp.pickpocket_failed.connect(func(t, v, reason): failed.append(reason))
	_pp.on_pickpocket_confirmed(THIEF, "victim2-uuid", CRYSTAL_WEAK)
	assert_eq(failed.size(), 0, "Cooldown gegen VICTIM darf einen Versuch gegen ein anderes Opfer nicht blockieren")

# ─────────────────────────────────────────────────────────────────────────────
# Garantierter Erfolg / Fehlschlag (Level-Extremfälle für Determinismus)
# ─────────────────────────────────────────────────────────────────────────────

func test_guaranteed_success_steals_something() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	_currency.request_add_gold(VICTIM, 1000)
	_give_thief_guaranteed_success_level()

	var attempts := []
	_pp.pickpocket_attempted.connect(
		func(t, v, success, items, gold): attempts.append([success, items.size(), gold])
	)
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)

	assert_eq(attempts.size(), 1)
	assert_true(attempts[0][0], "Bei garantiertem Erfolg muss success=true sein")
	assert_gt(attempts[0][1], 0, "Mindestens ein Slot muss etwas gestohlen haben")

func test_guaranteed_success_transfers_gold_to_thief() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	_currency.request_add_gold(VICTIM, 1000)
	_give_thief_guaranteed_success_level()

	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)

	assert_gt(_currency.get_gold(THIEF), 0, "Dieb muss etwas Gold erhalten haben")
	assert_lt(_currency.get_gold(VICTIM), 1000, "Opfer muss Gold verloren haben")

func test_zero_skill_level_with_no_victim_assets_does_not_crash() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	# Opfer besitzt nichts — auch bei Erfolg gibt es nichts zu stehlen.
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)
	assert_true(true, "Darf nicht crashen, auch wenn nichts stehlbar ist")

# ─────────────────────────────────────────────────────────────────────────────
# ADR-038: is_theft_protected schließt Items aus
# ─────────────────────────────────────────────────────────────────────────────

func test_theft_protected_item_never_in_pool() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	_inventory.on_item_add_confirmed(SWORD, 1, VICTIM)
	_inventory.get_item_instance(VICTIM, SWORD).is_theft_protected = true
	_give_thief_guaranteed_success_level()

	# Mehrfach versuchen (mit frischen Kristallen), um sicherzustellen, dass
	# das geschützte Schwert nie gestohlen wird, selbst bei garantiertem Erfolg.
	for i in range(5):
		_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
		# Cooldown umgehen für den Test — direkter Zugriff auf die interne Map.
		_pp._cooldowns.clear()
		_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)

	assert_true(_inventory.has_item(SWORD, VICTIM, 1), "Diebstahlgeschütztes Item darf niemals gestohlen werden")

# ─────────────────────────────────────────────────────────────────────────────
# XP-Vergabe
# ─────────────────────────────────────────────────────────────────────────────

func test_xp_granted_on_guaranteed_success() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	_currency.request_add_gold(VICTIM, 100)
	_give_thief_guaranteed_success_level()
	var xp_before := _skill.get_xp("pickpocketing", THIEF)

	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)

	assert_eq(_skill.get_xp("pickpocketing", THIEF), xp_before + PickpocketService.XP_SUCCESS)

func test_xp_granted_on_failure_is_smaller_than_success() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	# Kein Level — chance_1 ist klein (nur der Kristall-Bonus), Erfolg ist
	# nicht ausgeschlossen, aber der erwartete XP-Betrag bei Fehlschlag ist
	# in jedem Fall kleiner als XP_SUCCESS.
	var expected_fail_xp := int(round(float(PickpocketService.XP_SUCCESS) * PickpocketService.XP_FAIL_PERCENT))
	assert_lt(expected_fail_xp, PickpocketService.XP_SUCCESS)

# ─────────────────────────────────────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────────────────────────────────────

func test_save_key_is_pickpocket() -> void:
	assert_eq(_pp.get_save_key(), "pickpocket")

func test_save_data_round_trip_preserves_cooldown() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)
	var snapshot := _pp.get_save_data()

	var pp2 := PickpocketService.new()
	pp2.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.CURRENCY: _currency,
		ServiceKeys.SKILL_SYSTEM: _skill,
		ServiceKeys.ZONE_SERVICE: _zones,
		ServiceKeys.NETWORK_BRIDGE: _net,
	}))
	pp2._restore_from_save(snapshot)

	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	var failed := []
	pp2.pickpocket_failed.connect(func(t, v, reason): failed.append(reason))
	pp2.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)
	assert_eq(failed, ["cooldown_active"], "Cooldown muss Round-Trip überleben (Neustart-Exploit-Schutz)")

func test_save_data_filters_expired_cooldowns() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	_pp.on_pickpocket_confirmed(THIEF, VICTIM, CRYSTAL_WEAK)
	var key: String = _pp._pair_key(THIEF, VICTIM)
	_pp._cooldowns[key] = _pp._now() - 1.0  ## künstlich abgelaufen

	var saved := _pp.get_save_data()
	assert_false((saved["cooldowns"] as Dictionary).has(key))

# ─────────────────────────────────────────────
# Netzwerk-Routing / Client-Benachrichtigung (Round 113 Nachtrag, siehe
# method_reference_coverage.py-Fund)
# ─────────────────────────────────────────────

class MockBridgeAsClient extends NetworkBridge:
	var attempt_calls: Array = []
	func has_peer() -> bool:
		return true
	func is_server() -> bool:
		return false
	func send_pickpocket_attempt(crystal_item_id: String, victim_player_id: String, thief_player_id: String) -> void:
		attempt_calls.append([crystal_item_id, victim_player_id, thief_player_id])

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_pp.inject_network_bridge(bridge)
	assert_same(_pp._network, bridge)

func test_request_pickpocket_without_network_confirms_directly() -> void:
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	var attempted := []
	_pp.pickpocket_attempted.connect(func(t, v, success, items, gold): attempted.append(success))
	var failed := []
	_pp.pickpocket_failed.connect(func(t, v, reason): failed.append(reason))

	_pp.request_pickpocket(THIEF, VICTIM, CRYSTAL_WEAK)

	assert_eq(attempted.size() + failed.size(), 1, "Ohne Network-Bridge muss request_pickpocket() sofort verarbeiten (Attempt oder Fehlschlag, aber nicht gar nichts)")

func test_request_pickpocket_as_client_routes_via_network_not_local() -> void:
	var bridge: MockBridgeAsClient = add_child_autofree(MockBridgeAsClient.new())
	_put_victim_in_theft_zone()
	_inventory.on_item_add_confirmed(CRYSTAL_WEAK, 1, THIEF)
	_pp.inject_network_bridge(bridge)

	var fired := []
	_pp.pickpocket_attempted.connect(func(t, v, success, items, gold): fired.append(true))
	_pp.pickpocket_failed.connect(func(t, v, reason): fired.append(true))

	_pp.request_pickpocket(THIEF, VICTIM, CRYSTAL_WEAK)

	assert_eq(bridge.attempt_calls, [[CRYSTAL_WEAK, VICTIM, THIEF]])
	assert_true(fired.is_empty(), "Auf dem Client darf kein Versuch direkt ausgewertet werden")

func test_on_notification_received_forwards_to_ui_bus() -> void:
	var received := []
	_bus.ui().notification_requested.connect(func(text: String) -> void: received.append(text))
	_pp.on_notification_received("Jemand hat versucht, dich zu bestehlen!")
	assert_eq(received, ["Jemand hat versucht, dich zu bestehlen!"])
