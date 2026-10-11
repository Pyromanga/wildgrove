# res://tests/unit/test_gravestone.gd
extends GutTest

## Unit-Tests für Gravestone (ADR-037 — PvE-Tod-Loot, Grab-Hybrid-Timer).
##
## Strategie: analog test_quest_npc.gd/test_harvestable_entity.gd —
## add_child_autofree(Gravestone.new()) für echten SceneTree-Zugriff
## (get_tree().create_timer() braucht einen Baum), EntityContext.for_test()
## + direkt gesetzte Felder als Kollaboratoren.
##
## Abgedeckt:
##   - on_spawn() übernimmt alle Config-Felder korrekt
##   - Phase-Check: Besitzer darf immer plündern, andere erst ab
##     personal_loot_until
##   - Plündern überträgt Gold+Items an den Looter und markiert _looted
##   - Doppel-Plünderung wird verhindert (_looted-Guard)
##   - Pool-Reuse: zweiter on_spawn()-Aufruf akkumuliert keine Visual-Kinder
##     UND behält die CollisionShape3D (Regressionstest für den in dieser
##     Runde gefixten Pool-Reuse-Bug)
##   - _on_interacted() mit falscher action_id ist No-Op

class MockNetworkBridge extends NetworkBridge:
	var peer_to_player: Dictionary = {}
	func get_player_id_for_peer(peer_id: int) -> String:
		return String(peer_to_player.get(peer_id, ""))

const OWNER := "owner-uuid"
const LOOTER := "looter-uuid"
const OWNER_PEER := 1
const LOOTER_PEER := 2

func _make_grave() -> Gravestone:
	return add_child_autofree(Gravestone.new())

func _make_ctx(currency: CurrencyService, inventory: InventorySystem, network: NetworkBridge) -> EntityContext:
	var ctx := EntityContext.for_test()
	ctx._currency = currency
	ctx._inventory = inventory
	ctx._network = network
	return ctx

func _make_network() -> MockNetworkBridge:
	var net := MockNetworkBridge.new()
	net.peer_to_player = {OWNER_PEER: OWNER, LOOTER_PEER: LOOTER}
	return net

func _make_currency() -> CurrencyService:
	var c := CurrencyService.new()
	c.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	return c

func _make_inventory() -> InventorySystem:
	var ds := DataService.new()
	ds.configure(ServiceDeps.from_dict({}))
	var ore_def := ItemDefinition.new()
	ore_def.id = "iron_ore"
	ore_def.display_name = "Eisenerz"
	ds._items["iron_ore"] = ore_def
	var inv := InventorySystem.new()
	inv.configure(ServiceDeps.from_dict({ServiceKeys.DATA: ds, ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	return inv

func _now() -> float:
	return Time.get_unix_time_from_system()

func _default_config(personal_loot_until: float, despawn_at: float) -> Dictionary:
	return {
		"owner_player_id": OWNER,
		"gold": 500,
		"items": [{"item_id": "iron_ore", "quantity": 10}],
		"personal_loot_until": personal_loot_until,
		"despawn_at": despawn_at,
	}

# ─────────────────────────────────────────────────────────────────────────────
# on_spawn() — Config-Übernahme
# ─────────────────────────────────────────────────────────────────────────────

func test_on_spawn_stores_owner_and_contents() -> void:
	var grave := _make_grave()
	var ctx := _make_ctx(_make_currency(), _make_inventory(), _make_network())
	grave.on_spawn(_default_config(_now() + 600.0, _now() + 1800.0), ctx)

	assert_eq(grave.owner_player_id, OWNER)
	assert_eq(grave._gold, 500)
	assert_eq(grave._items.size(), 1)
	assert_false(grave._looted)

func test_on_spawn_without_ctx_does_not_crash() -> void:
	var grave := _make_grave()
	grave.on_spawn(_default_config(_now() + 600.0, _now() + 1800.0), null)
	assert_true(true, "on_spawn() ohne Context darf nicht crashen")

# ─────────────────────────────────────────────────────────────────────────────
# Phase-Check (Personal Loot vs. Free-for-all)
# ─────────────────────────────────────────────────────────────────────────────

func test_owner_can_loot_during_personal_phase() -> void:
	var currency := _make_currency()
	var inventory := _make_inventory()
	var grave := _make_grave()
	grave.on_spawn(_default_config(_now() + 600.0, _now() + 1800.0), _make_ctx(currency, inventory, _make_network()))

	grave._on_interacted("loot_gravestone", OWNER_PEER)

	assert_eq(currency.get_gold(OWNER), 500, "Besitzer muss während Personal-Loot-Phase plündern können")
	assert_true(grave._looted)

func test_other_player_denied_during_personal_phase() -> void:
	var currency := _make_currency()
	var inventory := _make_inventory()
	var grave := _make_grave()
	grave.on_spawn(_default_config(_now() + 600.0, _now() + 1800.0), _make_ctx(currency, inventory, _make_network()))

	grave._on_interacted("loot_gravestone", LOOTER_PEER)

	assert_eq(currency.get_gold(LOOTER), 0, "Fremder darf während Personal-Loot-Phase nicht plündern")
	assert_false(grave._looted, "Grab darf nach verweigertem Versuch nicht als geplündert markiert sein")

func test_other_player_can_loot_after_personal_phase_expires() -> void:
	var currency := _make_currency()
	var inventory := _make_inventory()
	var grave := _make_grave()
	# personal_loot_until liegt bereits in der Vergangenheit → Free-for-all.
	grave.on_spawn(_default_config(_now() - 1.0, _now() + 1800.0), _make_ctx(currency, inventory, _make_network()))

	grave._on_interacted("loot_gravestone", LOOTER_PEER)

	assert_eq(currency.get_gold(LOOTER), 500, "Nach Ablauf der Personal-Loot-Phase darf jeder plündern")
	assert_true(grave._looted)

# ─────────────────────────────────────────────────────────────────────────────
# Plündern — Transfer + Doppel-Guard
# ─────────────────────────────────────────────────────────────────────────────

func test_looting_transfers_items_to_looter() -> void:
	var currency := _make_currency()
	var inventory := _make_inventory()
	var grave := _make_grave()
	grave.on_spawn(_default_config(_now() - 1.0, _now() + 1800.0), _make_ctx(currency, inventory, _make_network()))

	grave._on_interacted("loot_gravestone", LOOTER_PEER)

	assert_true(inventory.has_item("iron_ore", LOOTER, 10))

func test_second_loot_attempt_is_noop() -> void:
	var currency := _make_currency()
	var inventory := _make_inventory()
	var grave := _make_grave()
	grave.on_spawn(_default_config(_now() - 1.0, _now() + 1800.0), _make_ctx(currency, inventory, _make_network()))

	grave._on_interacted("loot_gravestone", LOOTER_PEER)
	# Zweiter Looter versucht es danach — Grab ist bereits leer/geplündert.
	grave._on_interacted("loot_gravestone", OWNER_PEER)

	assert_eq(currency.get_gold(OWNER), 0, "Nach erfolgreichem Plündern darf niemand mehr etwas bekommen")

func test_wrong_action_id_is_noop() -> void:
	var currency := _make_currency()
	var inventory := _make_inventory()
	var grave := _make_grave()
	grave.on_spawn(_default_config(_now() - 1.0, _now() + 1800.0), _make_ctx(currency, inventory, _make_network()))

	grave._on_interacted("some_other_action", LOOTER_PEER)

	assert_false(grave._looted)
	assert_eq(currency.get_gold(LOOTER), 0)

func test_unresolvable_peer_id_is_noop() -> void:
	var currency := _make_currency()
	var inventory := _make_inventory()
	var grave := _make_grave()
	var net := _make_network()
	net.peer_to_player.clear()  # keine Auflösung möglich für irgendeinen Peer
	grave.on_spawn(_default_config(_now() - 1.0, _now() + 1800.0), _make_ctx(currency, inventory, net))

	grave._on_interacted("loot_gravestone", LOOTER_PEER)

	assert_false(grave._looted)

# ─────────────────────────────────────────────────────────────────────────────
# Pool-Reuse (Regressionstest für den in dieser Runde gefixten Bug)
# ─────────────────────────────────────────────────────────────────────────────

func test_pool_reuse_does_not_accumulate_visual_children() -> void:
	var grave := _make_grave()
	var ctx := _make_ctx(_make_currency(), _make_inventory(), _make_network())
	grave.on_spawn(_default_config(_now() + 600.0, _now() + 1800.0), ctx)
	var count_after_first := grave.get_child_count()

	grave.on_spawn(_default_config(_now() + 600.0, _now() + 1800.0), ctx)
	var count_after_second := grave.get_child_count()

	assert_eq(count_after_second, count_after_first, "Zweiter on_spawn() darf keine zusätzlichen Kinder anhäufen")

func test_pool_reuse_keeps_collision_shape() -> void:
	var grave := _make_grave()
	var ctx := _make_ctx(_make_currency(), _make_inventory(), _make_network())
	grave.on_spawn(_default_config(_now() + 600.0, _now() + 1800.0), ctx)
	grave.on_spawn(_default_config(_now() + 600.0, _now() + 1800.0), ctx)

	var has_collision := false
	for child in grave.get_children():
		if child is CollisionShape3D:
			has_collision = true
			break
	assert_true(has_collision, "CollisionShape3D darf beim zweiten on_spawn() nicht verloren gehen (Pool-Reuse-Regression)")

func test_pool_reuse_resets_looted_flag() -> void:
	var currency := _make_currency()
	var inventory := _make_inventory()
	var grave := _make_grave()
	var net := _make_network()
	grave.on_spawn(_default_config(_now() - 1.0, _now() + 1800.0), _make_ctx(currency, inventory, net))
	grave._on_interacted("loot_gravestone", LOOTER_PEER)
	assert_true(grave._looted)

	# Grab wird "despawnt" und für ein neues Opfer wiederverwendet.
	grave.on_spawn(_default_config(_now() - 1.0, _now() + 1800.0), _make_ctx(currency, inventory, net))
	assert_false(grave._looted, "_looted muss bei Wiederverwendung zurückgesetzt werden")
