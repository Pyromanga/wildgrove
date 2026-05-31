extends RefCounted
class_name ContextMenuController

const LOG_CAT := "UI/ContextMenu"

func show(hud: CanvasLayer, actions: Array) -> void:
    if actions.is_empty(): return
    
    # Aufräumen von alten Menüs (wenn nötig)
    var existing = hud.get_tree().get_nodes_in_group("context_menu")
    for n in existing: n.queue_free()

    var container := Control.new()
    container.add_to_group("context_menu")
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE

    # Layout-Logik (ehemals in der UIFactory)
    var panel := PanelContainer.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    
    var vbox := VBoxContainer.new()
    panel.add_child(vbox)

    for action in actions:
        var btn := Button.new()
        btn.text = action.label
        btn.custom_minimum_size = Vector2(200, 50)
        btn.pressed.connect(func():
            container.queue_free()
            Kernel.builder.execute_action(action)
        )
        vbox.add_child(btn)
        
    container.add_child(panel)
    hud.add_child(container)
    
    # Auto-Close Timer
    hud.get_tree().create_timer(5.0).timeout.connect(func():
        if is_instance_valid(container): container.queue_free()
    )
    
    Logger.log_debug("Kontextmenü für %d Aktionen angezeigt" % actions.size(), LOG_CAT)