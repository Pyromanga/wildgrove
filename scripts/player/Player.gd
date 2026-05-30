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
    Logger.log_debug("Player _ready() start", "Player")
    add_to_group("player")
    _build_player_nodes()
    position = Vector3(0, 1.5, 0)
    Logger.log_debug("Player _ready() fertig, touch: " + str(_touch), "Player")

func _physics_process(delta: float) -> void:
    if _touch == null:
        return
    if not Kernel.states.is_free():
        if _touch.js_vec.length() > 0.3:
            Kernel.builder.cancel_interaction()
        velocity.x = 0
        velocity.z = 0
        move_and_slide()
        return
    _handle_camera(_touch, delta)
    _handle_movement(_touch, delta)

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

func try_default_interact() -> void:
    Logger.log_debug("[Player] try_default_interact aufgerufen", "Player")
    var target = _get_closest_interactable()
    if not target:
        Logger.log_debug("[Player] Kein Interactable in Reichweite", "Player")
        return
    if target.has_method("start_default_interaction"):
        Logger.log_debug("[Player] start_default_interaction auf " + target.name, "Player")
        target.start_default_interaction()
    else:
        Logger.log_debug("[Player] Target hat keine start_default_interaction", "Player")

func try_open_context_menu() -> void:
    Logger.log_debug("[Player] try_open_context_menu aufgerufen", "Player")
    var target = _get_closest_interactable()
    if not target:
        Logger.log_debug("[Player] Kein Interactable in Reichweite", "Player")
        return
    if target.has_method("get_actions"):
        var actions = target.get_actions()
        Logger.log_debug("[Player] " + str(actions.size()) + " Aktionen gefunden", "Player")
        if actions.size() > 0:
            Kernel.ui_factory.show_context_menu(actions)
        else:
            Logger.log_debug("[Player] Keine Aktionen vorhanden", "Player")
    else:
        Logger.log_debug("[Player] Target hat keine get_actions", "Player")

func _get_closest_interactable() -> Node3D:
    return Kernel.utils.get_closest_node(global_position, "interactable", interact_range)

# ... (der gesamte restliche Code aus dem bisherigen Player.gd)

func _build_player_nodes() -> void:
    Logger.log_debug("_build_player_nodes() START", "Player")

    var col := CollisionShape3D.new()
    col.shape = CapsuleShape3D.new()
    col.position.y = 1.0
    add_child(col)

    _mesh = MeshInstance3D.new()
    var cm := CapsuleMesh.new()
    cm.radius = 0.4
    cm.height = 1.8
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

    var touch_node := Node.new()
    touch_node.name = "TouchInput"
    touch_node.set_script(load("res://scripts/player/TouchInput.gd"))
    add_child(touch_node)
    _touch = touch_node as TouchInput

    call_deferred("_setup_joystick_visuals")
    Logger.log_debug("_build_player_nodes() ENDE", "Player")

func _setup_joystick_visuals() -> void:
    Logger.log_debug("_setup_joystick_visuals() start", "Player")
    var hud_nodes := get_tree().get_nodes_in_group("hud")
    Logger.log_debug("HUD nodes: " + str(hud_nodes.size()), "Player")
    if hud_nodes.is_empty():
        Logger.log_error("Kein HUD gefunden!", "Player")
        get_tree().node_added.connect(_on_node_added)
        return
    _attach_joystick_to_hud(hud_nodes[0])

func _on_node_added(node: Node) -> void:
    if node.is_in_group("hud"):
        get_tree().node_added.disconnect(_on_node_added)
        _attach_joystick_to_hud(node)

func _attach_joystick_to_hud(hud: Node) -> void:
    Logger.log_debug("_attach_joystick_to_hud() start", "Player")
    var visuals: Array = Kernel.ui_factory.create_joystick_visuals()
    var base: ColorRect = visuals[0]
    var knob: ColorRect = visuals[1]
    hud.add_child(base)
    hud.add_child(knob)
    _touch.register_joystick_visuals(base, knob)
    Logger.log_debug("Joystick registriert!", "Player")