# Die Instanz, die im Inventar wirklich liegt
class_name ItemInstance extends RefCounted

var definition: ItemDefinition  # Referenz auf die statische Resource
var quantity: int = 1
var durability: float = 100.0

func _init(def: ItemDefinition, qty: int = 1) -> void:
	self.definition = def
	self.quantity = qty
