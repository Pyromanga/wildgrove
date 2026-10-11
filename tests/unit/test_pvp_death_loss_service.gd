# res://tests/unit/test_pvp_death_loss_service.gd
extends GutTest

## Unit-Tests für PvPDeathLossService (ADR-036 — PvP-Tod-Verlust/Skull-Loot).
##
## Strategie: PvPDeathLossService direkt instanziieren, mit ECHTEN Instanzen
## von PvPService/CurrencyService/InventorySystem/ItemProtectionService/
## AuraService als Kollaboratoren (Tier-1-Pfad, kein SaveSystem, kein
## NetworkBridge) — analog test_bank_service.gd/test_item_protection_service.gd.
## PvPService.set_voluntary_skull() wird genutzt, um einen Spieler direkt in
## den Skull-Zustand zu versetzen (einfacher als report_pvp_damage(), das
## zwei Spieler + Gegenwehr-Fenster-Buchführung bräuchte, und für die
## Verlust-Logik hier ohnehin irrelevant ist — nur is_skulled() zählt).
##
## Abgedeckt:
##   - Opfer geskullt → 100% Verlust (Gold UND Items)
##   - Opfer nicht geskullt → gestaffelter Verlust nach Killer-Risiko
##     (RISK_TIERS-Grenzfälle: exakt an einer Schwelle, unterhalb aller
##     Schwellen → Sockel-Prozentsatz)
##   - Loot geht an den Killer (Gold UND Items)
##   - ADR-038-Schutzkategorien: PvE-/Diebstahlschutz vollständig ausgenommen
##     (auch bei 100% Verlust), PvP-Schutz rettet + verbraucht sich
##   - Rundung auf 0 bei kleinen Stacks bei niedrigem Verlust-Prozentsatz
##     (dokumentiertes Verhalten, kein Bug)
##   - Fehlerfälle: leere IDs, victim==killer → No-Op
##   - death_loss_applied-Signal mit korrekten Werten
##   - ADR-036 Aura-Kopplung: Kill-Strafe NUR wenn der Killer selbst geskullt war

class MockItemDef extends ItemDefinition:
	func _init(p_id: String, p_name: String, p_sell_price: int = 0, p_max_stack: int = 99) -> void:
		id = p_id
		display_name = p_name
		sell_price = p_sell_price
		max_stack = p_max_stack

class MockDataService extends DataService:
	func get_all_items() -> Dictionary:
		return _items

const ORE := "iron_ore"
const SWORD := "iron_sword"
const P_VICTIM := "victim-uuid"
const P_KILLER := "killer-uuid"
const TEST_ROLES_PATH := "user://unit_test_pvp_death_loss_roles.json"

var _loss: PvPDeathLossService
var _pvp: PvPService
var _currency: CurrencyService
var _inventory: InventorySystem
var _protection: ItemProtectionService
var _aura: AuraService
var _perms: PermissionService
var _zones: ZoneService
var _ds: MockDataService
var _bus: MockEventBus

func before_each() -> void:
	_delete_test_roles_file()
	_ds = MockDataService.new()
	_ds._items[ORE]   = MockItemDef.new(ORE, "Eisenerz", 10, 99)
	_ds._items[SWORD] = MockItemDef.new(SWORD, "Eisenschwert", 100, 1)
	_bus = MockEventBus.new()

	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({ServiceKeys.DATA: _ds, ServiceKeys.EVENT_BUS: _bus}))

	_currency = CurrencyService.new()
	_currency.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

	_perms = PermissionService.new()
	_perms.set_path_override(TEST_ROLES_PATH)
	_perms.configure(ServiceDeps.from_dict({}))

	_zones = ZoneService.new()
	_zones.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	_zones.on_ready()

	_pvp = PvPService.new()
	_pvp.configure(ServiceDeps.from_dict({
		ServiceKeys.PERMISSION_SERVICE: _perms,
		ServiceKeys.ZONE_SERVICE: _zones,
	}))

	_protection = ItemProtectionService.new()
	_protection.configure(ServiceDeps.from_dict({ServiceKeys.INVENTORY: _inventory}))

	_aura = AuraService.new()
	_aura.configure(ServiceDeps.from_dict({}))

	_loss = PvPDeathLossService.new()
	_loss.configure(ServiceDeps.from_dict({
		ServiceKeys.PVP: _pvp,
		ServiceKeys.CURRENCY: _currency,
		ServiceKeys.INVENTORY: _inventory,
		ServiceKeys.ITEM_PROTECTION: _protection,
		ServiceKeys.AURA: _aura,
		ServiceKeys.EVENT_BUS: _bus,
	}))

func after_each() -> void:
	_zones.on_cleanup()
	_pvp.on_cleanup()
	_loss.on_cleanup()
	_loss = null
	_pvp = null
	_currency = null
	_inventory = null
	_protection = null
	_aura = null
	_perms = null
	_zones = null
	_ds = null
	_bus = null
	_delete_test_roles_file()

func _delete_test_roles_file() -> void:
	if FileAccess.file_exists(TEST_ROLES_PATH):
		DirAccess.remove_absolute(TEST_ROLES_PATH)
	if FileAccess.file_exists(TEST_ROLES_PATH + ".tmp"):
		DirAccess.remove_absolute(TEST_ROLES_PATH + ".tmp")

# ─────────────────────────────────────────────────────────────────────────────
# Opfer geskullt → 100% Verlust
# ─────────────────────────────────────────────────────────────────────────────

func test_skulled_victim_loses_all_gold() -> void:
	_currency.request_add_gold(P_VICTIM, 500)
	_pvp.set_voluntary_skull(P_VICTIM, true)

	_loss.apply_death_loss(P_VICTIM, P_KILLER)

	assert_eq(_currency.get_gold(P_VICTIM), 0)
	assert_eq(_currency.get_gold(P_KILLER), 500)

func test_skulled_victim_loses_all_items() -> void:
	_inventory.on_item_add_confirmed(ORE, 20, P_VICTIM)
	_pvp.set_voluntary_skull(P_VICTIM, true)

	_loss.apply_death_loss(P_VICTIM, P_KILLER)

	assert_false(_inventory.has_item(ORE, P_VICTIM, 1))
	assert_true(_inventory.has_item(ORE, P_KILLER, 20))

# ─────────────────────────────────────────────────────────────────────────────
# Opfer NICHT geskullt → gestaffelter Verlust nach Killer-Risiko
# ─────────────────────────────────────────────────────────────────────────────

func test_unskulled_victim_below_all_tiers_loses_floor_percent() -> void:
	_currency.request_add_gold(P_VICTIM, 1000)
	# Killer hat nichts mitgeführt → unterhalb aller Schwellen.
	_loss.apply_death_loss(P_VICTIM, P_KILLER)
	assert_eq(_currency.get_gold(P_VICTIM), 1000 - int(round(1000.0 * PvPDeathLossService.BELOW_TIER_LOSS_PERCENT)))

func test_unskulled_victim_exact_tier_threshold_uses_that_tier() -> void:
	_currency.request_add_gold(P_VICTIM, 10_000)
	_currency.request_add_gold(P_KILLER, 50_000)  # exakt an der niedrigsten Schwelle
	_loss.apply_death_loss(P_VICTIM, P_KILLER)
	var expected_loss := int(round(10_000.0 * 0.20))
	assert_eq(_currency.get_gold(P_KILLER), 50_000 + expected_loss, "Killer muss den vollen Verlust erhalten")
	assert_eq(_currency.get_gold(P_VICTIM), 10_000 - expected_loss)

func test_unskulled_victim_highest_tier_loses_70_percent() -> void:
	_currency.request_add_gold(P_VICTIM, 1000)
	_currency.request_add_gold(P_KILLER, 2_000_000_000)
	_loss.apply_death_loss(P_VICTIM, P_KILLER)
	assert_eq(_currency.get_gold(P_VICTIM), 1000 - int(round(1000.0 * 0.70)))

func test_killer_risk_counts_gold_and_item_sell_price() -> void:
	_currency.request_add_gold(P_VICTIM, 10_000)
	# Killer erreicht die 50k-Schwelle NUR über Item-Wert (5000x Ore * sell_price=10 = 50_000, kein Gold nötig).
	_inventory.on_item_add_confirmed(ORE, 5000, P_KILLER)  # 5000 * 10 sell_price = 50_000
	_loss.apply_death_loss(P_VICTIM, P_KILLER)
	var expected_loss := int(round(10_000.0 * 0.20))
	assert_eq(_currency.get_gold(P_VICTIM), 10_000 - expected_loss, "Item-Wert des Killers muss ins Risiko einfließen")

# ─────────────────────────────────────────────────────────────────────────────
# Loot geht an den Killer
# ─────────────────────────────────────────────────────────────────────────────

func test_lost_items_are_transferred_to_killer_not_destroyed() -> void:
	_inventory.on_item_add_confirmed(ORE, 100, P_VICTIM)
	_pvp.set_voluntary_skull(P_VICTIM, true)
	_loss.apply_death_loss(P_VICTIM, P_KILLER)
	assert_true(_inventory.has_item(ORE, P_KILLER, 100))

# ─────────────────────────────────────────────────────────────────────────────
# ADR-038-Schutzkategorien
# ─────────────────────────────────────────────────────────────────────────────

func test_pve_protected_item_survives_even_at_100_percent_loss() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P_VICTIM)
	_inventory.get_item_instance(P_VICTIM, SWORD).is_pve_death_protected = true
	_pvp.set_voluntary_skull(P_VICTIM, true)

	_loss.apply_death_loss(P_VICTIM, P_KILLER)

	assert_true(_inventory.has_item(SWORD, P_VICTIM, 1), "PvE-geschütztes Item darf nicht verloren gehen")
	assert_false(_inventory.has_item(SWORD, P_KILLER, 1))

func test_theft_protected_item_survives_even_at_100_percent_loss() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P_VICTIM)
	_inventory.get_item_instance(P_VICTIM, SWORD).is_theft_protected = true
	_pvp.set_voluntary_skull(P_VICTIM, true)

	_loss.apply_death_loss(P_VICTIM, P_KILLER)

	assert_true(_inventory.has_item(SWORD, P_VICTIM, 1))

func test_pvp_protected_item_survives_and_is_consumed() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P_VICTIM)
	_inventory.get_item_instance(P_VICTIM, SWORD).is_pvp_protected = true
	_pvp.set_voluntary_skull(P_VICTIM, true)

	_loss.apply_death_loss(P_VICTIM, P_KILLER)

	assert_true(_inventory.has_item(SWORD, P_VICTIM, 1), "PvP-Schutz muss das Item retten")
	assert_false(_inventory.get_item_instance(P_VICTIM, SWORD).is_pvp_protected, "PvP-Schutz muss dabei verbraucht werden")

func test_unprotected_item_alongside_protected_item_is_still_lost() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P_VICTIM)
	_inventory.on_item_add_confirmed(ORE, 10, P_VICTIM)
	_inventory.get_item_instance(P_VICTIM, SWORD).is_pve_death_protected = true
	_pvp.set_voluntary_skull(P_VICTIM, true)

	_loss.apply_death_loss(P_VICTIM, P_KILLER)

	assert_true(_inventory.has_item(SWORD, P_VICTIM, 1), "Geschütztes Item bleibt")
	assert_false(_inventory.has_item(ORE, P_VICTIM, 1), "Ungeschütztes Item geht trotzdem verloren")

# ─────────────────────────────────────────────────────────────────────────────
# Rundung bei kleinen Stacks (dokumentiertes Verhalten)
# ─────────────────────────────────────────────────────────────────────────────

func test_single_unprotected_item_survives_low_loss_percent_due_to_rounding() -> void:
	_inventory.on_item_add_confirmed(SWORD, 1, P_VICTIM)  # max_stack 1
	# Kein Skull, kein Killer-Risiko → BELOW_TIER_LOSS_PERCENT (5%), round(1*0.05)=0.
	_loss.apply_death_loss(P_VICTIM, P_KILLER)
	assert_true(_inventory.has_item(SWORD, P_VICTIM, 1), "Bei 5% Verlust darf ein einzelnes Item nicht verloren gehen (Rundung)")

# ─────────────────────────────────────────────────────────────────────────────
# Fehlerfälle
# ─────────────────────────────────────────────────────────────────────────────

func test_apply_death_loss_noop_for_empty_ids() -> void:
	_currency.request_add_gold(P_VICTIM, 100)
	_loss.apply_death_loss("", P_KILLER)
	_loss.apply_death_loss(P_VICTIM, "")
	assert_eq(_currency.get_gold(P_VICTIM), 100)

func test_apply_death_loss_noop_when_victim_equals_killer() -> void:
	_currency.request_add_gold(P_VICTIM, 100)
	_loss.apply_death_loss(P_VICTIM, P_VICTIM)
	assert_eq(_currency.get_gold(P_VICTIM), 100)

# ─────────────────────────────────────────────────────────────────────────────
# Signal
# ─────────────────────────────────────────────────────────────────────────────

func test_death_loss_applied_signal_reports_correct_values() -> void:
	_currency.request_add_gold(P_VICTIM, 500)
	_pvp.set_voluntary_skull(P_VICTIM, true)

	var received := []
	_loss.death_loss_applied.connect(
		func(victim, killer, gold_lost, items_lost, pct, was_skulled):
			received.append([victim, killer, gold_lost, pct, was_skulled])
	)
	_loss.apply_death_loss(P_VICTIM, P_KILLER)

	assert_eq(received, [[P_VICTIM, P_KILLER, 500, 1.0, true]])

# ─────────────────────────────────────────────────────────────────────────────
# ADR-036: Aura-Kopplung — Kill-Strafe nur wenn der KILLER selbst geskullt war
# ─────────────────────────────────────────────────────────────────────────────

func test_killer_aura_penalized_only_when_killer_was_skulled() -> void:
	_pvp.set_voluntary_skull(P_KILLER, true)
	_loss.apply_death_loss(P_VICTIM, P_KILLER)
	assert_eq(_aura.get_aura(P_KILLER), AuraService.KILL_PENALTY)

func test_killer_aura_untouched_when_killer_not_skulled() -> void:
	# Nur das Opfer ist geskullt — der Killer selbst war "sauber".
	_pvp.set_voluntary_skull(P_VICTIM, true)
	_loss.apply_death_loss(P_VICTIM, P_KILLER)
	assert_eq(_aura.get_aura(P_KILLER), 0)

# ─────────────────────────────────────────────────────────────────────────────
# Round 98 (ADR-042): Kill-Feed-Broadcast — EventBus.combat.player_killed_by_player
# ─────────────────────────────────────────────────────────────────────────────

class SpyNetworkBridge extends NetworkBridge:
	var broadcast_calls: Array[Dictionary] = []
	func broadcast_to_all_peers(kind: String, payload: Dictionary) -> void:
		broadcast_calls.append({"kind": kind, "payload": payload})

func test_apply_death_loss_emits_combat_event_locally_on_authority() -> void:
	# Kein NetworkBridge injiziert -> reiner Tier-1-Pfad. Die Autorität muss
	# ihr eigenes Kill-Feed-Signal trotzdem direkt emittieren (kein Rundweg
	# über ein RPC nötig, siehe _notify_kill()-Kommentar).
	_currency.request_add_gold(P_VICTIM, 500)
	_pvp.set_voluntary_skull(P_VICTIM, true)

	var received := []
	_bus.combat().player_killed_by_player.connect(
		func(victim, killer, was_skulled, gold_lost, items_lost_count):
			received.append([victim, killer, was_skulled, gold_lost, items_lost_count])
	)
	_loss.apply_death_loss(P_VICTIM, P_KILLER)

	assert_eq(received, [[P_VICTIM, P_KILLER, true, 500, 0]])

func test_apply_death_loss_broadcasts_pvp_kill_to_all_peers() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_loss.inject_network_bridge(net)

	_currency.request_add_gold(P_VICTIM, 500)
	_inventory.on_item_add_confirmed(ORE, 10, P_VICTIM)
	_pvp.set_voluntary_skull(P_VICTIM, true)

	_loss.apply_death_loss(P_VICTIM, P_KILLER)

	assert_eq(net.broadcast_calls.size(), 1,
		"Ein PvP-Tod muss genau einen Broadcast an alle Peers auslösen.")
	var payload: Dictionary = net.broadcast_calls[0]["payload"]
	assert_eq(net.broadcast_calls[0]["kind"], "pvp_kill")
	assert_eq(String(payload["victim_player_id"]), P_VICTIM)
	assert_eq(String(payload["killer_player_id"]), P_KILLER)
	assert_eq(bool(payload["victim_was_skulled"]), true)
	assert_eq(int(payload["gold_lost"]), 500)
	assert_eq(int(payload["items_lost_count"]), 1)

func test_apply_death_loss_noop_for_empty_ids_does_not_broadcast() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_loss.inject_network_bridge(net)
	_loss.apply_death_loss("", P_KILLER)
	assert_eq(net.broadcast_calls.size(), 0,
		"Der frühe No-Op-Guard darf keinen Kill-Feed-Broadcast auslösen.")

func test_broadcast_event_received_routes_pvp_kill_into_combat_event() -> void:
	# Client-Seite: broadcast_event_received (ADR-042) muss
	# EventBus.combat.player_killed_by_player auslösen — analog zu
	# AuctionHouseService.listings_updated (Round 97).
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_loss.inject_network_bridge(net)

	var received := []
	_bus.combat().player_killed_by_player.connect(
		func(victim, killer, was_skulled, gold_lost, items_lost_count):
			received.append([victim, killer, was_skulled, gold_lost, items_lost_count])
	)
	net.broadcast_event_received.emit("pvp_kill", {
		"event": "player_killed", "victim_player_id": P_VICTIM, "killer_player_id": P_KILLER,
		"victim_was_skulled": false, "gold_lost": 42, "items_lost_count": 2,
	})

	assert_eq(received, [[P_VICTIM, P_KILLER, false, 42, 2]])

func test_broadcast_event_received_ignores_other_kinds() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_loss.inject_network_bridge(net)

	var received := []
	_bus.combat().player_killed_by_player.connect(
		func(_v, _k, _s, _g, _i): received.append(true)
	)
	net.broadcast_event_received.emit("auction_house", {"event": "listings_snapshot", "listings": []})

	assert_true(received.is_empty(),
		"PvPDeathLossService darf nur auf kind == 'pvp_kill' reagieren.")
