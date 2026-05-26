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
		# Wir binden den Builder-Task an das Objekt
		interactable.set_meta("task", self)
		
		# Wichtig: Der Player ruft diese Funktion auf
		interactable.set_script(load("res://scripts/Interactable.gd"))
		
		target.add_child(interactable)

# Wird vom Interactable-Script aufgerufen
func execute_interaction(task: Task) -> void:
	if not task.target or not is_instance_valid(task.target): return
	
	States.set_state(States.PlayerState.BUSY)
	
	# UI-Factory Integration
	var hud = task.target.get_tree().get_nodes_in_group("hud")[0]
	var bar = Factory.create_progress_bar(250.0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hud.add_child(bar)
	
	# Tween für flüssige Animation
	var tween = task.target.get_tree().create_tween()
	tween.tween_property(bar, "value", 100.0, task.duration).from(0.0)
	
	# Timer
	await task.target.get_tree().create_timer(task.duration).timeout
	
	# Aufräumen (Safety-Check: Ist das Target noch da?)
	if is_instance_valid(bar):
		bar.queue_free()
		
	if task.on_done.is_valid():
		task.on_done.call()
		
	States.set_state(States.PlayerState.FREE)

func create(node: Node3D) -> Task:
	return Task.new(node)