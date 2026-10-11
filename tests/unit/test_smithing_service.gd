# res://tests/unit/test_smithing_service.gd
extends GutTest

## Unit-Tests für SmithingService (Schmelzen & Schmieden).
##
## Strategie wie test_shop_service.gd: SmithingService extends Service (RefCounted) — kein
## add_child nötig. InventorySystem/SkillSystem/EquipmentService/DataService sind leichte lokale
## Stubs: sie bräuchten als echte Instanzen viel Setup (Gewichtslimits, Manifeste von Disk) für
## Dinge, die hier nicht getestet werden. Kein NetworkBridge -> request_craft() nimmt immer den
## synchronen Tier-1-Zweig; den Nicht-Autorität-Guard (braucht einen echten MultiplayerPeer)
## testet dieses File bewusst nicht. Die Zeit ist über `clock` steuerbar (kein echtes Warten).
##
## Abgedeckt:
##   - get_block_reason()/can_craft(): unbekanntes Rezept, Menge, Level, Werkzeug (Inventar UND
##     Werkzeug-Slot), Zutaten
##   - Stations-Zugang: ohne Zugang abgelehnt, Zugang läuft ab, Zugang gilt nur für DIESE Station,
##     Zugang über das Bus-Signal smithing_station_used, on_cleanup() räumt auf
##   - Herstellen: Erfolg (Zutaten weg, Ergebnis da, XP, Signal), Sammel-Herstellung (Menge x N),
##     volles Inventar -> Zutaten-Rollback, Werkzeuge werden nicht verbraucht

const PLAYER := "player-uuid-1"
const OTHER := "player-uuid-2"

class StubInventory extends InventorySystem:
	var stock: Dictionary = {}  ## "player|item" -> int
	## Items, deren Einlagern scheitert (simuliert "Inventar voll" nur für das HERGESTELLTE Item —
	## die Rückerstattung der Zutaten geht trotzdem durch, wie im echten Inventar mit freigewordenen Plätzen).
	var reject_adding: Array[String] = []
	var removed: Array = []

	func _k(player_id: String, item_id: String) -> String:
		return "%s|%s" % [player_id, item_id]

	func give(player_id: String, item_id: String, qty: int) -> void:
		stock[_k(player_id, item_id)] = int(stock.get(_k(player_id, item_id), 0)) + qty

	func count(player_id: String, item_id: String) -> int:
		return int(stock.get(_k(player_id, item_id), 0))

	func has_item(item_id: String, player_id: String, quantity: int = 1) -> bool:
		return count(player_id, item_id) >= quantity

	func remove_item(item_id: String, player_id: String, quantity: int = 1) -> bool:
		if count(player_id, item_id) < quantity:
			return false
		stock[_k(player_id, item_id)] = count(player_id, item_id) - quantity
		removed.append([item_id, quantity])
		return true

	func request_add_item(item_id: String, player_id: String, quantity: int = 1) -> bool:
		if reject_adding.has(item_id):
			return false
		give(player_id, item_id, quantity)
		return true

class StubSkills extends SkillSystem:
	var level: int = 10
	var xp_calls: Array = []

	func get_level(_skill_name: String, _player_id: String) -> int:
		return level

	func request_add_xp(skill_name: String, amount: int, player_id: String) -> void:
		xp_calls.append([skill_name, amount, player_id])

class StubEquipment extends EquipmentService:
	var tool_item: ItemDefinition = null

	func get_equipped(slot: String, _player_id: String) -> ItemDefinition:
		return tool_item if slot == EquipmentService.SLOT_TOOL else null

class StubData extends DataService:
	var recipes: Dictionary = {}
	func get_smithing_recipe(recipe_id: String) -> SmithingRecipe:
		return recipes.get(recipe_id)
	func get_all_smithing_recipes() -> Array[SmithingRecipe]:
		var out: Array[SmithingRecipe] = []
		for r in recipes.values():
			out.append(r)
		return out
	func get_smithing_recipes_for_station(station_kind: String) -> Array[SmithingRecipe]:
		var out: Array[SmithingRecipe] = []
		for r in recipes.values():
			if (r as SmithingRecipe).is_available_at(station_kind):
				out.append(r)
		return out

var _svc: SmithingService
var _inv: StubInventory
var _skills: StubSkills
var _equip: StubEquipment
var _data: StubData
var _bus: MockEventBus
var _now_ms: int = 0

var _completed: Array = []
var _failed: Array = []

func _recipe(rid: String, station: String, inputs: Dictionary, out_id: String, out_qty: int, min_level: int, xp: int, tools: Array[String]) -> SmithingRecipe:
	var r := SmithingRecipe.new()
	r.id = rid
	r.display_name = rid
	r.station = station
	r.inputs = inputs
	r.output_item_id = out_id
	r.output_quantity = out_qty
	r.min_level = min_level
	r.xp = xp
	r.required_tools = tools
	return r

func before_each() -> void:
	_now_ms = 1000
	_bus = MockEventBus.new()
	_inv = StubInventory.new()
	_skills = StubSkills.new()
	_equip = StubEquipment.new()
	_data = StubData.new()
	_data.recipes["smelt_iron"] = _recipe("smelt_iron", SmithingRecipe.STATION_FURNACE,
		{"iron_ore": 2, "charcoal": 2}, "iron_ingot", 1, 3, 30, ["tool_tongs"] as Array[String])
	_data.recipes["forge_iron_sword"] = _recipe("forge_iron_sword", SmithingRecipe.STATION_ANVIL,
		{"iron_ingot": 2}, "iron_sword", 1, 6, 80, ["tool_hammer", "tool_tongs"] as Array[String])

	_svc = SmithingService.new()
	_svc.clock = func() -> int: return _now_ms
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.INVENTORY: _inv,
		ServiceKeys.SKILL_SYSTEM: _skills,
		ServiceKeys.DATA: _data,
		ServiceKeys.EQUIPMENT: _equip,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	_svc.on_ready()

	_completed = []
	_failed = []
	_bus.smithing().smithing_craft_completed.connect(
		func(pid, rid, oid, qty, xp): _completed.append([pid, rid, oid, qty, xp]))
	_bus.smithing().smithing_craft_failed.connect(
		func(pid, rid, reason): _failed.append([pid, rid, reason]))

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

func _equip_smelter() -> void:
	_inv.give(PLAYER, "iron_ore", 4)
	_inv.give(PLAYER, "charcoal", 4)
	_inv.give(PLAYER, "tool_tongs", 1)

# ── get_block_reason / can_craft ──

func test_unknown_recipe_is_blocked() -> void:
	assert_eq(_svc.get_block_reason(PLAYER, "nope"), SmithingService.FAIL_UNKNOWN_RECIPE)

func test_empty_player_id_is_invalid() -> void:
	assert_eq(_svc.get_block_reason("", "smelt_iron"), SmithingService.FAIL_INVALID_PLAYER)

func test_quantity_bounds() -> void:
	_equip_smelter()
	assert_eq(_svc.get_block_reason(PLAYER, "smelt_iron", 0), SmithingService.FAIL_INVALID_QUANTITY)
	assert_eq(_svc.get_block_reason(PLAYER, "smelt_iron", -1), SmithingService.FAIL_INVALID_QUANTITY)
	assert_eq(_svc.get_block_reason(PLAYER, "smelt_iron", SmithingService.MAX_BATCH + 1), SmithingService.FAIL_INVALID_QUANTITY)

func test_level_too_low_is_blocked() -> void:
	_equip_smelter()
	_skills.level = 2
	assert_eq(_svc.get_block_reason(PLAYER, "smelt_iron"), SmithingService.FAIL_LEVEL_TOO_LOW)

func test_missing_tool_is_blocked() -> void:
	_inv.give(PLAYER, "iron_ore", 4)
	_inv.give(PLAYER, "charcoal", 4)
	assert_eq(_svc.get_block_reason(PLAYER, "smelt_iron"), SmithingService.FAIL_MISSING_TOOL)

func test_equipped_tool_counts_as_present() -> void:
	_inv.give(PLAYER, "iron_ore", 4)
	_inv.give(PLAYER, "charcoal", 4)
	var tongs := ItemDefinition.new()
	tongs.id = "tool_tongs"
	_equip.tool_item = tongs
	assert_eq(_svc.get_block_reason(PLAYER, "smelt_iron"), "")

func test_wrong_equipped_tool_does_not_count() -> void:
	_inv.give(PLAYER, "iron_ore", 4)
	_inv.give(PLAYER, "charcoal", 4)
	var axe := ItemDefinition.new()
	axe.id = "tool_axe"
	_equip.tool_item = axe
	assert_eq(_svc.get_block_reason(PLAYER, "smelt_iron"), SmithingService.FAIL_MISSING_TOOL)

func test_missing_ingredients_is_blocked() -> void:
	_equip_smelter()
	_inv.stock.clear()
	_inv.give(PLAYER, "tool_tongs", 1)
	_inv.give(PLAYER, "iron_ore", 1)  # braucht 2
	_inv.give(PLAYER, "charcoal", 2)
	assert_eq(_svc.get_block_reason(PLAYER, "smelt_iron"), SmithingService.FAIL_MISSING_INGREDIENTS)

func test_batch_multiplies_ingredient_requirement() -> void:
	_equip_smelter()  # 4 Erz / 4 Kohle -> reicht für genau 2 Durchläufe
	assert_true(_svc.can_craft(PLAYER, "smelt_iron", 2))
	assert_eq(_svc.get_block_reason(PLAYER, "smelt_iron", 3), SmithingService.FAIL_MISSING_INGREDIENTS)

func test_other_players_inventory_is_not_used() -> void:
	_equip_smelter()
	assert_eq(_svc.get_block_reason(OTHER, "smelt_iron"), SmithingService.FAIL_MISSING_TOOL)

# ── Stations-Zugang ──

func test_craft_without_station_access_is_rejected() -> void:
	_equip_smelter()
	_svc.request_craft(PLAYER, "smelt_iron")
	assert_eq(_failed.size(), 1)
	assert_eq(_failed[0][2], SmithingService.FAIL_NO_STATION)
	assert_eq(_inv.count(PLAYER, "iron_ore"), 4, "nichts darf verbraucht worden sein")
	assert_eq(_completed.size(), 0)

func test_access_is_per_station() -> void:
	_equip_smelter()
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_ANVIL)  # falsche Station
	_svc.request_craft(PLAYER, "smelt_iron")                          # Hochofen-Rezept
	assert_eq(_failed[0][2], SmithingService.FAIL_NO_STATION)

func test_access_is_per_player() -> void:
	_equip_smelter()
	_svc.grant_station_access(OTHER, SmithingRecipe.STATION_FURNACE)
	_svc.request_craft(PLAYER, "smelt_iron")
	assert_eq(_failed[0][2], SmithingService.FAIL_NO_STATION)

func test_access_expires() -> void:
	_equip_smelter()
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_FURNACE)
	assert_true(_svc.has_station_access(PLAYER, SmithingRecipe.STATION_FURNACE))
	_now_ms += int((SmithingService.STATION_ACCESS_SEC + 1.0) * 1000.0)
	assert_false(_svc.has_station_access(PLAYER, SmithingRecipe.STATION_FURNACE))
	_svc.request_craft(PLAYER, "smelt_iron")
	assert_eq(_failed[0][2], SmithingService.FAIL_NO_STATION)

func test_access_still_valid_just_before_expiry() -> void:
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_FURNACE)
	_now_ms += int((SmithingService.STATION_ACCESS_SEC - 1.0) * 1000.0)
	assert_true(_svc.has_station_access(PLAYER, SmithingRecipe.STATION_FURNACE))

func test_unknown_station_kind_is_never_granted() -> void:
	_svc.grant_station_access(PLAYER, "workbench")
	assert_false(_svc.has_station_access(PLAYER, "workbench"))

func test_access_granted_via_bus_signal() -> void:
	_equip_smelter()
	_bus.smithing().emit_smithing_station_used(PLAYER, SmithingRecipe.STATION_FURNACE)
	assert_true(_svc.has_station_access(PLAYER, SmithingRecipe.STATION_FURNACE))
	_svc.request_craft(PLAYER, "smelt_iron")
	assert_eq(_completed.size(), 1)

func test_revoke_removes_access() -> void:
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_FURNACE)
	_svc.revoke_station_access(PLAYER)
	assert_false(_svc.has_station_access(PLAYER, SmithingRecipe.STATION_FURNACE))

func test_cleanup_disconnects_signal_and_clears_access() -> void:
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_FURNACE)
	_svc.on_cleanup()
	assert_false(_svc.has_station_access(PLAYER, SmithingRecipe.STATION_FURNACE))
	_bus.smithing().emit_smithing_station_used(PLAYER, SmithingRecipe.STATION_FURNACE)
	assert_false(_svc.has_station_access(PLAYER, SmithingRecipe.STATION_FURNACE), "nach Cleanup darf das Signal nichts mehr bewirken")

# ── Herstellen ──

func test_successful_smelt_consumes_inputs_and_grants_output_and_xp() -> void:
	_equip_smelter()
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_FURNACE)
	_svc.request_craft(PLAYER, "smelt_iron")
	assert_eq(_inv.count(PLAYER, "iron_ore"), 2)
	assert_eq(_inv.count(PLAYER, "charcoal"), 2)
	assert_eq(_inv.count(PLAYER, "iron_ingot"), 1)
	assert_eq(_skills.xp_calls, [[SmithingService.SKILL_ID, 30, PLAYER]])
	assert_eq(_completed, [[PLAYER, "smelt_iron", "iron_ingot", 1, 30]])
	assert_eq(_failed.size(), 0)

func test_tools_are_not_consumed() -> void:
	_equip_smelter()
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_FURNACE)
	_svc.request_craft(PLAYER, "smelt_iron")
	assert_eq(_inv.count(PLAYER, "tool_tongs"), 1)

func test_batch_craft_scales_inputs_output_and_xp() -> void:
	_equip_smelter()
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_FURNACE)
	_svc.request_craft(PLAYER, "smelt_iron", 2)
	assert_eq(_inv.count(PLAYER, "iron_ore"), 0)
	assert_eq(_inv.count(PLAYER, "charcoal"), 0)
	assert_eq(_inv.count(PLAYER, "iron_ingot"), 2)
	assert_eq(_completed[0][3], 2)
	assert_eq(_completed[0][4], 60)

func test_forge_at_anvil_uses_anvil_access_not_furnace_access() -> void:
	_inv.give(PLAYER, "iron_ingot", 2)
	_inv.give(PLAYER, "tool_hammer", 1)
	_inv.give(PLAYER, "tool_tongs", 1)
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_FURNACE)
	_svc.request_craft(PLAYER, "forge_iron_sword")
	assert_eq(_failed[0][2], SmithingService.FAIL_NO_STATION)
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_ANVIL)
	_svc.request_craft(PLAYER, "forge_iron_sword")
	assert_eq(_inv.count(PLAYER, "iron_sword"), 1)
	assert_eq(_inv.count(PLAYER, "iron_ingot"), 0)

func test_full_inventory_refunds_all_inputs() -> void:
	_equip_smelter()
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_FURNACE)
	_inv.reject_adding = ["iron_ingot"]
	_svc.request_craft(PLAYER, "smelt_iron")
	assert_eq(_failed[0][2], SmithingService.FAIL_INVENTORY_FULL)
	assert_eq(_inv.count(PLAYER, "iron_ore"), 4, "Erz zurückerstattet")
	assert_eq(_inv.count(PLAYER, "charcoal"), 4, "Kohle zurückerstattet")
	assert_eq(_inv.count(PLAYER, "iron_ingot"), 0)
	assert_eq(_skills.xp_calls.size(), 0, "keine XP bei Fehlschlag")
	assert_eq(_completed.size(), 0)

func test_failed_craft_gives_no_xp() -> void:
	_svc.grant_station_access(PLAYER, SmithingRecipe.STATION_FURNACE)
	_svc.request_craft(PLAYER, "smelt_iron")  # nichts im Inventar
	assert_eq(_skills.xp_calls.size(), 0)

func test_recipes_for_station_filters_by_station() -> void:
	var furnace := _svc.get_recipes_for_station(SmithingRecipe.STATION_FURNACE)
	var anvil := _svc.get_recipes_for_station(SmithingRecipe.STATION_ANVIL)
	assert_eq(furnace.size(), 1)
	assert_eq(furnace[0].id, "smelt_iron")
	assert_eq(anvil.size(), 1)
	assert_eq(anvil[0].id, "forge_iron_sword")
