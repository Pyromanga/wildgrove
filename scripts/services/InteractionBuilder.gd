extends Node
## InteractionBuilder.gd — Der Manager für Interaktions-Logik

class Task:
	var target: Node3D
	var label: String = "Interagieren"
	var duration: float = 2.0
	var on_done: Callable

	func _init(node: Node3D):
		target = node

	func set_label(l: String) -> Task:
		label = l; return self

	func set_duration(d: float) -> Task:
		duration = d; return self

	func on_complete(c: Callable) -> Task:
		on_done = c; return self

	func build() -> void:
		var interactable = Node3D.new()
		interactable.add_to_group("interactable")
		interactable.set_meta("task", self)
		interactable.set_script(load("res://scripts/Interactable.gd"))
		target.add_child(interactable)

# Wird vom Interactable-Script aufgerufen
func execute_interaction(task: Task) -> void:
    if not task.target or not is_instance_valid(task.target): return
    
    Kernel.states.set_state(Kernel.states.PlayerState.BUSY)
    
    # Sicherere HUD-Referenz
    var hud = Kernel.utils.get_hud() # Methode in Utils ergänzen: return get_tree().get_first_node_in_group("hud")
    if not hud: return
    
    var bar = Kernel.ui_factory.create_progress_bar(250.0)
    bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    hud.add_child(bar)
    
    var tween = task.target.get_tree().create_tween()
    tween.tween_property(bar, "value", 100.0, task.duration).from(0.0)
    
    # Wartet auf den Timer ODER ein Abbruch-Signal
    var timer = task.target.get_tree().create_timer(task.duration)
    # Optional: await Kernel.events.interact_canceled (falls du Abbruch willst)
    await timer.timeout
    
    if is_instance_valid(bar):
        bar.queue_free()
        
    if task.on_done.is_valid():
        task.on_done.call()
        
    Kernel.states.set_state(Kernel.states.PlayerState.FREE)

func create(node: Node3D) -> Task:
	return Task.new(node)