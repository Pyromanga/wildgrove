extends Node
## InventorySystem.gd — Verwaltet die Gegenstände des Spielers

signal inventory_changed

# Speichert die Items als {"item_id": anzahl}, z.B. {"log_normal": 5}
var _items: Dictionary = {}

func _ready() -> void:
	add_to_group("inventory_system")
	print("[InventorySystem] Bereit.")


## Fügt ein Item hinzu oder erhöht die Anzahl
func add_item(item_name: String, amount: int = 1) -> void:
	if amount <= 0:
		return
		
	if _items.has(item_name):
		_items[item_name] += amount
	else:
		_items[item_name] = amount
		
	print("[InventorySystem] %d x %s hinzugefügt. Neuer Bestand: %d" % [amount, item_name, _items[item_name]])
	emit_signal("inventory_changed")


## Entfernt ein Item (wichtig für späteres Crafting/Quests)
func remove_item(item_name: String, amount: int = 1) -> bool:
	if not _items.has(item_name) or _items[item_name] < amount:
		return false # Nicht genug Items vorhanden
		
	_items[item_name] -= amount
	if _items[item_name] <= 0:
		_items.erase(item_name)
		
	emit_signal("inventory_changed")
	return true


## Gibt das gesamte Inventar zurück (für das HUD)
func get_items() -> Dictionary:
	return _items


## Prüft, ob der Spieler ein bestimmtes Item hat
func has_item(item_name: String, amount: int = 1) -> bool:
	return _items.get(item_name, 0) >= amount