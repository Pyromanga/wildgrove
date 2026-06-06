extends ServiceNode
class_name InventorySystem

## InventorySystem — Verwaltet das Spieler-Inventar.
## Abhängigkeiten (deps): ["data", "savesystem"]
##
## REFACTOR (Session 4):
##   _load_item_database() entfernt — InventorySystem öffnet kein DirAccess mehr.
##   Item-Registry kommt jetzt von DataService.get_all_items() (zentrales Repository).

signal inventory_changed(items: Array)

const LOG_CAT := "Inventory"
const SAVE_KEY := "inventory"

var _items: Dictionary = {}           # { "item_id": quantity }
var _item_registry: Dictionary = {}   # { "item_id": ItemDefinition } — von DataService

var _save_system: SaveSystem


# ─────────────────────────────────────────────
# Phase 4: Configure (DI)
# ─────────────────────────────────────────────


func configure(deps: Dictionary) -> void:
	var t := Logger.log_begin("InventorySystem.configure()", LOG_CAT)

	# Item-Registry aus DataService — kein eigenes DirAccess mehr
	var data_service := deps.get("data") as DataService
	if is_instance_valid(data_service):
		_item_registry = data_service.get_all_items()
		Logger.log_debug("Item-Registry von DataService: %d Items." % _item_registry.size(), LOG_CAT)
	else:
		Logger.log_error("DataService fehlt — Item-Registry leer!" , LOG_CAT)

	_save_system = deps.get("savesystem") as SaveSystem
	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		Logger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	Logger.log_end("InventorySystem.configure()", t, LOG_CAT)
	Logger.log_info(
		"Initialisiert. %d Items in DB, %d im Rucksack." % [_item_registry.size(), _items.size()],
		LOG_CAT
	)


# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────


func on_ready() -> void:
	# Initialen Zustand publizieren
	inventory_changed.emit(get_all_items())
	# Loot-Events von InteractableComponent abhören — statt direkter Service-Kopplung.
	# InteractableComponent ruft kein Services.inventory.add_item() mehr auf,
	# sondern emittiert EventBus.world.loot_collected. Wir horchen hier darauf.
	EventBus.world.loot_collected.connect(add_item)


# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────


func get_save_key() -> String:
	return SAVE_KEY


func get_save_data() -> Dictionary:
	# Duplicate verhindert, dass das SaveSystem Referenzen manipuliert
	return _items.duplicate()


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func add_item(item_id: String, quantity: int = 1) -> void:
	var def := get_item_info(item_id)
	if not def:
		Logger.log_error("Item-ID '%s' unbekannt." % item_id, LOG_CAT)
		return

	var current: int = _items.get(item_id, 0)
	_items[item_id] = min(current + quantity, def.max_stack)
	inventory_changed.emit(get_all_items())


func remove_item(item_id: String, quantity: int = 1) -> bool:
	var current: int = _items.get(item_id, 0)
	if current < quantity:
		Logger.log_warn("Zu wenig '%s' (Besitz: %d)." % [item_id, current], LOG_CAT)
		return false

	_items[item_id] = current - quantity
	if _items[item_id] <= 0:
		_items.erase(item_id)

	inventory_changed.emit(get_all_items())
	return true


func has_item(item_id: String, quantity: int = 1) -> bool:
	return _items.get(item_id, 0) >= quantity


func get_all_items() -> Array:
	var result: Array = []
	for item_id in _items:
		var def: ItemDefinition = _item_registry.get(item_id)
		result.append(
			{
				"id": item_id,
				"name": def.display_name if def else item_id,
				"quantity": _items[item_id],
				"icon": def.icon if def else null
			}
		)
	return result


func get_item_info(item_id: String) -> ItemDefinition:
	return _item_registry.get(item_id)


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _restore_from_save(saved: Dictionary) -> void:
	for item_id in saved:
		if _item_registry.has(item_id):
			_items[item_id] = int(saved[item_id])
