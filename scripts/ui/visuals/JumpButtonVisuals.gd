class_name JumpButtonVisuals

var button: Button

func _init(parent: CanvasLayer) -> void:
	button = Button.new()
	button.name = "JumpButton"
	button.text = "▲"
	button.custom_minimum_size = Vector2(120, 120)
	button.anchor_left   = 0.85
	button.anchor_right  = 0.85
	button.anchor_top    = 0.75
	button.anchor_bottom = 0.75
	button.offset_left   = 60
	button.offset_right  = 180
	button.offset_top    = -60
	button.offset_bottom = 60
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(button)

func connect_pressed(cb: Callable) -> void:
	if not button.pressed.is_connected(cb):
		button.pressed.connect(cb)
