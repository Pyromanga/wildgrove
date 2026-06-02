extends ServiceNode
class_name InventorySystem

## InventorySystem — Verwaltet das Spieler-Inventar.
## Abhängigkeiten (in BootstrapConfig deps): ["savesystem"]

signal inventory_changed(items: Array)

const LOG_CAT   := "Inventory"
const ITEMS_PATH := "res://data/items/"
const SAVE_KEY   := "inventory"

var _items:         Dictionary = {}  # item_id → quantity
var _item_registry: Dictionary = {}  # item_id → ItemDefinition

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	# 1. Statische DB laden (muss zuerst passieren!)
	_load_item_database()

	# 2. Beim SaveSystem registrieren
	# Da 'savesystem' in den deps steht, ist der Zugriff sicher.
	Services.save_system.register_save_provider(self)
	
	# 3. Daten-Restore (Sofort-Wiederherstellung aus dem RAM-Cache des SaveSystems)
	var saved := Services.save_system.get_state_for(SAVE_KEY)
	if not saved.is_empty():
		_restore_from_save(saved)

	Logger.log_info("Initialisiert. %d Items in DB, %d im Rucksack." % [_item_registry.size(), _items.size()], LOG_CAT)

func on_ready() -> void:
	# Hier könnten wir auf den EventBus hören, falls Items 
	# durch globale Events (z.B. Quest-Belohnung) getriggert werden.
	pass

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return _items.duplicate()

# ─────────────────────────────────────────────
# Öffentliche API (Bleibt weitgehend gleich, nutzt aber Logging & Typsicherheit)
# ─────────────────────────────────────────────

func add_item(item_id: String, quantity: int = 1) -> void:
	var def := get_item_info(item_id)
	if not def:
		Logger.log_error("Kann Item nicht hinzufügen: ID '%s' unbekannt." % item_id, LOG_CAT)
		return
		
	var current := _items.get(item_id, 0) as int
	_items[item_id] = min(current + quantity, def.max_stack)
	
	inventory_changed.emit(get_all_items())
	# Optional: Globales Event werfen
	# EventBus.inventory.item_added.emit(item_id, quantity)

func remove_item(item_id: String, quantity: int = 1) -> bool:
	var current := _items.get(item_id, 0) as int
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

## Gibt alle Items als Array von Dicts zurück (für UI).
func get_all_items() -> Array:
	var result := []
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
	# Hier nutzen wir DirAccess wie gehabt, um die .tres Dateien zu indexieren.
	# Profi-Tipp: In Godot 4.x ist 'DirAccess.get_files()' oft sauberer.
	var dir := DirAccess.open(ITEMS_PATH)
	if not dir: return

	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			var item := load(ITEMS_PATH + file_name) as ItemDefinition
			if item and not item.id.is_empty():
				_item_registry[item.id] = item

func _restore_from_save(saved: Dictionary) -> void:
	for item_id in saved:
		if _item_registry.has(item_id):
			_items[item_id] = saved[item_id]