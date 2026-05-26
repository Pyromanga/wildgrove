extends CharacterBody3D
## Player.gd — Komplette Steuerung, Kamera und Interaktion

# Konstanten
const SPEED: float = 6.0
const GRAVITY: float = 12.0
const LERP_VAL: float = 10.0

# Kamera-Parameter
var _target_zoom: float = 8.0
var _target_yaw: float = 0.0
var _target_pitch: float = deg_to_rad(-35.0)

# Nodes
var _spring_arm: SpringArm3D
var _mesh: MeshInstance3D

func _ready() -> void:
	add_to_group("player")
	_build_player_nodes()
	# Startposition leicht über dem Boden
	position = Vector3(0, 1.5, 0)

func _build_player_nodes() -> void:
	# 1. Kollisions-Kapsel
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.position.y = 1.0
	add_child(col)

	# 2. Visuelles Modell
	_mesh = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4; cm.height = 1.8
	_mesh.mesh = cm
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.1) # Kräftiges Orange
	_mesh.material_override = mat
	_mesh.position.y = 1.0
	add_child(_mesh)

	# 3. Kamera-System (SpringArm verhindert Wand-Clipping)
	_spring_arm = SpringArm3D.new()
	_spring_arm.position = Vector3(0, 1.6, 0)
	_spring_arm.spring_length = _target_zoom
	# Maske 1 ausschließen, damit der Arm nicht am Player selbst hängen bleibt
	_spring_arm.add_excluded_object(get_rid()) 
	add_child(_spring_arm)

	var cam := Camera3D.new()
	cam.current = true
	_spring_arm.add_child(cam)

# --- Interaktion ---

func try_interact() -> void:
	var interactables = get_tree().get_nodes_in_group("interactable")
	var closest: Node3D = null
	var min_dist: float = 4.0

	for node in interactables:
		if node is Node3D:
			var d = global_position.distance_to(node.global_position)
			if d < min_dist:
				min_dist = d
				closest = node

	if closest:
		if closest.has_method("start_interaction"):
			closest.start_interaction()
		elif closest.has_method("interact"):
			closest.interact(self)

# --- Game Loop ---

func _physics_process(delta: float) -> void:
	var touch = _get_touch_input()
	if not touch:
		return

	_handle_camera(touch, delta)
	_handle_movement(touch, delta)

# --- Logik-Module ---

func _handle_camera(touch: Node, delta: float) -> void:
	# 1. Drehung (Swipe)
	if touch.cam_delta != Vector2.ZERO:
		_target_yaw -= touch.cam_delta.x * 0.006
		_target_pitch -= touch.cam_delta.y * 0.005
		_target_pitch = clamp(_target_pitch, deg_to_rad(-75), deg_to_rad(0))
		touch.cam_delta = Vector2.ZERO # Wichtig: Sofort resetten

	# 2. Zoom (Pinch oder Mausrad)
	if touch.zoom_delta != 0:
		_target_zoom = clamp(_target_zoom + touch.zoom_delta, 3.0, 15.0)
		touch.zoom_delta = 0 # Wichtig: Sofort resetten

	# 3. Glättung der Kamera-Werte
	_spring_arm.rotation.y = lerp_angle(_spring_arm.rotation.y, _target_yaw, LERP_VAL * delta)
	_spring_arm.rotation.x = lerp(_spring_arm.rotation.x, _target_pitch, LERP_VAL * delta)
	_spring_arm.spring_length = lerp(_spring_arm.spring_length, _target_zoom, 5.0 * delta)

func _handle_movement(touch: Node, delta: float) -> void:
	var input = touch.js_vec # Vector2 vom Joystick (-1 bis 1)
	
	# Schwerkraft
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0

	if input.length() > 0.1:
		# Richtung relativ zur Kamera berechnen
		var cam_basis = _spring_arm.global_transform.basis
		var forward = Vector3(-cam_basis.z.x, 0, -cam_basis.z.z).normalized()
		var right = Vector3(cam_basis.x.x, 0, cam_basis.x.z).normalized()
		
		# Joystick Vektor: Y ist oben/unten, X ist links/rechts
		var move_dir = (forward * -input.y + right * input.x).normalized()
		
		velocity.x = move_dir.x * SPEED
		velocity.z = move_dir.z * SPEED
		
		# Modell sanft in Laufrichtung drehen
		var target_rotation = atan2(move_dir.x, move_dir.z)
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, target_rotation, LERP_VAL * delta)

func _get_touch_input() -> Node:
	var nodes = get_tree().get_nodes_in_group("touch_input")
	if nodes.size() > 0:
		return nodes[0]
	return null