# scripts/ui/ressources/ContextButtonVisuals.gd
class_name ContextButtonVisuals

## ContextButtonVisuals — der Kontext-Button (☰) unten rechts.
##
## FIX: visible = false initial — erst wenn ein Ziel in Reichweite ist,
## soll dieser Button sichtbar sein (wird von ContextButtonController gesteuert).

var button: Button


func _init(parent: CanvasLayer) -> void:
	button = Button.new()
	button.text = "☰"
	button.custom_minimum_size = Vector2(150, 150)
	button.position = LayoutManager.get_action_button_position(1)
	button.visible = false  # FIX: Initial versteckt
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(button)
