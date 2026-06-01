# scripts/ui/visuals/interaction_button_visuals.gd
class_name InteractionButtonVisuals

var button: Button

func _init(parent: CanvasLayer, pos: Vector2) -> void:
    button = Button.new()
    button.text = "!"
    button.custom_minimum_size = Vector2(150, 150)
    button.position = pos # Position wird von außen diktiert
    parent.add_child(button)