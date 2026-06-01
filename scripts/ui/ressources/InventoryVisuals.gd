class_name InventoryVisuals

var panel: PanelContainer
var label: Label

func _init(parent: CanvasLayer) -> void:
    panel = PanelContainer.new()
    panel.visible = false
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    
    label = Label.new()
    panel.add_child(label)
    parent.add_child(panel)

func update_text(text: String) -> void:
    label.text = text

func toggle() -> void:
    panel.visible = !panel.visible