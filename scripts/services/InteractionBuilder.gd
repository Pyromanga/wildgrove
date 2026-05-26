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

	func build() -> Node3D: # Rückgabetyp Node3D für mehr Flexibilität
		var interactable = Node3D.new()
		interactable.add_to_group("interactable")
		interactable.set_meta("task", self)
		interactable.set_script(load("res://scripts/Interactable.gd"))
		target.add_child(interactable)
		return interactable # Damit man das Objekt bei Bedarf weiter konfigurieren kann

func execute_interaction(task: Task) -> void:
	if not task.target or not is_instance_valid(task.target): return
	
	Kernel.states.set_state(Kernel.states.PlayerState.BUSY)
	
	# Hole HUD sicher ab
	var hud = get_tree().get_first_node_in_group("hud")
	if not hud: 
		push_warning("InteractionBuilder: Kein HUD gefunden!")
		return
	
	var bar = Kernel.ui_factory.create_progress_bar(250.0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hud.add_child(bar)
	
	var tween = bar.create_tween()
	tween.tween_property(bar, "value", 100.0, task.duration).from(0.0)
	
	await get_tree().create_timer(task.duration).timeout
	
	if is_instance_valid(bar):
		bar.queue_free()
		
	if task.on_done.is_valid():
		task.on_done.call()
		
	Kernel.states.set_state(Kernel.states.PlayerState.FREE)

func create(node: Node3D) -> Task:
	return Task.new(node)