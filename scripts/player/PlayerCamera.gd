extends SpringArm3D
class_name PlayerCamera

const LOG_CAT := "Camera"

@export var touch_sensitivity: float = 0.006
@export var zoom_speed: float = 5.0
@export var rotation_speed: float = 10.0

var _target_zoom: float = 8.0
var _target_yaw: float = 0.0
var _target_pitch: float = deg_to_rad(-35.0)

var camera: Camera3D


func _init() -> void:
	position = Vector3(0, 1.6, 0)
	spring_length = _target_zoom
	collision_mask = 1
	_build_camera()


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)


func handle_input(inp: TouchInput, delta: float) -> void:
	_process_rotation(inp, delta)
	_process_zoom(inp, delta)


func _process_rotation(inp: TouchInput, delta: float) -> void:
	var c_delta := inp.cam_delta
	inp.cam_delta = Vector2.ZERO
	if c_delta != Vector2.ZERO:
		_target_yaw -= c_delta.x * touch_sensitivity
		_target_pitch = clamp(
			_target_pitch - c_delta.y * touch_sensitivity, deg_to_rad(-75.0), deg_to_rad(0.0)
		)
	rotation.y = lerp_angle(rotation.y, _target_yaw, rotation_speed * delta)
	rotation.x = lerp(rotation.x, _target_pitch, rotation_speed * delta)


func _process_zoom(inp: TouchInput, delta: float) -> void:
	var z_delta := inp.zoom_delta
	inp.zoom_delta = 0.0
	if z_delta != 0.0:
		_target_zoom = clamp(_target_zoom + z_delta, 3.0, 15.0)
	spring_length = lerp(spring_length, _target_zoom, zoom_speed * delta)
