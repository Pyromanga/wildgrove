extends Node
## PlayerInventory.gd — Ressourcen-Inventar (Dictionary)
signal inventory_changed

var items: Dictionary = {}

func add_item(resource_name: String, amount: int) -> void:
	items[resource_name] = items.get(resource_name, 0) + amount
    	emit_signal("inventory_changed", resource_name, items[resource_name])

        func get_item_count(resource_name: String) -> int:
        	return items.get(resource_name, 0)extends