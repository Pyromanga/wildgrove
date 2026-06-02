extends ServiceNode
class_name InventorySystem

## InventorySystem — Verwaltet das Spieler-Inventar.
## Lädt Item-Definitionen aus res://data/items/.
## Stellt sich beim SaveSystem als Provider vor.

signal inventory_changed(items: Array)

const LOG_CAT   := "Inventory"
const ITEMS_PATH := "res://data/items/"
const SAVE_KEY   := "inventory"

var _items:         Dictionary = {}  # item_id → quantity
var _item_registry: Dictionary = {}  # item_id → ItemDefinition

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	super._ready()

func init() -> void:
	super.init()
	_load_item_database()

	# Save-Provider registrieren
	var save_system := Kernel.get_service("savesystem") as SaveSystem
	if save_system:
		save_system.register_save_provider(self)
		# Gespeichertes Inventar laden
		var saved := save_system.get_state_for(SAVE_KEY)
		_restore_from_save(saved)
	else:
		Logger.log_warn("SaveSystem nicht gefunden — Inventar startet leer.", LOG_CAT)

	Logger.log_info("Bereit. Items: %d" % _items.size(), LOG_CAT)

func on_ready() -> void:
	super.on_ready()

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
	if not _item_registry.has(item_id):
		Logger.log_warn("Unbekanntes Item: '%s'" % item_id, LOG_CAT)
		return
	var def: ItemDefinition = _item_registry[item_id]
	var current := _items.get(item_id, 0) as int
	_items[item_id] = min(current + quantity, def.max_stack)
	Logger.log_debug("+%d '%s' (jetzt: %d)" % [quantity, item_id, _items[item_id]], LOG_CAT)
	inventory_changed.emit(get_all_items())

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
	var dir := DirAccess.open(ITEMS_PATH)
	if not dir:
		Logger.log_warn("Item-Ordner nicht gefunden: '%s'" % ITEMS_PATH, LOG_CAT)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var item := load(ITEMS_PATH + file_name) as ItemDefinition
			if item and not item.id.is_empty():
				_item_registry[item.id] = item
			elif item:
				Logger.log_warn("ItemDefinition ohne ID: '%s'" % file_name, LOG_CAT)
		file_name = dir.get_next()

	Logger.log_info("Item-DB: %d Einträge." % _item_registry.size(), LOG_CAT)

func _restore_from_save(saved: Dictionary) -> void:
	if saved.is_empty():
		return
	for item_id in saved:
		if _item_registry.has(item_id):
			_items[item_id] = saved[item_id]
		else:
			Logger.log_warn("Unbekanntes Item im Save: '%s' — ignoriert." % item_id, LOG_CAT)
	Logger.log_info("Inventar aus Save geladen: %d Items." % _items.size(), LOG_CAT)