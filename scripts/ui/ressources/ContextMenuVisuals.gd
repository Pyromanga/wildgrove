class_name ContextMenuVisuals

signal action_triggered(action)

var container: Control
var vbox: VBoxContainer

func _init(parent: CanvasLayer, actions: Array) -> void:
    container = Control.new()
    container.add_to_group("context_menu")
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    var panel := PanelContainer.new()
    # Layout wird hier durch den LayoutManager bestimmt (siehe unten)
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    container.add_child(panel)
    
    vbox = VBoxContainer.new()
    panel.add_child(vbox)
    
    for action in actions:
        var btn := Button.new()
        btn.text = action.label
        btn.custom_minimum_size = Vector2(200, 50)
        btn.pressed.connect(func(): action_triggered.emit(action))
        vbox.add_child(btn)
        
    parent.add_child(container)

func destroy() -> void:
    container.queue_free()