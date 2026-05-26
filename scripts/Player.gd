extends CharacterBody3D
## Player.gd — Kernel-optimierte Fassung

@onready var speed: float = Kernel.data.get_player_stat("speed", 6.0)
@onready var gravity: float = Kernel.data.get_player_stat("gravity", 12.0)
@onready var interact_range: float = Kernel.data.get_player_stat("interact_range", 4.0)

var _target_zoom: float = 8.0
var _target_yaw: float = 0.0
var _target_pitch: float = deg_to_rad(-35.0)

var _spring_arm: SpringArm3D
var _mesh: MeshInstance3D

func _ready() -> void:
    add_to_group("player")
    _build_player_nodes()
    position = Vector3(0, 1.5, 0)

func _physics_process(delta: float) -> void:
    if not Kernel.states.is_free(): 
        velocity.x = 0
        velocity.z = 0
        move_and_slide()
        return

    var touch = Kernel.touch
    _handle_camera(touch, delta)
    _handle_movement(touch, delta)

func _handle_camera(touch: Node, delta: float) -> void:
    if touch.cam_delta != Vector2.ZERO:
        _target_yaw -= touch.cam_delta.x * 0.006
        _target_pitch = clamp(_target_pitch - touch.cam_delta.y * 0.005, deg_to_rad(-75), deg_to_rad(0))
        touch.cam_delta = Vector2.ZERO

    if touch.zoom_delta != 0:
        _target_zoom = clamp(_target_zoom + touch.zoom_delta, 3.0, 15.0)
        touch.zoom_delta = 0

    _spring_arm.rotation.y = lerp_angle(_spring_arm.rotation.y, _target_yaw, 10.0 * delta)
    _spring_arm.rotation.x = lerp(_spring_arm.rotation.x, _target_pitch, 10.0 * delta)
    _spring_arm.spring_length = lerp(_spring_arm.spring_length, _target_zoom, 5.0 * delta)

func _handle_movement(touch: Node, delta: float) -> void:
    var input = touch.js_vec
    
    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = 0

    if input.length() > 0.1:
        var move_dir = Kernel.utils.calculate_move_direction(_spring_arm, input)
        velocity.x = move_dir.x * speed
        velocity.z = move_dir.z * speed
        _mesh.rotation.y = lerp_angle(_mesh.rotation.y, atan2(move_dir.x, move_dir.z), 10.0 * delta)
    else:
        velocity.x = move_toward(velocity.x, 0, speed)
        velocity.z = move_toward(velocity.z, 0, speed)

    move_and_slide()

func try_interact() -> void:
    var target = Kernel.utils.get_closest_node(global_position, "interactable", interact_range)
    if target:
        if target.has_method("start_interaction"):
            target.start_interaction()
        elif target.has_method("interact"):
            target.interact(self)

func _build_player_nodes() -> void:
    var col := CollisionShape3D.new()
    col.shape = CapsuleShape3D.new()
    col.position.y = 1.0
    add_child(col)

    _mesh = MeshInstance3D.new()
    var cm := CapsuleMesh.new()
    cm.radius = 0.4; cm.height = 1.8
    _mesh.mesh = cm
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.4, 0.1)
    _mesh.material_override = mat
    _mesh.position.y = 1.0
    add_child(_mesh)

    _spring_arm = SpringArm3D.new()
    _spring_arm.position = Vector3(0, 1.6, 0)
    _spring_arm.spring_length = _target_zoom
    _spring_arm.add_excluded_object(get_rid()) 
    add_child(_spring_arm)

    var cam := Camera3D.new()
    cam.current = true
    _spring_arm.add_child(cam)