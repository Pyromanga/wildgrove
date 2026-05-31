extends Node
class_name TouchInput

# --- Output-State (read-only für Player) ---
var js_vec: Vector2    = Vector2.ZERO
var cam_delta: Vector2 = Vector2.ZERO
var zoom_delta: float  = 0.0

# --- Signals für UI-Schicht ---
signal joystick_activated(origin: Vector2)
signal joystick_moved(origin: Vector2, offset: Vector2)
signal joystick_released()

# --- Interner State ---
var _js_finger: int     = -1
var _js_origin: Vector2 = Vector2.ZERO
const JS_RADIUS: float  = 90.0

var _right_fingers: Dictionary = {}
var _pinch_last_dist: float    = 0.0
var _cam_last: Vector2         = Vector2.ZERO
var _cam_finger: int           = -1

func _ready() -> void:
    add_to_group("touch_input")
    # State-Changes abonnieren statt Settings-Node suchen
    Kernel.events.system.state_changed.connect(_on_state_changed)

func _on_state_changed(new_state: int) -> void:
    # Bei jedem State-Wechsel Input zurücksetzen
    # (FREE→BUSY wenn Aktion startet, BUSY→FREE wenn sie endet)
    reset_input()

func reset_input() -> void:
    js_vec     = Vector2.ZERO
    cam_delta  = Vector2.ZERO
    zoom_delta = 0.0
    _js_finger = -1
    _right_fingers.clear()
    _cam_finger     = -1
    _pinch_last_dist = 0.0
    joystick_released.emit()  # UI versteckt Visuals selbst

func _unhandled_input(event: InputEvent) -> void:
    # Nur blocken wenn MENU offen — BUSY erlaubt Input (für cancel)
    if Kernel.states.get_state() == Kernel.states.PlayerState.MENU:
        js_vec    = Vector2.ZERO
        cam_delta = Vector2.ZERO
        return

    var sw := get_viewport().get_visible_rect().size.x

    if event is InputEventScreenTouch:
        _handle_touch(event, sw)
    elif event is InputEventScreenDrag:
        _handle_drag(event, sw)
    elif event is InputEventMouseMotion:
        if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
            cam_delta += event.relative
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            zoom_delta -= 1.0
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            zoom_delta += 1.0

func _handle_touch(event: InputEventScreenTouch, sw: float) -> void:
    if event.pressed:
        if event.position.x < sw * 0.5:
            if _js_finger < 0:
                _js_finger = event.index
                _js_origin = event.position
                joystick_activated.emit(_js_origin)
                joystick_moved.emit(_js_origin, Vector2.ZERO)
        else:
            _right_fingers[event.index] = event.position
            if _right_fingers.size() == 1:
                _cam_finger = event.index
                _cam_last   = event.position
            elif _right_fingers.size() == 2:
                _cam_finger = -1
                var keys := _right_fingers.keys()
                _pinch_last_dist = _right_fingers[keys[0]].distance_to(_right_fingers[keys[1]])
    else:
        if event.index == _js_finger:
            _js_finger = -1
            js_vec     = Vector2.ZERO
            joystick_released.emit()
        if event.index in _right_fingers:
            _right_fingers.erase(event.index)
            if _right_fingers.size() == 1:
                _cam_finger = _right_fingers.keys()[0]
                _cam_last   = _right_fingers[_cam_finger]
            else:
                _cam_finger = -1

func _handle_drag(event: InputEventScreenDrag, sw: float) -> void:
    if event.index == _js_finger:
        var delta   := event.position - _js_origin
        var clamped := delta.limit_length(JS_RADIUS)
        js_vec = clamped / JS_RADIUS
        joystick_moved.emit(_js_origin, clamped)
    elif event.index in _right_fingers:
        _right_fingers[event.index] = event.position
        if _right_fingers.size() == 2:
            var keys     := _right_fingers.keys()
            var new_dist := _right_fingers[keys[0]].distance_to(_right_fingers[keys[1]])
            if _pinch_last_dist > 0:
                zoom_delta += (_pinch_last_dist - new_dist) * 0.05
            _pinch_last_dist = new_dist
        elif event.index == _cam_finger:
            cam_delta += event.position - _cam_last
            _cam_last  = event.position