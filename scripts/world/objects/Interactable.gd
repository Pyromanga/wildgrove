extends Node3D
class_name Interactable

var task = null

func _ready() -> void:
    Logger.log_debug("Interactable._ready() START für Parent: " + str(get_parent().name), "Interactable")
    if has_meta("task"):
        task = get_meta("task")
        _setup_detection_area()
        Logger.log_debug("Interactable: Task gefunden, Area erstellt. Label: " + task.label, "Interactable")
    else:
        Logger.log_error("Interactable: Kein 'task' Meta gefunden!", "Interactable")

func _setup_detection_area() -> void:
    var label := Label3D.new()
    label.text = task.label
    label.position = Vector3(0, 2.5, 0)
    label.pixel_size = 0.01
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = Color(1, 1, 0)  # Gelb, gut sichtbar
    label.visible = false
    add_child(label)

    var area := Area3D.new()
    var col := CollisionShape3D.new()
    col.shape = SphereShape3D.new()
    col.shape.radius = 2.0
    area.add_child(col)
    add_child(area)

    area.body_entered.connect(
        func(b: Node3D):
            if b.is_in_group("player"):
                label.visible = true
                Logger.log_debug(">>> SPIELER IN INTERACTIONS-REICHWEITE: " + task.label + " bei " + str(global_position), "Interactable")
    )
    area.body_exited.connect(
        func(b: Node3D):
            if b.is_in_group("player"):
                label.visible = false
    )

func start_interaction() -> void:
    if task and Kernel.states.is_free():
        Kernel.builder.execute_interaction(task)
    elif not Kernel.states.is_free():
        Logger.log_debug("ABBRUCH start_interaction: Spieler nicht FREE", "Interactable")