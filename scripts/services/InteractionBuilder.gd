extends ServiceBase
class_name InteractionBuilder
# (Rest bleibt identisch)
## InteractionBuilder.gd — Der Manager für Interaktions-Logik

class Task:
	var target: Node3D
	var label: String = "Interagieren"
	var duration: float = 2.0
	var on_done: Callable

	func _init(node: Node3D):
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
		var interactable = Node3D.new()
		interactable.add_to_group("interactable")
		interactable.set_script(load("res://scripts/Interactable.gd"))
		interactable.set_meta("task", self)
		target.add_child(interactable)
		return interactable

  func execute_interaction(task: Task) -> void:
    Logger.log_debug("START execute_interaction für: " + task.label, "Builder")
    
    if not is_instance_valid(task.target):
        Logger.log_error("ABBRUCH: Target Instanz nicht mehr valide!", "Builder")
        return

    # Check ob Callback da ist
    if not task.on_done.is_valid():
        Logger.log_error("ABBRUCH: Callback (on_done) ist ungültig für " + task.label, "Builder")
        return

    Kernel.states.set_state(Kernel.states.PlayerState.BUSY)
    Logger.log_debug("Player ist jetzt BUSY", "Builder")

    # 1. Sicherer HUD-Zugriff
    var hud = Kernel.hud if Kernel.hud else get_tree().root
    
    # 2. UI erstellen
    var bar = Kernel.ui_factory.create_progress_bar(250.0)
    bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    hud.add_child(bar)

    # 3. Tween ausführen
    var tween = bar.create_tween()
    tween.tween_property(bar, "value", 100.0, task.duration).from(0.0)

    await get_tree().create_timer(task.duration).timeout

    # 4. Aufräumen (Sicherheits-Check für Validität der Bar)
    Logger.log_debug("Starte Timer/Tween für " + str(task.duration) + "s", "Builder")

    await get_tree().create_timer(task.duration).timeout
    
    Logger.log_debug("Timer abgelaufen für " + task.label, "Builder")

    if task.on_done.is_valid():
        Logger.log_debug("Rufe Callback auf...", "Builder")
        task.on_done.call()
    
    Kernel.states.set_state(Kernel.states.PlayerState.FREE)
    Logger.log_debug("Interaktion beendet, Player wieder FREE", "Builder")

    # 5. Korrekt eingerücktes await
    await get_tree().process_frame
    
    # 6. Callback ausführen
    if task.on_done.is_valid():
        task.on_done.call()

    Kernel.states.set_state(Kernel.states.PlayerState.FREE)

func create(node: Node3D) -> Task:
	return Task.new(node)
	
func is_interactable(node: Node) -> bool:
    return node.is_in_group("interactable")

func trigger_interaction(target: Node3D) -> void:
    if is_interactable(target):
        var task = create(target).set_duration(0.1)
        Kernel.events.interaction_started.emit(task.label, task.duration)
        execute_interaction(task)