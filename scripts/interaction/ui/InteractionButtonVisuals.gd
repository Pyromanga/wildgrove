# scripts/ui/visuals/InteractionButtonVisuals.gd
class_name InteractionButtonVisuals

## FIX 1: Button war initial sichtbar (visible=true ist Godot-Default).
## FIX 2: Absolute Position durch Anchor-Positionierung ersetzt — korrekt auf
##         allen Auflösungen. Rechts unten (80% horizontal, 85% vertikal).

var button: Button

func _init(parent: CanvasLayer, _pos: Vector2) -> void:
	button = Button.new()
	button.name = "InteractionButton"
	button.text = "!"
	button.custom_minimum_size = Vector2(120, 120)

	# Anchor: rechts unten — unabhängig von der Fenstergröße
	button.anchor_left = 0.85
	button.anchor_right = 0.85
	button.anchor_top = 0.85
	button.anchor_bottom = 0.85
	button.offset_left = -60
	button.offset_right = 60
	button.offset_top = -60
	button.offset_bottom = 60

	button.visible = false  # Initial versteckt — Controller schaltet ein wenn Ziel da
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(button)

func set_active(active: bool) -> void:
	button.visible = active

## Verbindet den Button mit einem Callable (wird vom Controller gesetzt).
func connect_pressed(callback: Callable) -> void:
	# Vorherige Verbindungen trennen um Doppel-Callbacks zu vermeiden
	if button.pressed.is_connected(callback):
		return
	button.pressed.connect(callback)
