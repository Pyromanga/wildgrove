# res://scripts/ui/controllers/InventoryUIController.gd
class_name InventoryUIController

var _visuals: InventoryVisuals
var _service: InventorySystem


func setup(visuals: InventoryVisuals, inv_service: InventorySystem) -> void:
	_visuals = visuals
	_service = inv_service
	_service.inventory_changed.connect(_on_inventory_changed)
	_update_display(_service.get_all_items())


func _on_inventory_changed(items: Array) -> void:
	_update_display(items)


func _update_display(items: Array) -> void:
	var lines: Array[String] = []
	for item in items:
		lines.append("%s ×%d" % [item["name"], item["quantity"]])
	_visuals.update_text("\n".join(lines) if not lines.is_empty() else "(Leer)")


func toggle() -> void:
	_visuals.toggle()
