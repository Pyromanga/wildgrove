extends ServiceNode
class_name InventorySystem

## InventorySystem — Verwaltet das Spieler-Inventar.
## Abhängigkeiten (deps): ["data", "savesystem"]

signal inventory_changed(items: Array)

const LOG_CAT    := "Inventory"
const ITEMS_PATH := "res://data/items/"
const SAVE_KEY   := "inventory"

var _items:         Dictionary = {}
var _item_registry: Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

# res://scripts/services/InventorySystem.gd
var _save_system: SaveSystem # Expliziter Typ für Autocomplete!

func init(deps: Dictionary) -> void:
    _load_item_database()
    
    # Typsichere Extraktion (Enterprise-Standard)
    _save_system = deps.get("savesystem") as SaveSystem
    
    if not _save_system:
        Logger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)
        return

    _save_system.register_save_provider(self)
    # ... Rest der Logik ...

	# FIX: War `var saved := ...` — gleicher Typfehler wie WorldService/SkillSystem.
	var saved: Dictionary = Services.save_system.get_state_for(SAVE_KEY)
	if not saved.is_empty():
		_restore_from_save(saved)

	Logger.log_info(
		"Initialisiert. %d Items in DB, %d im Rucksack." % [_item_registry.size(), _items.size()],
		LOG_CAT
	)

func on_ready() -> void:
	pass

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return _items.duplicate()

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func add_item(item_id: String, quantity: int = 1) -> void:
	var def := get_item_info(item_id)
	if not def:
		Logger.log_error("Kann Item nicht hinzufügen: ID '%s' unbekannt." % item_id, LOG_CAT)
		return
	var current: int = _items.get(item_id, 0)
	_items[item_id] = min(current + quantity, def.max_stack)
	inventory_changed.emit(get_all_items())

func remove_item(item_id: String, quantity: int = 1) -> bool:
	var current: int = _items.get(item_id, 0)
	if current < quantity:
		Logger.log_warn("Zu wenig '%s' (hat: %d, braucht: %d)." % [item_id, current, quantity], LOG_CAT)
		return false
	_items[item_id] = current - quantity
	if _items[item_id] <= 0:
		_items.erase(item_id)
	inventory_changed.emit(get_all_items())
	return true

func has_item(item_id: String, quantity: int = 1) -> bool:
	return _items.get(item_id, 0) >= quantity

func get_quantity(item_id: String) -> int:
	return _items.get(item_id, 0)

func get_all_items() -> Array:
	var result: Array = []
	for item_id in _items:
		var def: ItemDefinition = _item_registry.get(item_id)
		result.append({
			"id":       item_id,
			"name":     def.display_name if def else item_id,
			"quantity": _items[item_id],
		})
	return result

func get_item_info(item_id: String) -> ItemDefinition:
	return _item_registry.get(item_id)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _load_item_database() -> void:
	var dir := DirAccess.open(ITEMS_PATH)
	if not dir:
		Logger.log_warn("Items-Pfad nicht gefunden: '%s'" % ITEMS_PATH, LOG_CAT)
		return
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			var item := load(ITEMS_PATH + file_name) as ItemDefinition
			if item and not item.id.is_empty():
				_item_registry[item.id] = item

func _restore_from_save(saved: Dictionary) -> void:
	for item_id in saved:
		if _item_registry.has(item_id):
			_items[item_id] = saved[item_id]