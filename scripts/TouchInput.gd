extends Node
## TouchInput.gd — Touch & Maus Input
##
## Zwei Modi (per Setting "fixed_joystick"):
##
## FIXED (EIN, Standard):
##   Erster Finger links  = Joystick (Ursprung bleibt wo er aufgesetzt hat)
##   Zweiter Finger irgendwo = Kamera drehen ODER Pinch-Zoom
##   → man kann gleichzeitig laufen + Kamera drehen
##
## DYNAMIC (AUS):
##   Joystick-Ursprung springt zu jedem neuen Fingertipp links
##   Rechte Seite = Kamera, Zwei Finger = Pinch

# ── Öffentlich — von Player.gd gelesen ────────────────────────────────────
var js_vec: Vector2    = Vector2.ZERO
var cam_delta: Vector2 = Vector2.ZERO
var zoom_delta: float  = 0.0

# ── Joystick ───────────────────────────────────────────────────────────────
var _js_finger: int     = -1
var _js_origin: Vector2 = Vector2.ZERO
const JS_RADIUS: float  = 90.0

# ── Kamera-Swipe (Dynamic-Modus) ───────────────────────────────────────────
var _cam_finger: int    = -1
var _cam_last: Vector2  = Vector2.ZERO

# ── Zweiter Finger (Fixed-Modus) ───────────────────────────────────────────
# Wird für Kamera UND Pinch gleichzeitig genutzt
var _second_finger: int     = -1
var _second_last: Vector2   = Vector2.ZERO

# ── Pinch ──────────────────────────────────────────────────────────────────
var _all_fingers: Dictionary = {}   # index → Vector2 (alle aktiven Finger)
var _pinch_last_dist: float  = 0.0
var _pinching: bool          = false

# ── Visuals ────────────────────────────────────────────────────────────────
var _js_base: ColorRect = null
var _js_knob: ColorRect = null


func _ready() -> void:
	add_to_group("touch_input")


func register_joystick_visuals(base: ColorRect, knob: ColorRect) -> void:
	_js_base = base
	_js_knob = knob


func _get_fixed_mode() -> bool:
	var nodes: Array = get_tree().get_nodes_in_group("settings")
	if nodes.size() > 0 and nodes[0].has_method("get_setting"):
		var val = nodes[0].get_setting("fixed_joystick")
		if val != null:
			return val
	return true


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
		_all_fingers[event.index] = pos

		if _get_fixed_mode():
			# ── FIXED MODUS ────────────────────────────────────────────
			if _js_finger < 0 and pos.x < sw * 0.55:
				# Erster Finger links = Joystick
				_js_finger = event.index
				_js_origin = pos
				_update_js_visuals(pos, Vector2.ZERO)
			elif _js_finger >= 0 and _second_finger < 0 and event.index != _js_finger:
				# Zweiter Finger (egal wo) = Kamera + potentiell Pinch
				_second_finger = event.index
				_second_last = pos
				if _all_fingers.size() == 2:
					_pinch_last_dist = (_all_fingers[_js_finger] as Vector2).distance_to(pos)
		else:
			# ── DYNAMIC MODUS ──────────────────────────────────────────
			if pos.x < sw * 0.5:
				if _js_finger < 0:
					_js_finger = event.index
					_js_origin = pos
					_update_js_visuals(pos, Vector2.ZERO)
			else:
				if _cam_finger < 0:
					_cam_finger = event.index
					_cam_last = pos
			# Pinch: zwei Finger aktiv
			if _all_fingers.size() == 2:
				var keys: Array = _all_fingers.keys()
				_pinch_last_dist = (_all_fingers[keys[0]] as Vector2).distance_to(
					_all_fingers[keys[1]] as Vector2
				)
	else:
		_all_fingers.erase(event.index)
		_pinching = false
		_pinch_last_dist = 0.0

		if event.index == _js_finger:
			_js_finger = -1
			js_vec = Vector2.ZERO
			_reset_js_visuals()
		if event.index == _cam_finger:
			_cam_finger = -1
		if event.index == _second_finger:
			_second_finger = -1


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index in _all_fingers:
		_all_fingers[event.index] = event.position

	if _get_fixed_mode():
		# ── FIXED MODUS ────────────────────────────────────────────────
		if event.index == _js_finger:
			# Joystick bewegen
			var delta: Vector2   = event.position - _js_origin
			var clamped: Vector2 = delta.limit_length(JS_RADIUS)
			js_vec = clamped / JS_RADIUS
			_update_js_visuals(_js_origin, clamped)

		elif event.index == _second_finger and _second_finger >= 0:
			# Zweiter Finger: Pinch-Zoom wenn beide bewegen, sonst Kamera
			if _js_finger >= 0 and _js_finger in _all_fingers:
				var js_pos: Vector2 = _all_fingers[_js_finger]
				var new_dist: float = js_pos.distance_to(event.position)
				var dist_change: float = abs(new_dist - _pinch_last_dist)

				if dist_change > 3.0 and _pinch_last_dist > 0.0:
					# Distanz ändert sich merklich = Pinch-Zoom
					zoom_delta += (_pinch_last_dist - new_dist) * 0.025
					_pinch_last_dist = new_dist
				else:
					# Distanz gleich = Kamera-Swipe
					var d: Vector2 = event.position - _second_last
					cam_delta += d
				_pinch_last_dist = new_dist
			else:
				var d: Vector2 = event.position - _second_last
				cam_delta += d
			_second_last = event.position
	else:
		# ── DYNAMIC MODUS ──────────────────────────────────────────────
		if _all_fingers.size() == 2 and _pinch_last_dist > 0.0:
			var keys: Array = _all_fingers.keys()
			var new_dist: float = (_all_fingers[keys[0]] as Vector2).distance_to(
				_all_fingers[keys[1]] as Vector2
			)
			zoom_delta += (_pinch_last_dist - new_dist) * 0.025
			_pinch_last_dist = new_dist
			if event.index == _js_finger:
				var delta: Vector2   = event.position - _js_origin
				var clamped: Vector2 = delta.limit_length(JS_RADIUS)
				js_vec = clamped / JS_RADIUS
				_update_js_visuals(_js_origin, clamped)
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
