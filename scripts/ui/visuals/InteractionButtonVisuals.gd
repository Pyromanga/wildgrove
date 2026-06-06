# scripts/ui/ressources/InteractionButtonVisuals.gd
class_name InteractionButtonVisuals

## FIX: Button war initial sichtbar (visible=true ist Godot-Default).
## InteractionButtonController ruft set_active(false) erst nach _ready() auf,
## aber _ready() feuert erst wenn der Controller in den Tree eingefügt wird.
## Zwischen HUD-Erstellung und Tree-Einfügen war der Button kurz sichtbar.
## Lösung: visible = false direkt im _init() setzen.

var button: Button


func _init(parent: CanvasLayer, pos: Vector2) -> void:
	button = Button.new()
	button.text = "!"
	button.custom_minimum_size = Vector2(150, 150)
	button.position = pos
	button.visible = false  # FIX: Initial versteckt — Controller schaltet ein wenn Ziel da
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(button)


func set_active(active: bool) -> void:
	button.visible = active
