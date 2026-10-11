## tests/unit/test_equipment_service_r4.gd
## Regressionstests für ADR-027 (schließt R-4).
##
## Abdeckung:
##   - on_equip_confirmed() verweigert Equip wenn InventorySystem.has_item() false liefert
##   - on_equip_confirmed() erlaubt Equip wenn has_item() true liefert
##   - on_equip_confirmed() fragt WorldService.get_player_visuals(peer_id) für GENAU
##     den Ziel-Spieler ab, nicht für einen Default/lokalen Peer
##   - Ohne InventorySystem-Dep (Rückwärtskompatibilität, z. B. Tests ohne Inventory)
##     bleibt on_equip_confirmed() unverändert nutzbar (kein Crash, kein impliziter Zwang)
##   - Ohne WorldService-Dep (inject_world_service() nie aufgerufen) equipped trotzdem
##     erfolgreich, nur ohne Visual — kein Crash

extends GutTest

## Minimal DataService-Stub — wie in test_equipment_service.gd.
class MockDataService extends DataService:
	pass

## Minimal SaveSystem stand-in — wie in test_equipment_service.gd.
class MockSaveSystem extends SaveSystem:
	func register_save_provider(_p: Object) -> void:
		pass

	func get_state_for(_key: String) -> Dictionary:
		return {}

## ADR-027: Spy-WorldService — zeichnet auf, mit welchem peer_id
## get_player_visuals() aufgerufen wurde, statt eine echte Welt zu simulieren.
class SpyWorldService extends WorldService:
	var last_requested_peer_id: int = -1
	var call_count: int = 0
	var visuals_to_return: PlayerVisuals = null

	func get_player_visuals(peer_id: int) -> PlayerVisuals:
		last_requested_peer_id = peer_id
		call_count += 1
		return visuals_to_return

var _equipment: EquipmentService
var _stat_mods: StatModifierService
var _data: MockDataService
var _save_sys: MockSaveSystem
var _inventory: InventorySystem
var _bus: MockEventBus
## ADR-029 Round 66: `EquipmentService` führt peer_id jetzt selbst als
## String — `on_equip_confirmed()` bekommt die peer_id direkt (kein
## `_resolve_player_uuid()`-Umweg mehr, der existierte solange nur
## `InventorySystem` migriert war, siehe Git-Historie Round 63). Die
## `NetworkBridge`/`SessionManager`-Verdrahtung hier ist trotzdem nötig: die
## `WorldService`-Visuals-Auflösung (`SpyWorldService` unten) und die
## `StatModifierService`-Boni laufen intern über `EquipmentService.
## _resolve_peer_id()` (String → int, das Gegenstück) — ohne Bridge/Session
## würden die still übersprungen statt zu crashen.
var _session: SessionManager
var _bridge: NetworkBridge

func _make_weapon(id: String = "iron_sword", dmg_bonus: float = 5.0) -> WeaponDefinition:
	var w := WeaponDefinition.new()
	w.id = id
	w.display_name = id
	w.damage_bonus = dmg_bonus
	return w

func _make_equipment_with_inventory() -> void:
	_stat_mods = StatModifierService.new()
	_save_sys = MockSaveSystem.new()
	_data = MockDataService.new()
	_bus = MockEventBus.new()

	_session = SessionManager.new()
	_session.register_player_slot(1, "p1")
	_session.register_player_slot(2, "p2")
	_session.register_player_slot(7, "p7")
	add_child_autofree(_session)

	_bridge = NetworkBridge.new()
	_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SESSION_MANAGER: _session,
	}))
	add_child_autofree(_bridge)

	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _data,
		ServiceKeys.SAVE_SYSTEM: _save_sys,
		ServiceKeys.EVENT_BUS: _bus,
		"network_bridge": _bridge,
	}))

	_equipment = EquipmentService.new()
	_equipment.configure(ServiceDeps.from_dict({
		"stat_modifiers": _stat_mods,
		"savesystem": _save_sys,
		"data": _data,
		"inventory": _inventory,
		"network_bridge": _bridge,
	}))

func after_each() -> void:
	if is_instance_valid(_equipment):
		_equipment.on_cleanup()
	if is_instance_valid(_inventory):
		_inventory.on_cleanup()
	if is_instance_valid(_stat_mods):
		_stat_mods.on_cleanup()
	_equipment = null
	_inventory = null
	_stat_mods = null
	_data = null
	_save_sys = null
	_bus = null
	_session = null
	_bridge = null

# ─────────────────────────────────────────────
# has_item()-Guard (R-4)
# ─────────────────────────────────────────────

func test_on_equip_confirmed_rejects_when_player_does_not_have_item() -> void:
	_make_equipment_with_inventory()
	var sword := _make_weapon()
	_data._items[sword.id] = sword
	# Bewusst KEIN on_item_add_confirmed() — Spieler besitzt das Item nicht.

	_equipment.on_equip_confirmed("weapon", sword.id, "p1")

	assert_false(_equipment.is_equipped("weapon", "p1"),
		"on_equip_confirmed muss verweigern wenn InventorySystem.has_item() false liefert.")
	assert_null(_equipment.get_equipped("weapon", "p1"))

func test_on_equip_confirmed_allows_when_player_has_item() -> void:
	_make_equipment_with_inventory()
	var sword := _make_weapon()
	_data._items[sword.id] = sword
	_inventory.on_item_add_confirmed(sword.id, 1, "p1")

	_equipment.on_equip_confirmed("weapon", sword.id, "p1")

	assert_true(_equipment.is_equipped("weapon", "p1"),
		"on_equip_confirmed muss erlauben wenn der Spieler das Item besitzt.")
	assert_eq(_equipment.get_equipped("weapon", "p1"), sword)

func test_on_equip_confirmed_has_item_check_is_per_player() -> void:
	_make_equipment_with_inventory()
	var sword := _make_weapon()
	_data._items[sword.id] = sword
	_inventory.on_item_add_confirmed(sword.id, 1, "p1")  # nur Spieler 1 besitzt es

	_equipment.on_equip_confirmed("weapon", sword.id, "p2")

	assert_false(_equipment.is_equipped("weapon", "p2"),
		"Spieler 2 besitzt das Item nicht — muss trotz identischer item_id verweigert werden.")

## Rückwärtskompatibilität: ohne InventorySystem-Dep (z. B. bestehende Tests wie
## test_equipment_service.gd, die EquipmentService ohne "inventory" konfigurieren)
## bleibt on_equip_confirmed() nutzbar — die Prüfung wird übersprungen, nicht
## implizit erzwungen.
func test_on_equip_confirmed_without_inventory_dep_still_equips() -> void:
	_stat_mods = StatModifierService.new()
	_save_sys = MockSaveSystem.new()
	_data = MockDataService.new()
	var sword := _make_weapon()
	_data._items[sword.id] = sword

	_equipment = EquipmentService.new()
	_equipment.configure(ServiceDeps.from_dict({
		"stat_modifiers": _stat_mods,
		"savesystem": _save_sys,
		"data": _data,
	}))

	_equipment.on_equip_confirmed("weapon", sword.id, "p1")

	assert_true(_equipment.is_equipped("weapon", "p1"),
		"Ohne InventorySystem-Dep darf die has_item()-Prüfung nicht blockieren.")

# ─────────────────────────────────────────────
# WorldService-Auflösung der PlayerVisuals (ADR-027)
# ─────────────────────────────────────────────

func test_on_equip_confirmed_resolves_visuals_via_injected_world_service() -> void:
	_make_equipment_with_inventory()
	var sword := _make_weapon()
	_data._items[sword.id] = sword
	_inventory.on_item_add_confirmed(sword.id, 1, "p7")

	var spy_world := SpyWorldService.new()
	_equipment.inject_world_service(spy_world)

	_equipment.on_equip_confirmed("weapon", sword.id, "p7")

	assert_eq(spy_world.call_count, 1,
		"on_equip_confirmed muss WorldService.get_player_visuals() genau einmal aufrufen.")
	assert_eq(spy_world.last_requested_peer_id, 7,
		"Muss die Visuals des ZIEL-Spielers (peer_id) anfragen, nicht Default/1.")
	assert_true(_equipment.is_equipped("weapon", "p7"))

	spy_world.queue_free()

## Ohne inject_world_service() (z. B. Tests, die EquipmentService isoliert
## konfigurieren) darf on_equip_confirmed() weder crashen noch das Equip
## verweigern — nur das Visual bleibt aus.
func test_on_equip_confirmed_without_world_service_still_equips_without_crash() -> void:
	_make_equipment_with_inventory()
	var sword := _make_weapon()
	_data._items[sword.id] = sword
	_inventory.on_item_add_confirmed(sword.id, 1, "p1")

	_equipment.on_equip_confirmed("weapon", sword.id, "p1")

	assert_true(_equipment.is_equipped("weapon", "p1"),
		"Equip muss auch ohne injizierten WorldService erfolgreich sein.")

# ─────────────────────────────────────────────
# has_item()-Guard end-to-end über den RPC-Pfad (Round 71, schließt TODO-Punkt
# "Regressionstest für on_equip_confirmed()s has_item()-Prüfung fehlt")
#
# Die Tests oben rufen on_equip_confirmed() direkt auf — das deckt den Guard
# selbst ab, aber nicht den Weg, über den ein echter Client tatsächlich
# ausrüstet (Tier 2/3: request_equip() -> NetworkBridge.send_equip_item()
# -> RPC -> _rpc_equip_item() auf der Autorität -> on_equip_confirmed()).
# _rpc_equip_item() ist hier direkt aufrufbar: ohne aktiven MultiplayerPeer
# kollabiert _is_authority() auf "ist Autorität" (Tier-1-Konvention, siehe
# NetworkBridge._is_authority()), multiplayer.get_remote_sender_id() liefert
# 0 -> _sender_as_peer_id() defaultet auf peer 1 -> _sender_as_player_uuid()
# löst über SessionManager.get_player_id_for_peer(1) auf "p1" auf (siehe
# _session.register_player_slot(1, "p1") in _make_equipment_with_inventory()).
# ─────────────────────────────────────────────

## Reicht _equipment zusätzlich an _bridge durch — _make_equipment_with_inventory()
## konfiguriert _bridge VOR _equipment (Erstellungsreihenfolge), reconfigure()
## danach ist unschädlich (configure() ist reine Feldzuweisung, kein Re-Connect
## von Signalen o.ä.).
func _wire_bridge_to_equipment() -> void:
	_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.SESSION_MANAGER: _session,
		ServiceKeys.EQUIPMENT: _equipment,
	}))

func test_rpc_equip_item_rejects_when_player_does_not_have_item() -> void:
	_make_equipment_with_inventory()
	_wire_bridge_to_equipment()
	var sword := _make_weapon()
	_data._items[sword.id] = sword
	# Bewusst KEIN on_item_add_confirmed() — Spieler p1 (peer 1) besitzt das Item nicht.

	_bridge._rpc_equip_item("weapon", sword.id)

	assert_false(_equipment.is_equipped("weapon", "p1"),
		"Der komplette RPC-Pfad muss denselben has_item()-Guard durchsetzen wie der Direktaufruf.")

func test_rpc_equip_item_allows_when_player_has_item() -> void:
	_make_equipment_with_inventory()
	_wire_bridge_to_equipment()
	var sword := _make_weapon()
	_data._items[sword.id] = sword
	_inventory.on_item_add_confirmed(sword.id, 1, "p1")

	_bridge._rpc_equip_item("weapon", sword.id)

	assert_true(_equipment.is_equipped("weapon", "p1"),
		"Besitzt der Spieler das Item laut InventorySystem, muss der RPC-Pfad genauso erlauben wie der Direktaufruf.")
	assert_eq(_equipment.get_equipped("weapon", "p1"), sword)

## Gegenprobe: player_id kommt über den RPC-Pfad NIE aus einem Client-Parameter
## (_rpc_equip_item(slot, item_id) hat gar keinen player_id-Parameter mehr,
## siehe NetworkBridge._rpc_equip_item()) — sondern ausschließlich aus
## _sender_as_player_uuid(). Diese Guard-Kette kann also strukturell nicht
## dadurch umgangen werden, dass ein Client versucht, für einen ANDEREN
## Spieler auszurüsten; es gibt keinen Parameter, über den er das könnte.
func test_rpc_equip_item_always_resolves_target_player_from_sender_never_from_a_parameter() -> void:
	_make_equipment_with_inventory()
	_wire_bridge_to_equipment()
	var sword := _make_weapon()
	_data._items[sword.id] = sword
	_inventory.on_item_add_confirmed(sword.id, 1, "p1")   # p1 (peer 1, der Sender) besitzt es
	_inventory.on_item_add_confirmed(sword.id, 1, "p2")   # p2 (nicht der Sender) besitzt es ebenfalls

	_bridge._rpc_equip_item("weapon", sword.id)

	assert_true(_equipment.is_equipped("weapon", "p1"), "Muss dem tatsächlichen Sender (p1) gutgeschrieben werden.")
	assert_false(_equipment.is_equipped("weapon", "p2"), "Darf NIE einem anderen Spieler gutgeschrieben werden.")
