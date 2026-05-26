extends CharacterBody3D
## Player.gd — Spieler-Bewegung, Kamera, Interaktion

const SPEED: float       = 5.5
const GRAVITY: float     = 9.8
const ZOOM_MIN: float    = 3.0
const ZOOM_MAX: float    = 16.0
const CAM_SMOOTH: float  = 14.0
const ZOOM_SMOOTH: float = 8.0

var _spring_arm: SpringArm3D
var _mesh: MeshInstance3D
var _current_interactable: Node = null

var _target_yaw: float   = 0.0
var _target_pitch: float = deg_to_rad(-35.0)
var _target_zoom: float  = 8.0


func _ready() -> void:
	add_to_group("player")
	_build_mesh()
	_build_camera()
	_build_interact_hint()
	position = Vector3(0, 0.9, 0)


func _build_mesh() -> void:
	var col := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.4
	caps.height = 1.0
	col.shape = caps
	col.position.y = 0.9
	add_child(col)

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
	_spring_arm.spring_length = _target_zoom
	_spring_arm.position = Vector3(0, 1.5, 0)
	_spring_arm.rotation.x = _target_pitch
	add_child(_spring_arm)

	var cam := Camera3D.new()
	cam.current = true
	_spring_arm.add_child(cam)


func _build_interact_hint() -> void:
	var lbl := Label3D.new()
	lbl.name = "InteractHint"
	lbl.text = ""
	lbl.font_size = 48
	lbl.modulate = Color(1, 1, 0.2, 1.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 2.8, 0)
	lbl.visible = false
	add_child(lbl)


# ── Interaktion ────────────────────────────────────────────────────────────
func show_interact_hint(label: String) -> void:
	var hint := get_node_or_null("InteractHint")
	if hint:
		hint.text = "[ " + label + " ]"
		hint.visible = true


func hide_interact_hint() -> void:
	var hint := get_node_or_null("InteractHint")
	if hint:
		hint.visible = false
	_current_interactable = null


func try_interact() -> void:
	var interactables: Array = get_tree().get_nodes_in_group("interactable")
	var closest: Node3D = null
	var closest_dist: float = 3.0

	for node in interactables:
		if node is Node3D:
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < closest_dist:
				closest_dist = d
				closest = node

	if closest and closest.has_method("interact"):
		closest.interact(self)
		_current_interactable = closest


# ── Physik ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	var touch: Node = _get_touch()
	if not touch:
		return
	_handle_movement(touch, delta)
	_handle_camera(touch, delta)


func _handle_movement(touch: Node, delta: float) -> void:
	var input_vec: Vector2 = touch.js_vec

	var cam_relative: bool = true
	var raw: Variant = _get_setting("cam_relative")
	if raw != null:
		cam_relative = bool(raw)

	# joystick_inverted: EIN = hoch → vorwärts (intuitiv), AUS = hoch → rückwärts
	var inverted: bool = false
	var inv_raw: Variant = _get_setting("joystick_inverted")
	if inv_raw != null:
		inverted = bool(inv_raw)

	if input_vec.length() > 0.05:
		var dir: Vector3
		# Y-Achse: positiv = Joystick hoch
		# Kamera schaut von hinten → vorwärts = -input_vec.y damit hoch = vorwärts
		var forward_input: float = -input_vec.y if not inverted else input_vec.y

		if cam_relative:
			var basis: Basis   = _spring_arm.global_transform.basis
			var fwd: Vector3   = Vector3(-basis.z.x, 0, -basis.z.z).normalized()
			var right: Vector3 = Vector3( basis.x.x, 0,  basis.x.z).normalized()
			dir = (fwd * forward_input + right * input_vec.x).normalized()
		else:
			dir = Vector3(input_vec.x, 0, forward_input).normalized()

		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED

		var target_y: float = atan2(dir.x, dir.z)
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, target_y, 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * 8 * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * 8 * delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	move_and_slide()


func _handle_camera(touch: Node, delta: float) -> void:
	if touch.cam_delta != Vector2.ZERO:
		_target_yaw  -= touch.cam_delta.x * 0.007
		_target_pitch = clamp(
			_target_pitch - touch.cam_delta.y * 0.007,
			deg_to_rad(-65), deg_to_rad(-10)
		)
		touch.cam_delta = Vector2.ZERO

	if touch.zoom_delta != 0.0:
		_target_zoom = clamp(_target_zoom + touch.zoom_delta, ZOOM_MIN, ZOOM_MAX)
		touch.zoom_delta = 0.0

	var cam_smooth: float  = CAM_SMOOTH
	var zoom_smooth: float = ZOOM_SMOOTH
	var cs: Variant = _get_setting("cam_smooth")
	var zs: Variant = _get_setting("zoom_smooth")
	if cs != null: cam_smooth  = float(cs)
	if zs != null: zoom_smooth = float(zs)

	_spring_arm.rotation.y = lerp_angle(
		_spring_arm.rotation.y, _target_yaw, cam_smooth * delta
	)
	_spring_arm.rotation.x = lerp(
		_spring_arm.rotation.x, _target_pitch, cam_smooth * delta
	)
	_spring_arm.spring_length = lerp(
		_spring_arm.spring_length, _target_zoom, zoom_smooth * delta
	)


func _get_touch() -> Node:
	var nodes: Array = get_tree().get_nodes_in_group("touch_input")
	return nodes[0] if nodes.size() > 0 else null


func _get_setting(key: String) -> Variant:
	var nodes: Array = get_tree().get_nodes_in_group("settings")
	if nodes.size() > 0 and nodes[0].has_method("get_setting"):
		return nodes[0].get_setting(key)
	return null

func try_interact() -> void:
	var interactables: Array = get_tree().get_nodes_in_group("interactable")
	var closest: Node3D = null
	var closest_dist: float = 4.0 # Radius etwas erhöht

	for node in interactables:
		var d: float = global_position.distance_to(node.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = node

	if closest and closest.has_method("interact"):
		closest.interact(self)