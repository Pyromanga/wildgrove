extends Node3D
class_name Interactable

var target: InteractableObject = null

func _ready() -> void:
    Logger.log_debug("Interactable._ready() für Parent: " + get_parent().name, "Interactable")
    if has_meta("target"):
        target = get_meta("target")
        _setup_detection_area()
    else:
        Logger.log_error("Interactable: kein 'target' Meta!", "Interactable")

func _setup_detection_area() -> void:
    var label := Label3D.new()
    label.text = target.get_default_action().label if target.get_default_action() else ""
    label.position = Vector3(0, 2.5, 0)
    label.pixel_size = 0.01
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = Color(1, 1, 0)
    label.visible = false
    add_child(label)

    var area := Area3D.new()
    var col := CollisionShape3D.new()
    col.shape = SphereShape3D.new()
    col.shape.radius = 2.0
    area.add_child(col)
    add_child(area)

    area.body_entered.connect(func(b: Node3D):
        if b.is_in_group("player"):
            label.visible = true
            Logger.log_debug("Spieler in Reichweite: " + target.name, "Interactable")
    )
    area.body_exited.connect(func(b: Node3D):
        if b.is_in_group("player"):
            label.visible = false
    )

func start_default_interaction() -> void:
    if not target:
        return
    var action = target.get_default_action()
    if action:
        Kernel.builder.execute_action(action)

func get_actions() -> Array[InteractableAction]:
    if target:
        return target.actions
    return []