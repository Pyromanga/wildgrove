extends RefCounted
class_name InventoryUIController

const LOG_CAT := "UI/Inventory"

var panel: PanelContainer
var label: Label
var inventory_service: Node # Dein Service

func setup(hud: CanvasLayer, inv_service: Node) -> void:
    Logger.log_debug("Initialisiere InventoryUIController...", LOG_CAT)
    inventory_service = inv_service
    
    # 1. Visuals bauen (aus der UIFactory hierher verschoben)
    panel = PanelContainer.new()
    panel.visible = false
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    # Style-Logik hierher verschieben...
    
    label = Label.new()
    label.name = "InventoryLabel"
    panel.add_child(label)
    hud.add_child(panel)
    
    # 2. Verbinde das Event
    Kernel.events.player.inventory_changed.connect(_on_inventory_changed)
    
    # Initialer Status
    _on_inventory_changed(inventory_service.get_items())

func _on_inventory_changed(items: Array) -> void:
    Logger.log_debug("Update Inventar-UI", LOG_CAT)
    if items.is_empty():
        label.text = "(Leer)"
        return
        
    var lines: Array[String] = []
    for item in items:
        lines.append("%s ×%d" % [item["name"], item["quantity"]])
    label.text = "\n".join(lines)

func toggle() -> void:
    panel.visible = !panel.visible