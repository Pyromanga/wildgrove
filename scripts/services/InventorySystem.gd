extends ServiceBase
class_name InventorySystem

signal inventory_changed

# item_id → quantity
var _items: Dictionary = {}

const ITEM_DATABASE: Dictionary = {
    "log_normal": { "name": "Holz" },
    "log_oak":    { "name": "Eichenholz" },
    "log_willow": { "name": "Weidenholz" },
    "log_maple":  { "name": "Ahornholz" },
    "iron_ore":   { "name": "Eisenerz" },
    "copper_ore": { "name": "Kupfererz" },
}

func add_item(item_id: String, amount: int = 1) -> void:
    if amount <= 0:
        Logger.log_error("add_item: amount muss > 0 sein (%d)" % amount, "Inventory")
        return
    _items[item_id] = _items.get(item_id, 0) + amount
    Logger.log_debug("+%d %s (gesamt: %d)" % [amount, item_id, _items[item_id]], "Inventory")
    inventory_changed.emit()

func remove_item(item_id: String, amount: int = 1) -> bool:
    if get_quantity(item_id) < amount:
        Logger.log_debug("Nicht genug %s" % item_id, "Inventory")
        return false
    _items[item_id] -= amount
    if _items[item_id] <= 0:
        _items.erase(item_id)
    inventory_changed.emit()
    return true

func get_quantity(item_id: String) -> int:
    return _items.get(item_id, 0)

func get_all_items() -> Array:
    # Gibt Array von {item_id, quantity} zurück — kompatibel mit InventoryUIController
    var result: Array = []
    for item_id in _items:
        result.append({ "item_id": item_id, "quantity": _items[item_id] })
    return result

func get_item_info(item_id: String) -> Dictionary:
    return ITEM_DATABASE.get(item_id, { "name": item_id })
    # Fallback zeigt die item_id selbst statt "Unbekannt" — hilft beim Debugging

func has_item(item_id: String, amount: int = 1) -> bool:
    return get_quantity(item_id) >= amount

func clear_inventory() -> void:
    _items.clear()
    inventory_changed.emit()
    Logger.log_debug("Inventory geleert", "Inventory")