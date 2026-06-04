# scripts/ui/visuals/context_button_visuals.gd
class_name ContextButtonVisuals

var button: Button


func _init(parent: CanvasLayer) -> void:
	button = Button.new()
	button.text = "☰"
	button.custom_minimum_size = Vector2(150, 150)
	button.position = LayoutManager.get_action_button_position(1)
	parent.add_child(button)

# Hier könnten spezifische Dinge für das Kontextmenü hin (z.B. Highlight-Farbe)
