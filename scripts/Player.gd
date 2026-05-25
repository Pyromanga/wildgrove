extends CharacterBody3D
## Player.gd — Spieler-Bewegung & Kamera
## Liest Input von TouchInput via Gruppe "touch_input"
## Einstellung "cam_relative" kommt von Settings via Gruppe "settings"

const SPEED: float   = 5.5
const GRAVITY: float = 9.8
const ZOOM_MIN: float = 3.0
const ZOOM_MAX: float = 16.0

var _spring_arm: SpringArm3D
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("player")
	_build_mesh()
	_build_camera()
	position = Vector3(0, 0.9, 0)


func _build_mesh() -> void:
	# Kollision
	var col := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.4
	caps.height = 1.0
	col.shape = caps
	col.position.y = 0.9
	add_child(col)

	# Sichtbares Mesh
	_mesh = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	_mesh.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.6, 0.05)
	_mesh.material_override = mat
	_mesh.position.y = 0.9
	add_child(_mesh)


func _build_camera() -> void:
	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = 8.0
	_spring_arm.position = Vector3(0, 1.5, 0)
	_spring_arm.rotation_degrees.x = -35.0
	add_child(_spring_arm)

	var cam := Camera3D.new()
	cam.current = true
	_spring_arm.add_child(cam)


func _physics_process(delta: float) -> void:
	var touch := _get_touch()
	if not touch:
		return

	var input_vec: Vector2 = touch.js_vec
	var cam_relative: bool = _get_setting("cam_relative", true)

	if input_vec.length() > 0.05:
		var dir: Vector3
		if cam_relative:
			var basis: Basis = _spring_arm.global_transform.basis
			var fwd: Vector3   = Vector3(-basis.z.x, 0, -basis.z.z).normalized()
			var right: Vector3 = Vector3(basis.x.x,  0,  basis.x.z).normalized()
			dir = (fwd * input_vec.y + right * input_vec.x).normalized()
		else:
			dir = Vector3(input_vec.x, 0, -input_vec.y).normalized()

		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED

		# Mesh in Bewegungsrichtung drehen
		var target_y: float = atan2(dir.x, dir.z)
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, target_y, 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * 8 * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * 8 * delta)

	# Schwerkraft
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	# Kamera-Rotation & Zoom von TouchInput
	if touch.cam_delta != Vector2.ZERO:
		_spring_arm.rotation.y -= touch.cam_delta.x * 0.007
		_spring_arm.rotation.x = clamp(
			_spring_arm.rotation.x - touch.cam_delta.y * 0.007,
			deg_to_rad(-65), deg_to_rad(-10)
		)
		touch.cam_delta = Vector2.ZERO

	if touch.zoom_delta != 0.0:
		_spring_arm.spring_length = clamp(
			_spring_arm.spring_length + touch.zoom_delta,
			ZOOM_MIN, ZOOM_MAX
		)
		touch.zoom_delta = 0.0


func _get_touch() -> Node:
	var nodes: Array = get_tree().get_nodes_in_group("touch_input")
	return nodes[0] if nodes.size() > 0 else null


func _get_setting(key: String, default_val: Variant) -> Variant:
	var nodes: Array = get_tree().get_nodes_in_group("settings")
	if nodes.size() > 0 and nodes[0].has_method("get_setting"):
		return nodes[0].get_setting(key)
	return default_val
