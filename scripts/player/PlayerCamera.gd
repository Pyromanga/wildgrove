extends SpringArm3D
class_name PlayerCamera

## PlayerCamera — Verwaltet Rotation, Zoom und Smoothing der Kamera.
## Erbt von SpringArm3D, um automatische Kollision mit der Welt zu nutzen.

const LOG_CAT := "Camera"

# Konfiguration
@export var mouse_sensitivity: float = 0.005
@export var touch_sensitivity: float = 0.006
@export var zoom_speed:        float = 5.0
@export var rotation_speed:    float = 10.0

# Interner State
var _target_zoom:  float = 8.0
var _target_yaw:   float = 0.0
var _target_pitch: float = deg_to_rad(-35.0)

var camera: Camera3D

func _init() -> void:
	# SpringArm Grund-Setup
	position = Vector3(0, 1.6, 0) # Augenhöhe
	spring_length = _target_zoom
	
	# Damit die Kamera nicht durch Wände geht:
	# Layer 1 (Welt) sollte in der Maske sein
	collision_mask = 1 
	
	_build_camera()

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)
	Logger.log_debug("Camera3D instanziiert und an SpringArm gebunden.", LOG_CAT)

## Wird vom Player in jedem Frame aufgerufen
func handle_input(input: TouchInput, delta: float) -> void:
	_process_rotation(input, delta)
	_process_zoom(input, delta)

func _process_rotation(input: TouchInput, delta: float) -> void:
	var c_delta := input.cam_delta
	input.cam_delta = Vector2.ZERO # Delta nach Verbrauch nullen
	
	if c_delta != Vector2.ZERO:
		# Yaw (Horizontal) - Unbegrenzt
		_target_yaw -= c_delta.x * touch_sensitivity
		
		# Pitch (Vertikal) - Begrenzt (Clamping), damit man nicht über Kopf dreht
		_target_pitch -= c_delta.y * touch_sensitivity
		_target_pitch = clamp(_target_pitch, deg_to_rad(-75.0), deg_to_rad(0.0))

	# Sanftes Ausrichten der Rotation (Interpolation)
	rotation.y = lerp_angle(rotation.y, _target_yaw, rotation_speed * delta)
	rotation.x = lerp(rotation.x, _target_pitch, rotation_speed * delta)

func _process_zoom(input: TouchInput, delta: float) -> void:
	var z_delta := input.zoom_delta
	input.zoom_delta = 0.0
	
	if z_delta != 0.0:
		_target_zoom = clamp(_target_zoom + z_delta, 3.0, 15.0)
	
	# Sanfter Zoom-Übergang
	spring_length = lerp(spring_length, _target_zoom, zoom_speed * delta)