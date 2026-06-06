extends CharacterBody3D

## Player.gd — Zentraler Spieler-Controller.
## Nutzt das neue Services-System und den EventBus.

const LOG_CAT := "Player"

# Stats — werden im _load_stats() befüllt
var _speed: float = 6.0
var _gravity: float = 12.0
var _interact_range: float = 4.0

# Kamera-State
var _target_zoom: float = 8.0
var _target_yaw: float = 0.0
var _target_pitch: float = deg_to_rad(-35.0)

# Nodes
var _spring_arm: SpringArm3D
var _mesh: MeshInstance3D
var _touch: TouchInput
var _sensor: InteractionSensor

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────


func _ready() -> void:
	add_to_group("player")
	_load_stats()
	_build_nodes()
	Logger.log_debug("Player bereit.", LOG_CAT)


func _physics_process(delta: float) -> void:
	if not _touch:
		return

	# NEU: Nutzung des PlayerStateService
	if not Services.player_states.is_free():
		# Wenn BUSY (z.B. Hacken) und Joystick wird stark bewegt -> Abbruch
		if _touch.js_vec.length() > 0.3:
			EventBus.player.emit_movement_interrupted()

		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_handle_camera(_touch, delta)
	_handle_movement(_touch, delta)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func try_default_interact() -> void:
	var target := _sensor.get_closest() if _sensor else null
	if not target:
		Logger.log_debug("Kein Ziel in Reichweite.", LOG_CAT)
		return

	if target.has_method("start_default_interaction"):
		target.start_default_interaction()
	else:
		Logger.log_warn("Ziel '%s' ist nicht interagierbar." % target.name, LOG_CAT)


func get_closest_interactable() -> Node3D:
	return _sensor.get_closest() if _sensor else null


# ─────────────────────────────────────────────
# Privat — Kamera & Bewegung
# ─────────────────────────────────────────────


func _load_stats() -> void:
	# NEU: Sicherer Zugriff auf DataService
	if not Services.data:
		Logger.log_warn("DataService fehlt - nutze Defaults.", LOG_CAT)
		return

	_speed = Services.data.get_player_stat("speed", _speed)
	_gravity = Services.data.get_player_stat("gravity", _gravity)
	_interact_range = Services.data.get_player_stat("interact_range", _interact_range)


func _handle_camera(touch: TouchInput, delta: float) -> void:
	var c_delta := touch.cam_delta
	touch.cam_delta = Vector2.ZERO
	var z_delta := touch.zoom_delta
	touch.zoom_delta = 0.0

	if c_delta != Vector2.ZERO:
		_target_yaw -= c_delta.x * 0.006
		_target_pitch = clamp(_target_pitch - c_delta.y * 0.005, deg_to_rad(-75.0), deg_to_rad(0.0))

	if z_delta != 0.0:
		_target_zoom = clamp(_target_zoom + z_delta, 3.0, 15.0)

	_spring_arm.rotation.y = lerp_angle(_spring_arm.rotation.y, _target_yaw, 10.0 * delta)
	_spring_arm.rotation.x = lerp(_spring_arm.rotation.x, _target_pitch, 10.0 * delta)
	_spring_arm.spring_length = lerp(_spring_arm.spring_length, _target_zoom, 5.0 * delta)


func _handle_movement(touch: TouchInput, delta: float) -> void:
	var input := touch.js_vec

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if input.length() > 0.1:
		var move_dir := MathHelper.calculate_move_direction(_spring_arm, input)
		velocity.x = move_dir.x * _speed
		velocity.z = move_dir.z * _speed
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, atan2(move_dir.x, move_dir.z), 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, _speed)
		velocity.z = move_toward(velocity.z, 0.0, _speed)

	move_and_slide()


# ─────────────────────────────────────────────
# Node-Aufbau
# ─────────────────────────────────────────────


func _build_nodes() -> void:
	_build_collision()
	_build_mesh()
	_build_camera()
	_build_touch_input()
	_build_sensor()


func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 1.0, 0.0)
	add_child(col)


func _build_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = CapsuleMesh.new()
	_mesh.position = Vector3(0.0, 1.0, 0.0)
	add_child(_mesh)


func _build_camera() -> void:
	_spring_arm = SpringArm3D.new()
	_spring_arm.position = Vector3(0.0, 1.6, 0.0)
	add_child(_spring_arm)

	var cam := Camera3D.new()
	cam.current = true
	_spring_arm.add_child(cam)


func _build_touch_input() -> void:
	# Falls du TouchInput.gd als Script hast
	var touch_script = load("res://scripts/player/TouchInput.gd")
	_touch = Node.new()
	_touch.name = "TouchInput"
	_touch.set_script(touch_script)
	add_child(_touch)
	_touch.add_to_group("touch_input")


func _build_sensor() -> void:
	_sensor = InteractionSensor.new()
	_sensor.name = "InteractionSensor"
	# Hier könntest du die Reichweite aus den Stats anwenden:
	# _sensor.set_range(_interact_range)
	add_child(_sensor)
