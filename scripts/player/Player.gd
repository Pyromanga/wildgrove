extends CharacterBody3D

@onready var speed: float = Kernel.data.get_player_stat("speed", 6.0)
@onready var gravity: float = Kernel.data.get_player_stat("gravity", 12.0)
@onready var interact_range: float = Kernel.data.get_player_stat("interact_range", 4.0)

var _target_zoom: float = 8.0
var _target_yaw: float = 0.0
var _target_pitch: float = deg_to_rad(-35.0)

var _spring_arm: SpringArm3D
var _mesh: MeshInstance3D
var _touch: TouchInput 

func _ready() -> void:
	add_to_group("player")
	_build_player_nodes()
	position = Vector3(0, 1.5, 0)
	Logger.log_debug("Player bereit", "Player")

func _physics_process(delta: float) -> void:
	if _touch == null:
		return
	if not Kernel.states.is_free():
		if _touch.js_vec.length() > 0.3:
			Kernel.events.player.emit_movement_interrupted()
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	_handle_camera(_touch, delta)
	_handle_movement(_touch, delta)

func _handle_camera(touch: TouchInput, delta: float) -> void:
	var c_delta: Vector2 = touch.cam_delta
	touch.cam_delta = Vector2.ZERO
	var z_delta: float = touch.zoom_delta
	touch.zoom_delta = 0.0

	if c_delta != Vector2.ZERO:
		_target_yaw -= c_delta.x * 0.006
		_target_pitch = clamp(_target_pitch - c_delta.y * 0.005, deg_to_rad(-75), deg_to_rad(0))
	
	if z_delta != 0.0:
		_target_zoom = clamp(_target_zoom + z_delta, 3.0, 15.0)

	_spring_arm.rotation.y = lerp_angle(_spring_arm.rotation.y, _target_yaw, 10.0 * delta)
	_spring_arm.rotation.x = lerp(_spring_arm.rotation.x, _target_pitch, 10.0 * delta)
	_spring_arm.spring_length = lerp(_spring_arm.spring_length, _target_zoom, 5.0 * delta)

func _handle_movement(touch: Node, delta: float) -> void:
	var input: Vector2 = touch.js_vec
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
		
	if input.length() > 0.1:
		var move_dir: Vector3 = Kernel.utils.calculate_move_direction(_spring_arm, input)
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, atan2(move_dir.x, move_dir.z), 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	move_and_slide()

# --- Interaktions-Logik ---

func try_default_interact() -> void:
	_with_closest_target(func(target: Node3D):
		var logic = target
		if not target.has_method("start_default_interaction"):
			for child in target.get_children():
				if child.has_method("start_default_interaction"):
					logic = child
					break
		
		if logic.has_method("start_default_interaction"):
			logic.start_default_interaction()
		else:
			Logger.log_debug("Keine Standard-Aktion auf " + target.name, "Player")
	)

func _get_closest_interactable() -> Node3D:
	return Kernel.utils.get_closest_node(global_position, "interactable", interact_range)

func _with_closest_target(callback: Callable) -> void:
	var target: Node3D = _get_closest_interactable()
	if not target:
		Logger.log_debug("Kein Ziel in Reichweite", "Player")
		return
	callback.call(target)

func _build_player_nodes() -> void:
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.position.y = 1.0
	add_child(col)

	_mesh = MeshInstance3D.new()
	_mesh.mesh = CapsuleMesh.new()
	_mesh.position.y = 1.0
	add_child(_mesh)

	_spring_arm = SpringArm3D.new()
	_spring_arm.position = Vector3(0, 1.6, 0)
	add_child(_spring_arm)

	var cam := Camera3D.new()
	cam.current = true
	_spring_arm.add_child(cam)

	var touch_node := Node.new()
	touch_node.name = "TouchInput"
	touch_node.set_script(load("res://scripts/player/TouchInput.gd"))
	add_child(touch_node)
	_touch = touch_node as TouchInput
	
func try_open_context_menu() -> void:
	Logger.log_debug("Kontext-Menü Button gedrückt", "Player")
	_with_closest_target(func(target: Node3D):
		Logger.log_debug("Ziel für Kontext gefunden: " + target.name, "Player")
		
		# SUCHE NACH DER LOGIK: Entweder auf dem Node selbst oder in den Kindern
		var interactable_logic = target
		if not target.has_method("get_actions"):
			for child in target.get_children():
				if child.has_method("get_actions"):
					interactable_logic = child
					break
		
		if interactable_logic.has_method("get_actions"):
			var actions = interactable_logic.get_actions()
			if actions.is_empty():
				Logger.log_debug("Interactable hat keine Aktionen definiert", "Player")
				return
			Kernel.ui_factory.show_context_menu(actions)
		else:
			Logger.log_debug("Keine Interactable-Logik auf " + target.name + " gefunden!", "Player")
	)