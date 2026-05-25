extends CanvasLayer
## HUD.gd — Joystick-Visuals, Settings-Button
## Reagiert auf ui_offset_changed Signal von Settings

signal settings_requested

const JS_RADIUS: float = 90.0

var _js_base: ColorRect
var _js_knob: ColorRect
var _settings_btn: Button
var _base_btn_pos: Vector2   # Ausgangsposition des Buttons
var _base_js_pos: Vector2    # Ausgangsposition des Joysticks


func _ready() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_build_joystick(vp)
	_build_settings_button(vp)
	_connect_touch_input()


func _build_joystick(vp: Vector2) -> void:
	_js_base = ColorRect.new()
	_js_base.size = Vector2(JS_RADIUS * 2, JS_RADIUS * 2)
	_js_base.color = Color(1, 1, 1, 0.15)
	_base_js_pos = Vector2(40, vp.y - JS_RADIUS * 2 - 60)
	_js_base.position = _base_js_pos
	add_child(_js_base)

	_js_knob = ColorRect.new()
	_js_knob.size = Vector2(60, 60)
	_js_knob.color = Color(1, 1, 1, 0.8)
	_js_knob.position = _js_base.position + Vector2(JS_RADIUS - 30, JS_RADIUS - 30)
	add_child(_js_knob)


func _build_settings_button(vp: Vector2) -> void:
	_settings_btn = Button.new()
	_settings_btn.text = "⚙"
	# Größer und weiter von der Ecke weg
	_settings_btn.custom_minimum_size = Vector2(90, 90)
	_base_btn_pos = Vector2(vp.x - 110, 40)
	_settings_btn.position = _base_btn_pos
	_settings_btn.add_theme_font_size_override("font_size", 44)
	_settings_btn.pressed.connect(func() -> void: emit_signal("settings_requested"))
	add_child(_settings_btn)


func _connect_touch_input() -> void:
	var nodes: Array = get_tree().get_nodes_in_group("touch_input")
	if nodes.size() > 0:
		nodes[0].register_joystick_visuals(_js_base, _js_knob)


func apply_ui_offset(offset: Vector2) -> void:
	# Joystick verschieben
	var new_js: Vector2 = _base_js_pos + offset
	_js_base.position = new_js
	_js_knob.position = new_js + Vector2(JS_RADIUS - 30, JS_RADIUS - 30)

	# Settings-Button verschieben (nur Y, X bleibt rechts)
	_settings_btn.position = _base_btn_pos + Vector2(0, offset.y)
