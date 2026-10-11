## tests/unit/test_economy_backsync_r7.gd
## Tests für R-7 (ADR-022) — Server→Client-Rücksync für Economy-Mutationen.
##
## Abdeckung:
##   - NetworkBridge.send_economy_update_for_player(): No-Op ohne Peer (Tier 1)
##     und No-Op wenn player_id == die eigene lokale player_id (Autorität muss
##     sich nicht selbst synchronisieren)
##   - InventorySystem._on_economy_state_received(): wendet einen empfangenen
##     Bucket auf den EIGENEN lokalen player_id an, unabhängig von der player_id
##     im ursprünglichen Payload (Client kennt nur "das bin ich")
##   - SkillSystem._on_economy_state_received(): wendet XP/Level für einen
##     einzelnen Skill an und feuert skill_changed() fürs UI
##   - EquipmentService._on_economy_state_received(): equip- und unequip-Payload
##     werden korrekt auf den lokalen Spieler anggewendet
##   - Alle drei Services ignorieren `kind`, der nicht zu ihnen gehört (kein
##     Cross-Talk zwischen inventory/skill/equipment auf demselben Broadcast-Signal)
##   - _connect_economy_sync() ist idempotent — sowohl über configure() (Test-
##     Harness-Pfad) als auch über inject_network_bridge() (Produktions-Boot-Pfad)
##     verbunden, aber nur eine tatsächliche Signal-Verbindung entsteht

extends GutTest

class MockDataService extends DataService:
	pass  ## get_item()/_items sind bereits in DataService.

class MockSaveSystem extends SaveSystem:
	func register_save_provider(_p: Object) -> void:
		pass
	func get_state_for(_key: String) -> Dictionary:
		return {}

var _bridge: NetworkBridge
var _bus: MockEventBus
var _save: MockSaveSystem
var _data: MockDataService
## ADR-029 Plan-Schritt 4 (Round 63): InventorySystem ist auf player_id:
## String migriert und holt sich ihre lokale Identität ausschließlich über
## NetworkBridge.get_local_player_id() -> SessionManager. Ohne registrierten
## Slot liefert das "" und _on_economy_state_received() bricht über den
## is_empty()-Guard früh ab — Tests, die den Empfangspfad wirklich prüfen
## wollen, brauchen deshalb denselben Session-Aufbau wie
## test_equipment_service_r4.gd (register_player_slot(1, "p1")).
var _session: SessionManager

func before_each() -> void:
	_bus  = MockEventBus.new()
	_save = MockSaveSystem.new()
	_data = MockDataService.new()

	_session = SessionManager.new()
	_session.register_player_slot(1, "p1")
	add_child_autofree(_session)

	_bridge = NetworkBridge.new()
	_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SESSION_MANAGER: _session,
	}))
	add_child_autofree(_bridge)

func after_each() -> void:
	_bridge.on_cleanup()
	_bridge = null
	_bus = null
	_save = null
	_data = null
	_session = null

# ─────────────────────────────────────────────
# NetworkBridge.send_economy_update_for_player() Guards
# ─────────────────────────────────────────────

## ADR-029 Round 66: `send_economy_update(int)` selbst ist entfernt — der
## letzte verbliebene Aufrufer (EquipmentService) ist jetzt auf das
## String-Pendant umgestellt, siehe NetworkBridge.gd-Kommentar. Die beiden
## Guard-Tests, die vorher direkt gegen `send_economy_update()` liefen, sind
## durch die beiden String-Pendants unten vollständig abgedeckt (identische
## Guards: kein Peer / Ziel ist der lokale Spieler selbst), deshalb ersatzlos
## entfernt statt gegen eine nicht mehr existierende Methode zu kompilieren.

func test_send_economy_update_for_player_is_noop_without_peer() -> void:
	# Tier 1 (kein Peer) — _has_peer() ist false, muss still zurückkehren.
	_bridge.send_economy_update_for_player("p1", "inventory", {"foo": "bar"})
	assert_true(true, "send_economy_update_for_player() ohne Peer darf nicht crashen.")

func test_send_economy_update_for_player_is_noop_for_local_player_id() -> void:
	# Ziel ist die eigene lokale player_id ("p1", über SessionManager
	# registriert) — die Autorität hat ihre eigene Kopie bereits direkt
	# mutiert, kein Rundweg über RPC für sich selbst nötig.
	_bridge.send_economy_update_for_player(_bridge.get_local_player_id(), "inventory", {"foo": "bar"})
	assert_true(true, "send_economy_update_for_player() für die eigene player_id darf nicht crashen.")

# ─────────────────────────────────────────────
# InventorySystem — Empfangsseite
# ─────────────────────────────────────────────

func test_inventory_applies_received_bucket_to_local_player() -> void:
	var ore := ItemDefinition.new()
	ore.id = "iron_ore"
	ore.display_name = "Iron Ore"
	_data._items[ore.id] = ore

	var inventory := InventorySystem.new()
	inventory.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _data,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
		"network_bridge": _bridge,
	}))

	var received_player_id := [""]
	var received_items: Array = [[]]
	inventory.inventory_changed.connect(
		func(pid: String, items: Array[Dictionary]) -> void:
			received_player_id[0] = pid
			received_items[0]     = items
	)

	# Autorität hätte für eine andere player_id gesendet — der Client wendet es
	# aber immer auf SEINE EIGENE lokale player_id an ("p1", über SessionManager
	# registriert), unabhängig davon was im Payload steht.
	# ADR-035 Phase 1: payload["items"] muss im ItemInstance.to_dict()-Wire-
	# Format ankommen ({item_id: {quantity, ...}}), nicht mehr im alten
	# {item_id: quantity(int)}-Format — siehe InventorySystem._on_economy_state_received().
	var bucket := {"items": {"iron_ore": {"quantity": 3}}, "weight": 1.5, "max_slots": 20, "max_weight": 50.0}
	_bridge.economy_state_received.emit("inventory", bucket)

	assert_eq(received_player_id[0], "p1", "Muss auf die lokale player_id angewendet werden, nicht auf player_id aus dem Payload.")
	assert_eq((received_items[0] as Array).size(), 1, "Bucket mit einem Item muss zu einem Eintrag führen.")

	inventory.on_cleanup()

func test_inventory_ignores_non_inventory_kind() -> void:
	var inventory := InventorySystem.new()
	inventory.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _data,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
		"network_bridge": _bridge,
	}))

	var call_count := [0]
	inventory.inventory_changed.connect(func(_pid, _items): call_count[0] += 1)

	_bridge.economy_state_received.emit("skill", {"skill_id": "mining", "xp": 5, "level": 1})

	assert_eq(call_count[0], 0, "kind=='skill' darf InventorySystem nicht triggern.")
	inventory.on_cleanup()

# ─────────────────────────────────────────────
# SkillSystem — Empfangsseite
# ─────────────────────────────────────────────

func test_skill_system_applies_received_xp_and_level_to_local_player() -> void:
	var combat_def := SkillDefinition.new()
	combat_def.id = "combat"
	combat_def.display_name = "Combat"
	_data._skills["combat"] = combat_def

	var skills := SkillSystem.new()
	skills.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _data,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
		"network_bridge": _bridge,
	}))

	# ADR-029 Round 65: skill_changed(skill_id: String, player_id: String) —
	# _on_economy_state_received() wendet den Payload immer auf die eigene
	# lokale player_id an (get_local_player_id() -> SessionManager), hier "p1"
	# (siehe register_player_slot(1, "p1") in before_each), unabhängig davon,
	# dass der Payload selbst keine player_id trägt.
	var received: Array = [null, null]
	skills.skill_changed.connect(
		func(skill_id: String, pid: String) -> void:
			received[0] = skill_id
			received[1] = pid
	)

	_bridge.economy_state_received.emit("skill", {"skill_id": "combat", "xp": 40, "level": 2})

	assert_eq(received[0], "combat", "skill_changed muss mit dem betroffenen Skill feuern.")
	assert_eq(received[1], "p1", "Muss auf die lokale player_id angewendet werden.")
	assert_eq(skills.get_level("combat", "p1"), 2, "Level muss aus dem Payload übernommen werden.")
	assert_eq(skills.get_xp("combat", "p1"), 40, "XP muss aus dem Payload übernommen werden.")

	skills.on_cleanup()

func test_skill_system_ignores_unknown_skill_id() -> void:
	var combat_def := SkillDefinition.new()
	combat_def.id = "combat"
	_data._skills["combat"] = combat_def

	var skills := SkillSystem.new()
	skills.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _data,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
		"network_bridge": _bridge,
	}))

	var call_count := [0]
	skills.skill_changed.connect(func(_sid, _pid): call_count[0] += 1)

	_bridge.economy_state_received.emit("skill", {"skill_id": "does_not_exist", "xp": 1, "level": 1})

	assert_eq(call_count[0], 0, "Unbekannte skill_id darf keinen skill_changed auslösen.")
	skills.on_cleanup()

# ─────────────────────────────────────────────
# EquipmentService — Empfangsseite
# ─────────────────────────────────────────────

func _make_weapon(id: String = "iron_sword") -> WeaponDefinition:
	var w := WeaponDefinition.new()
	w.id = id
	w.display_name = id
	w.damage_bonus = 5.0
	return w

func test_equipment_applies_received_equip_to_local_player() -> void:
	var sword := _make_weapon()
	_data._items[sword.id] = sword

	var equipment := EquipmentService.new()
	equipment.configure(ServiceDeps.from_dict({
		"savesystem": _save,
		"data": _data,
		"network_bridge": _bridge,
	}))

	_bridge.economy_state_received.emit("equipment", {"slot": "weapon", "item_id": sword.id})

	assert_true(equipment.is_equipped("weapon", "p1"), "Muss auf den lokalen Peer angewendet werden.")
	assert_eq(equipment.get_equipped("weapon", "p1"), sword)

	equipment.on_cleanup()

func test_equipment_applies_received_unequip_to_local_player() -> void:
	var sword := _make_weapon()
	_data._items[sword.id] = sword

	var equipment := EquipmentService.new()
	equipment.configure(ServiceDeps.from_dict({
		"savesystem": _save,
		"data": _data,
		"network_bridge": _bridge,
	}))
	equipment.equip("weapon", sword, "p1")

	_bridge.economy_state_received.emit("equipment", {"slot": "weapon", "item_id": null})

	assert_false(equipment.is_equipped("weapon", "p1"), "item_id==null muss den Slot leeren.")

	equipment.on_cleanup()

func test_equipment_ignores_unknown_item_id() -> void:
	var equipment := EquipmentService.new()
	equipment.configure(ServiceDeps.from_dict({
		"savesystem": _save,
		"data": _data,
		"network_bridge": _bridge,
	}))

	_bridge.economy_state_received.emit("equipment", {"slot": "weapon", "item_id": "does_not_exist"})

	assert_false(equipment.is_equipped("weapon", "p1"), "Unbekannte item_id darf nichts equippen.")

	equipment.on_cleanup()

# ─────────────────────────────────────────────
# _connect_economy_sync() Idempotenz
# ─────────────────────────────────────────────

func test_connect_economy_sync_does_not_double_connect_across_configure_and_late_inject() -> void:
	var inventory := InventorySystem.new()
	# configure() verbindet bereits (network_bridge als Dep vorhanden).
	inventory.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _data,
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.EVENT_BUS: _bus,
		"network_bridge": _bridge,
	}))
	# Produktions-Bootpfad ruft zusätzlich inject_network_bridge() auf (Phase C8) —
	# darf keine zweite Verbindung erzeugen.
	inventory.inject_network_bridge(_bridge)

	var call_count := [0]
	inventory.inventory_changed.connect(func(_pid, _items): call_count[0] += 1)

	_bridge.economy_state_received.emit("inventory", {"items": {}, "weight": 0.0, "max_slots": 20, "max_weight": 50.0})

	assert_eq(call_count[0], 1, "Trotz zweifacher Connect-Anfrage darf inventory_changed nur einmal feuern.")
	inventory.on_cleanup()
