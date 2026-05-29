extends CanvasLayer
class_name HUD

var _inventory_label: Label

func _ready() -> void:
    add_to_group("hud")  # NEU
    _build_ui()
    Logger.log_debug("HUD bereit", "HUD")

func _build_ui() -> void:
    _inventory_label = Label.new()
    _inventory_label.name = "InventoryLabel"
    add_child(_inventory_label)

func update_inventory_display(items: Array) -> void:
    var text = "Inventar:\n"
    for item in items:
        text += "- " + item["name"] + ": " + str(item["quantity"]) + "\n"
    _inventory_label.text = text