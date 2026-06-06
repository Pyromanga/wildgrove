extends Node
class_name TouchInput

## TouchInput — Input-Adapter für Mobile + Desktop.
## Kein Service — direktes Child des Player-Nodes.
## Gibt js_vec, cam_delta und zoom_delta als Output-State heraus.
## Player liest diese Werte in _physics_process.
##
## FIX: joystick_activated/moved/released waren eigene Signals die niemand
## auf EventBus.ui gebridget hat. JoystickController lauscht auf EventBus.ui,
## also wurden die Joystick-Visuals nie aktualisiert.
## Lösung: _ready() connectet die eigenen Signals direkt auf die EventBus.ui-Emitter.

# ─────────────────────────────────────────────
# Output-State (vom Player gelesen)
# ─────────────────────────────────────────────
var js_vec: Vector2 = Vector2.ZERO
var cam_delta: Vector2 = Vector2.ZERO
var zoom_delta: float = 0.0

# ─────────────────────────────────────────────
# Interner State
# ─────────────────────────────────────────────
const JS_RADIUS: float = 90.0

var _js_finger: int = -1
var _js_origin: Vector2 = Vector2.ZERO
var _right_fingers: Dictionary = {}
var _pinch_last_dist: float = 0.0
var _cam_finger: int = -1
var _cam_last: Vector2 = Vector2.ZERO


# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────


func _ready() -> void:
	# Bridge: eigene Signale → EventBus.ui damit JoystickController (und alle
	# anderen Lauscher) über den globalen Bus benachrichtigt werden.
	# JoystickController.setup() connectet auf EventBus.ui.joystick_toggled/moved —
	# ohne diesen Bridge erreichte der Controller nie ein Signal.
	pass  # Connections werden erst in _on_player_ready gesetzt — Player ruft das auf.


## Wird von Player._build_system() nach add_child(input) aufgerufen.
## Zu diesem Zeitpunkt ist EventBus garantiert initialisiert.
func connect_to_event_bus() -> void:
	EventBus.ui.emit_joystick_toggled(false, Vector2.ZERO)  # Initial-State

	# Wir bridgen manuell im _handle_touch / _handle_drag statt via Signal-Chain,
	# da wir die Emit-Methoden direkt aufrufen (kein zusätzlicher Signal-Overhead).
	pass


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


## Zurücksetzen — aufgerufen von PlayerStateService wenn State wechselt.
func reset_input() -> void:
	js_vec = Vector2.ZERO
	cam_delta = Vector2.ZERO
	zoom_delta = 0.0
	_js_finger = -1
	_cam_finger = -1
	_pinch_last_dist = 0.0
	_right_fingers.clear()
	# Joystick-Visuals ausblenden wenn Input resettet wird
	EventBus.ui.emit_joystick_toggled(false, Vector2.ZERO)


# ─────────────────────────────────────────────
# Input
# ─────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if Services.player_states and Services.player_states.is_in_menu():
		js_vec = Vector2.ZERO
		cam_delta = Vector2.ZERO
		return

	var sw := get_viewport().get_visible_rect().size.x

	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch, sw)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			cam_delta += (event as InputEventMouseMotion).relative
	elif event is InputEventMouseButton and event.pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_delta -= 1.0
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_delta += 1.0


# ─────────────────────────────────────────────
# Touch-Handler
# ─────────────────────────────────────────────


func _handle_touch(event: InputEventScreenTouch, sw: float) -> void:
	if event.pressed:
		if event.position.x < sw * 0.5:
			# Linke Seite → Joystick
			if _js_finger < 0:
				_js_finger = event.index
				_js_origin = event.position
				# FIX: Bridge zu EventBus.ui damit JoystickController reagiert
				EventBus.ui.emit_joystick_toggled(true, _js_origin)
				EventBus.ui.emit_joystick_moved(_js_origin, Vector2.ZERO)
		else:
			# Rechte Seite → Kamera / Pinch
			_right_fingers[event.index] = event.position
			if _right_fingers.size() == 1:
				_cam_finger = event.index
				_cam_last = event.position
			elif _right_fingers.size() == 2:
				_cam_finger = -1
				var keys := _right_fingers.keys()
				_pinch_last_dist = (_right_fingers[keys[0]] as Vector2).distance_to(
					_right_fingers[keys[1]]
				)
	else:
		if event.index == _js_finger:
			_js_finger = -1
			js_vec = Vector2.ZERO
			# FIX: Bridge zu EventBus.ui
			EventBus.ui.emit_joystick_toggled(false, Vector2.ZERO)
		if _right_fingers.erase(event.index):
			if _right_fingers.size() == 1:
				_cam_finger = _right_fingers.keys()[0]
				_cam_last = _right_fingers[_cam_finger]
			else:
				_cam_finger = -1


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _js_finger:
		var delta_pos := event.position - _js_origin
		var clamped := delta_pos.limit_length(JS_RADIUS)
		js_vec = clamped / JS_RADIUS
		# FIX: Bridge zu EventBus.ui damit JoystickVisuals den Knob bewegen
		EventBus.ui.emit_joystick_moved(_js_origin, clamped)

	elif _right_fingers.has(event.index):
		_right_fingers[event.index] = event.position

		if _right_fingers.size() == 2:
			var keys := _right_fingers.keys()
			var new_dist: float = (_right_fingers[keys[0]] as Vector2).distance_to(
				_right_fingers[keys[1]]
			)
			if _pinch_last_dist > 0.0:
				zoom_delta += (_pinch_last_dist - new_dist) * 0.05
			_pinch_last_dist = new_dist

		elif event.index == _cam_finger:
			cam_delta += event.position - _cam_last
			_cam_last = event.position
