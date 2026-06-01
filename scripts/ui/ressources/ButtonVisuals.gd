# scripts/ui/visuals/button_visuals.gd
class_name ButtonVisuals

var interact_btn: Button
var context_btn: Button

func _init(parent: CanvasLayer) -> void:
    # Interact Button
    interact_btn = Button.new()
    interact_btn.text = "Interagieren"
    interact_btn.custom_minimum_size = Vector2(150, 50)
    interact_btn.position = Vector2(100, 500) # Beispielposition
    parent.add_child(interact_btn)
    
    # Context Button
    context_btn = Button.new()
    context_btn.text = "Optionen"
    context_btn.custom_minimum_size = Vector2(150, 50)
    context_btn.position = Vector2(300, 500) # Beispielposition
    parent.add_child(context_btn)

func set_active(is_active: bool) -> void:
    var color = Color.WHITE if is_active else Color(0.4, 0.4, 0.4)
    interact_btn.self_modulate = color
    context_btn.self_modulate = color