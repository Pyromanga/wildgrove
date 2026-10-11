# scripts/ui/visuals/ContextButtonVisuals.gd
class_name ContextButtonVisuals

## ContextButtonVisuals — der Kontext-Button (☰) rechts unten neben dem Interaction-Button.
##
## FIX 1: visible = false initial — erst wenn ein Ziel in Reichweite ist.
## FIX 2: Absolute Position durch Anchor-Positionierung ersetzt.

var button: Button

func _init(parent: CanvasLayer) -> void:
	button = Button.new()
	button.name = "ContextButton"
	button.text = "☰"
	button.custom_minimum_size = Vector2(120, 120)

	# Anchor: rechts unten, links vom Interaction-Button
	button.anchor_left = 0.70
	button.anchor_right = 0.70
	button.anchor_top = 0.85
	button.anchor_bottom = 0.85
	button.offset_left = -60
	button.offset_right = 60
	button.offset_top = -60
	button.offset_bottom = 60

	button.visible = false  # Initial versteckt
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(button)
