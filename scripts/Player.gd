extends CharacterBody3D
## Player.gd — Bewegung, Kamera und Interaktion

const SPEED: float = 5.5
const GRAVITY: float = 9.8

# Kamera-Einstellungen
var _target_zoom: float = 8.0
var _target_yaw: float = 0.0
var _target_pitch: float = deg_to_rad(-35.0)

# Nodes
var _spring_arm: SpringArm3D
var _mesh: MeshInstance3D

func _ready() -> void:
	add_to_group("player")
	_build_player_nodes()
	position = Vector3(0, 1.0, 0)

func _build_player_nodes() -> void:
	# Kollision
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.position.y = 1.0
	add_child(col)

	# Visuelles Modell (Kapsel)
	_mesh = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4; cm.height = 1.8
	_mesh.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.6, 0.05) # Orange
	_mesh.material_override = mat
	_mesh.position.y = 1.0
	add_child(_mesh)

	# Kamera-System
	_spring_arm = SpringArm3D.new()
	_spring_arm.position = Vector3(0, 1.5, 0)
	_spring_arm.spring_length = _target_zoom
	add_child(_spring_arm)

	var cam := Camera3D.new()
	cam.current = true
	_spring_arm.add_child(cam)

# --- Interaktion ---

func try_interact() -> void:
	# Sucht das nächste Interactable in 4m Umkreis
	var interactables = get_tree().get_nodes_in_group("interactable")
	var closest: Node3D = null
	var dist: float = 4.0

	for node in interactables:
		var d = global_position.distance_to(node.global_position)
		if d < dist:
			dist = d
			closest = node

	if closest and closest.has_method("interact"):
		closest.interact(self)
	elif closest and closest.has_method("start_interaction"):
		# Falls wir die neue Komponenten-Logik nutzen
		closest.start_interaction()

# --- Physik & Bewegung ---

func _physics_process(delta: float) -> void:
	var touch = _get_touch_input()
	if not touch: return

	_handle_camera(touch, delta)
	_handle_movement(touch, delta)

func _handle_movement(touch: Node, delta: float) -> void:
	var input_vec = touch.js_vec # Vector2 vom Joystick
	
	if input_vec.length() > 0.1:
		# Bewegung relativ zur Kamera-Blickrichtung
		var basis = _spring_arm.global_transform.basis
		var fwd = Vector3(-basis.z.x, 0, -basis.z.z).normalized()
		var right = Vector3(basis.x.x, 0, basis.x.z).normalized()
		
		# Joystick hoch (-y) soll vorwärts sein
		var dir = (fwd * -input_vec.y + right * input_vec.x).normalized()
		
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		
		# Modell in Laufrichtung drehen
		var target_angle = atan2(dir.x, dir.z)
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, target_angle, 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	move_and_slide()

func _handle_camera(touch: Node, delta: float) -> void:
	# Drehung per Touch (cam_delta kommt vom TouchInput)
	if touch.cam_delta != Vector2.ZERO:
		_target_yaw -= touch.cam_delta.x * 0.005
		_target_pitch = clamp(_target_pitch - touch.cam_delta.y * 0.005, deg_to_rad(-70), deg_to_rad(-10))
		touch.cam_delta = Vector2.ZERO # Reset nach Verarbeitung

	# Glätten der Kamera-Bewegung
	_spring_arm.rotation.y = lerp_angle(_spring_arm.rotation.y, _target_yaw, 10.0 * delta)
	_spring_arm.rotation.x = lerp(_spring_arm.rotation.x, _target_pitch, 10.0 * delta)

func _get_touch_input() -> Node:
	var nodes = get_tree().get_nodes_in_group("touch_input")
	return nodes[0] if nodes.size() > 0 else null