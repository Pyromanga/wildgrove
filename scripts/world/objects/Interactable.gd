extends Node3D
class_name Interactable

var target: InteractableObject = null

var _label: Label3D = null
var _bar_3d: Factory3D.Bar3D = null
var _bar_tween: Tween = null

func setup(interactable_target: InteractableObject) -> void:
    target = interactable_target
    _setup_visuals()
    _setup_detection_area()
    _connect_builder_signals()
    Logger.log_debug("Interactable bereit: " + target.name, "Interactable")

func _setup_visuals() -> void:
    _label = Label3D.new()
    _label.text = target.get_default_action().label if target.get_default_action() else ""
    _label.position = Vector3(0, 2.5, 0)
    _label.pixel_size = 0.01
    _label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _label.modulate = Color(1, 1, 0)
    _label.visible = false
    add_child(_label)

    _bar_3d = Kernel.factory3d.create_3d_bar(self)
    _bar_3d.position.y = 3.0

func _setup_detection_area() -> void:
    var area := Area3D.new()
    var col := CollisionShape3D.new()
    col.shape = SphereShape3D.new()
    col.shape.radius = target.detection_radius
    area.add_child(col)
    add_child(area)
    area.body_entered.connect(func(b: Node3D):
        if b.is_in_group("player"):
            call_deferred("_refresh_label_visibility")
    )
    area.body_exited.connect(func(b: Node3D):
        if b.is_in_group("player"):
            _label.visible = false
    )

func _refresh_label_visibility() -> void:
    var players := get_tree().get_nodes_in_group("player")
    if players.is_empty():
        return
    var closest := Kernel.utils.get_closest_node(
        players[0].global_position, "interactable", 999.0
    )
    _label.visible = (closest == target)  # closest ist InteractableObject (in gruppe)

func _connect_builder_signals() -> void:
    Kernel.builder.interaction_started.connect(_on_interaction_started)
    Kernel.builder.interaction_completed.connect(_on_interaction_ended)
    Kernel.builder.interaction_cancelled.connect(_on_interaction_ended)

func _on_interaction_started(label: String, duration: float) -> void:
    var default_action := target.get_default_action()
    if not default_action or default_action.label != label:
        return
    _bar_3d.visible = true
    _bar_tween = create_tween()
    _bar_tween.tween_method(
        func(v: float): _bar_3d.update(v),
        0.0, 1.0, duration
    )

func _on_interaction_ended(_label: String) -> void:
    if _bar_tween:
        _bar_tween.kill()
        _bar_tween = null
    _bar_3d.visible = false
    _bar_3d.update(0.0)

# --- Player-API ---
func start_default_interaction() -> void:
    var action := target.get_default_action() if target else null
    if action:
        Kernel.builder.execute_action(action)

func get_actions() -> Array[InteractableAction]:
    return target.actions if target else []