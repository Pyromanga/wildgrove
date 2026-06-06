class_name ItemInstance
extends RefCounted

## ItemInstance — Laufzeit-Repräsentation eines einzelnen Inventar-Items.
##
## STATUS (Session 4): Vorbereitet, noch nicht aktiv genutzt.
##   InventorySystem speichert aktuell als { "item_id": quantity } Dictionary
##   (schnell, einfach, für die aktuelle Phase ausreichend).
##
## MIGRATION (geplant): Wenn Haltbarkeit, Enchantments, oder Item-spezifische
##   Eigenschaften gebraucht werden, InventorySystem auf Array[ItemInstance]
##   umstellen. Dann:
##     _items: Dictionary  →  _items: Array[ItemInstance]
##     add_item(id, qty)   →  add_item(instance: ItemInstance)
##
## NICHT LÖSCHEN — wird aktiv für diese Migration vorbereitet.

var definition: ItemDefinition
var quantity:   int   = 1
var durability: float = 100.0


func _init(def: ItemDefinition, qty: int = 1) -> void:
	self.definition = def
	self.quantity   = qty


func get_id() -> String:
	return definition.id if definition else ""


func get_display_name() -> String:
	return definition.display_name if definition else "???"


func is_stackable() -> bool:
	return definition.max_stack > 1 if definition else false


func is_broken() -> bool:
	return durability <= 0.0
