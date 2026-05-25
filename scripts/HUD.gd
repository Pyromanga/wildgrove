extends CanvasLayer
## HUD.gd — Heads-Up Display
## Zuständig für: Joystick-Visuals, Settings-Button
## Kommuniziert mit TouchInput via register_joystick_visuals()

signal settings_requested

var _js_base: ColorRect
var _js_knob: ColorRect

const JS_RADIUS: float = 90.0


func _ready() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_build_joystick(vp)
	_build_settings_button(vp)
	_connect_touch_input()


func _build_joystick(vp: Vector2) -> void:
	_js_base = ColorRect.new()
	_js_base.size = Vector2(JS_RADIUS * 2, JS_RADIUS * 2)
	_js_base.color = Color(1, 1, 1, 0.15)
	_js_base.position = Vector2(30, vp.y - JS_RADIUS * 2 - 30)
	add_child(_js_base)

	_js_knob = ColorRect.new()
	_js_knob.size = Vector2(60, 60)
	_js_knob.color = Color(1, 1, 1, 0.8)
	_js_knob.position = _js_base.position + Vector2(JS_RADIUS - 30, JS_RADIUS - 30)
	add_child(_js_knob)


func _build_settings_button(vp: Vector2) -> void:
	var btn := Button.new()
	btn.text = "⚙"
	btn.position = Vector2(vp.x - 90, 20)
	btn.size = Vector2(70, 70)
	btn.add_theme_font_size_override("font_size", 36)
	btn.pressed.connect(func() -> void: emit_signal("settings_requested"))
	add_child(btn)


func _connect_touch_input() -> void:
	# TouchInput braucht Referenz auf die Joystick-Visuals
	var nodes: Array = get_tree().get_nodes_in_group("touch_input")
	if nodes.size() > 0:
		nodes[0].register_joystick_visuals(_js_base, _js_knob)
