extends Node
## TouchInput.gd — Verarbeitet alle Touch- und Maus-Eingaben
## Schreibt Ergebnisse in öffentliche Variablen
## Player.gd liest diese jedes Frame

# Öffentliche Variablen — von Player.gd gelesen
var js_vec: Vector2    = Vector2.ZERO  # Joystick-Richtung (-1..1)
var cam_delta: Vector2 = Vector2.ZERO  # Kamera-Bewegung diesen Frame
var zoom_delta: float  = 0.0           # Zoom-Änderung diesen Frame

# Joystick
var _js_finger: int    = -1
var _js_origin: Vector2 = Vector2.ZERO
const JS_RADIUS: float  = 90.0

# Kamera-Swipe
var _cam_finger: int   = -1
var _cam_last: Vector2 = Vector2.ZERO

# Pinch-Zoom
var _pinch_b: int      = -1
var _pinch_pos_a: Vector2 = Vector2.ZERO
var _pinch_pos_b: Vector2 = Vector2.ZERO
var _pinch_last_dist: float = 0.0

# Referenz auf Joystick-Visuals in HUD
var _js_base: ColorRect = null
var _js_knob: ColorRect = null


func _ready() -> void:
	add_to_group("touch_input")


func register_joystick_visuals(base: ColorRect, knob: ColorRect) -> void:
	_js_base = base
	_js_knob = knob


func _input(event: InputEvent) -> void:
	var sw: float = get_viewport().get_visible_rect().size.x

	if event is InputEventScreenTouch:
		_handle_touch(event, sw)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			cam_delta += event.relative
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_delta -= 0.5
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_delta += 0.5


func _handle_touch(event: InputEventScreenTouch, sw: float) -> void:
	var pos: Vector2 = event.position
	if event.pressed:
		# Zweiter Finger für Pinch
		if _js_finger >= 0 and _pinch_b < 0 and event.index != _js_finger:
			_pinch_b = event.index
			_pinch_pos_b = pos
			_pinch_last_dist = _pinch_pos_a.distance_to(_pinch_pos_b)
			return

		if pos.x < sw * 0.5:
			if _js_finger < 0:
				_js_finger = event.index
				_pinch_pos_a = pos
				_js_origin = pos
				_update_js_visuals(pos, Vector2.ZERO)
		else:
			if _cam_finger < 0:
				_cam_finger = event.index
				_pinch_pos_a = pos
				_cam_last = pos
	else:
		if event.index == _js_finger:
			_js_finger = -1
			_pinch_b = -1
			js_vec = Vector2.ZERO
			_reset_js_visuals()
		if event.index == _cam_finger:
			_cam_finger = -1
			_pinch_b = -1
		if event.index == _pinch_b:
			_pinch_b = -1
			_pinch_last_dist = 0.0


func _handle_drag(event: InputEventScreenDrag) -> void:
	# Pinch-Zoom — beide Finger aktiv
	if _pinch_b >= 0:
		if event.index == _js_finger or event.index == _cam_finger:
			_pinch_pos_a = event.position
		elif event.index == _pinch_b:
			_pinch_pos_b = event.position

		var new_dist: float = _pinch_pos_a.distance_to(_pinch_pos_b)
		if _pinch_last_dist > 0.0:
			zoom_delta += (_pinch_last_dist - new_dist) * 0.02
		_pinch_last_dist = new_dist
		return

	if event.index == _js_finger:
		var delta: Vector2   = event.position - _js_origin
		var clamped: Vector2 = delta.limit_length(JS_RADIUS)
		js_vec = clamped / JS_RADIUS
		_update_js_visuals(_js_origin, clamped)

	elif event.index == _cam_finger:
		var d: Vector2 = event.position - _cam_last
		_cam_last = event.position
		cam_delta += d


func _update_js_visuals(origin: Vector2, offset: Vector2) -> void:
	if _js_base:
		_js_base.position = origin - Vector2(JS_RADIUS, JS_RADIUS)
	if _js_knob:
		_js_knob.position = origin + offset - Vector2(30, 30)


func _reset_js_visuals() -> void:
	if _js_base and _js_knob:
		_js_knob.position = _js_base.position + Vector2(JS_RADIUS - 30, JS_RADIUS - 30)
