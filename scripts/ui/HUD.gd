extends CanvasLayer
class_name HUD

func show_floating_text(text: String, color: Color, font_size: int = 24, duration: float = 2.0) -> void:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.self_modulate = color
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    label.position = Vector2(0, -100)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(label)
    
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(label, "position", label.position + Vector2(0, -80), duration)
    tween.tween_property(label, "self_modulate:a", 0.0, duration).from(1.0)
    tween.tween_callback(label.queue_free).set_delay(duration)