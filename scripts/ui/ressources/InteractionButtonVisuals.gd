# scripts/ui/visuals/interaction_button_visuals.gd
class_name InteractionButtonVisuals

var button: Button

func _init(parent: CanvasLayer) -> void:
    button = Button.new()
    button.text = "!"
    button.custom_minimum_size = Vector2(150, 150)
    # Layout wird über den LayoutManager gesetzt
    button.position = LayoutManager.get_action_button_position(0)
    parent.add_child(button)

func set_active(is_active: bool) -> void:
    button.self_modulate = Color.WHITE if is_active else Color(0.4, 0.4, 0.4)