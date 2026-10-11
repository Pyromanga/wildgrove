class_name MountVisuals

## MountVisuals — Schaltfläche "Aufsteigen"/"Absteigen" über dem Sprung-Knopf (rechts unten).
## Nur sichtbar, wenn ein eigenes Reittier in Reichweite ist oder man gerade reitet.

var button: Button

func _init(parent: CanvasLayer) -> void:
	button = Button.new()
	button.name = "MountButton"
	button.text = ""
	button.custom_minimum_size = Vector2(140, 100)
	button.anchor_left   = 0.85
	button.anchor_right  = 0.85
	button.anchor_top    = 0.75
	button.anchor_bottom = 0.75
	button.offset_left   = 50
	button.offset_right  = 190
	button.offset_top    = -190
	button.offset_bottom = -90
	button.add_theme_font_size_override("font_size", 20)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.visible = false
	parent.add_child(button)

func connect_pressed(cb: Callable) -> void:
	if not button.pressed.is_connected(cb):
		button.pressed.connect(cb)

func show_mount(label: String) -> void:
	button.text = "Aufsteigen\n%s" % label
	button.visible = true

func show_dismount(label: String) -> void:
	button.text = "Absteigen\n%s" % label
	button.visible = true

func hide_button() -> void:
	button.visible = false
