extends RefCounted
class_name NotificationController

const LOG_CAT := "UI/Notification"

func show(hud: CanvasLayer, text: String) -> void:
    # Bestehende Popups aufräumen
    for n in hud.get_tree().get_nodes_in_group("popup_message"):
        n.queue_free()

    var container := Control.new()
    container.add_to_group("popup_message")
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var panel := PanelContainer.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    panel.custom_minimum_size = Vector2(400, 100)
    
    # Style (hier kannst du deinen StyleBoxFlat wiederverwenden)
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0, 0, 0, 0.85)
    sb.set_content_margin_all(16)
    sb.set_corner_radius_all(8)
    panel.add_theme_stylebox_override("panel", sb)

    var lbl := Label.new()
    lbl.text = text
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    panel.add_child(lbl)
    
    container.add_child(panel)
    hud.add_child(container)
    
    # Auto-Close Timer
    hud.get_tree().create_timer(3.0).timeout.connect(func():
        if is_instance_valid(container): container.queue_free()
    )
    
    Logger.log_debug("Popup angezeigt: " + text, LOG_CAT)