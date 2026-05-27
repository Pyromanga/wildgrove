extends Node
## InventorySystem.gd — Passend für dein HUD-Grid

signal inventory_changed

# Speichert Items als Liste von Dictionaries, wie vom HUD erwartet
# [{ "item_id": "log_normal", "quantity": 5 }, ...]
var _inventory_data: Array = []

# Datenbank für Item-Infos (Name, Icon, etc.)
const ITEM_DATABASE = {
	"log_normal": { "name": "Holz" },
	"log_oak":    { "name": "Eichenholz" },
	"log_willow": { "name": "Weidenholz" },
	"log_maple":  { "name": "Ahornholz" }
}

func _ready() -> void:
	add_to_group("inventory_system")

## HUD-Kompatibel: Gibt alle Items als Array zurück
func get_all_items() -> Array:
	return _inventory_data

## HUD-Kompatibel: Gibt Infos wie den Namen zurück
func get_item_info(item_id: String) -> Dictionary:
	return ITEM_DATABASE.get(item_id, { "name": "Unbekannt" })
  
func add_item(item_id: String, amount: int = 1) -> void:
	var found = false
	for entry in _inventory_data:
		if entry["item_id"] == item_id:
			entry["quantity"] += amount
			found = true
			break
	
	if not found:
		_inventory_data.append({ "item_id": item_id, "quantity": amount })
	
	# Korrekte Einrückung: Diese Zeilen müssen auf Ebene 1 sein (genau wie 'if not found')
	inventory_changed.emit()
	Kernel.events.log("Inventory updated: " + item_id)

func clear_inventory() -> void:
    _inventory_data.clear()
    inventory_changed.emit()

func get_quantity(item_id: String) -> int:
    for entry in _inventory_data:
        if entry["item_id"] == item_id:
            return entry["quantity"]
    return 0