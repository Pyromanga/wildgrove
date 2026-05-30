extends Node
class_name TouchInput

var js_vec: Vector2    = Vector2.ZERO
var cam_delta: Vector2 = Vector2.ZERO
var zoom_delta: float  = 0.0

var _js_finger: int     = -1
var _js_origin: Vector2 = Vector2.ZERO
const JS_RADIUS: float  = 90.0

var _right_fingers: Dictionary = {}
var _pinch_last_dist: float    = 0.0
var _cam_last: Vector2         = Vector2.ZERO
var _cam_finger: int           = -1
var _right_press_pos: Dictionary = {}

var _js_base: ColorRect = null
var _js_knob: ColorRect = null

func _ready() -> void:
    add_to_group("touch_input")

func register_joystick_visuals(base: ColorRect, knob: ColorRect) -> void:
    _js_base = base
    _js_knob = knob

func reset() -> void:
    js_vec = Vector2.ZERO
    cam_delta = Vector2.ZERO
    zoom_delta = 0.0
    _js_finger = -1
    _right_fingers.clear()
    _right_press_pos.clear()
    _cam_finger = -1
    _pinch_last_dist = 0.0
    if _js_base: _js_base.visible = false
    if _js_knob: _js_knob.visible = false

func _is_settings_open() -> bool:
    var nodes = get_tree().get_nodes_in_group("settings")
    if nodes.size() > 0 and nodes[0].has_method("is_settings_open"):
        return nodes[0].is_settings_open()
    return false

func _input(event: InputEvent) -> void:
    if _is_settings_open():
        js_vec = Vector2.ZERO
        cam_delta = Vector2.ZERO
        return

    var sw = get_viewport().get_visible_rect().size.x

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
        elif event.button_index == MOUSE_BUTTON_LEFT:
            _try_player_interact()

func _handle_touch(event: InputEventScreenTouch, sw: float) -> void:
    if event.pressed:
        if event.position.x < sw * 0.5:
            if _js_finger < 0:
                _js_finger = event.index
                _js_origin = event.position
                if _js_base: _js_base.visible = true
                if _js_knob: _js_knob.visible = true
                _update_js_visuals(_js_origin, Vector2.ZERO)
        else:
            _right_fingers[event.index] = event.position
            _right_press_pos[event.index] = event.position
            if _right_fingers.size() == 1:
                _cam_finger = event.index
                _cam_last = event.position
            elif _right_fingers.size() == 2:
                _cam_finger = -1
                var keys = _right_fingers.keys()
                _pinch_last_dist = _right_fingers[keys[0]].distance_to(_right_fingers[keys[1]])
    else:
        if event.index == _js_finger:
            _js_finger = -1
            js_vec = Vector2.ZERO
            if _js_base: _js_base.visible = false
            if _js_knob: _js_knob.visible = false
            _reset_js_visuals()
        if event.index in _right_fingers:
            var start_pos = _right_press_pos.get(event.index, event.position)
            var moved = event.position.distance_to(start_pos)
            _right_press_pos.erase(event.index)
            _right_fingers.erase(event.index)

            if moved < 20.0 and _right_fingers.size() == 0:
                _try_player_interact()

            if _right_fingers.size() == 1:
                _cam_finger = _right_fingers.keys()[0]
                _cam_last = _right_fingers[_cam_finger]
            else:
                _cam_finger = -1

func _handle_drag(event: InputEventScreenDrag, sw: float) -> void:
    if event.index == _js_finger:
        var delta = event.position - _js_origin
        var clamped = delta.limit_length(JS_RADIUS)
        js_vec = clamped / JS_RADIUS
        _update_js_visuals(_js_origin, clamped)
    elif event.index in _right_fingers:
        _right_fingers[event.index] = event.position
        if _right_fingers.size() == 2:
            var keys = _right_fingers.keys()
            var new_dist = _right_fingers[keys[0]].distance_to(_right_fingers[keys[1]])
            if _pinch_last_dist > 0:
                zoom_delta += (_pinch_last_dist - new_dist) * 0.05
            _pinch_last_dist = new_dist
        elif event.index == _cam_finger:
            cam_delta += event.position - _cam_last
            _cam_last = event.position

func _try_player_interact() -> void:
    var players = get_tree().get_nodes_in_group("player")
    if players.size() > 0 and players[0].has_method("try_interact"):
        players[0].try_interact()

func _update_js_visuals(origin: Vector2, offset: Vector2) -> void:
    if _js_base: _js_base.global_position = origin - Vector2(JS_RADIUS, JS_RADIUS)
    if _js_knob: _js_knob.global_position = origin + offset - (_js_knob.size * 0.5)

func _reset_js_visuals() -> void:
    if _js_base and _js_knob:
        _js_knob.global_position = _js_base.global_position + Vector2(JS_RADIUS, JS_RADIUS) - (_js_knob.size * 0.5)