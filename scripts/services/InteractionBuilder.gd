extends ServiceBase
class_name InteractionBuilder


class Task:
    var target: Node3D
    var label: String = "Interagieren"
    var duration: float = 2.0
    var on_done: Callable

    func _init(node: Node3D) -> void:
        target = node

    func set_label(l: String) -> Task:
        label = l
        return self

    func set_duration(d: float) -> Task:
        duration = d
        return self

    func on_complete(c: Callable) -> Task:
        on_done = c
        return self

    func build() -> Node3D:
        var interactable := Node3D.new()
        # Gruppe NICHT hier setzen – liegt auf InteractableObject selbst
        interactable.set_script(load("res://scripts/world/objects/Interactable.gd"))  # ← objects
        interactable.set_meta("task", self)
        target.add_child(interactable)
        return interactable


func execute_interaction(task: Task) -> void:
    Logger.log_debug("START execute_interaction für: " + task.label, "Builder")

    if not is_instance_valid(task.target):
        Logger.log_error("ABBRUCH: Target Instanz nicht mehr valide!", "Builder")
        return

    if not task.on_done.is_valid():
        Logger.log_warn("Kein gültiger Callback für '%s' – nur BUSY-Zeit wird abgewartet." % task.label, "Builder")

    Kernel.states.set_state(Kernel.states.PlayerState.BUSY)
    Logger.log_debug("Spieler ist jetzt BUSY", "Builder")

    var hud_root: Node = Kernel.hud if Kernel.hud else get_tree().root

    var bar: ProgressBar = Kernel.ui_factory.create_progress_bar(250.0)
    bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    hud_root.add_child(bar)

    var tween: Tween = bar.create_tween()
    tween.tween_property(bar, "value", 100.0, task.duration).from(0.0)
    await tween.finished

    bar.queue_free()

    if task.on_done.is_valid():
        Logger.log_debug("Rufe Callback auf...", "Builder")
        task.on_done.call()

    Kernel.states.set_state(Kernel.states.PlayerState.FREE)
    Logger.log_debug("Interaktion beendet, Spieler wieder FREE", "Builder")


func create(node: Node3D) -> Task:
    return Task.new(node)


func is_interactable(node: Node) -> bool:
    return node.is_in_group("interactable")


func trigger_interaction(target: Node3D) -> void:
    if is_interactable(target):
        var task := create(target).set_duration(0.1)
        Kernel.events.interaction_started.emit(task.label, task.duration)
        execute_interaction(task)