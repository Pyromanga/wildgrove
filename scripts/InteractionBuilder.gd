extends Node
## InteractionBuilder.gd — Erstellt Interaktionen per Script-Kette

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
		# Wir erstellen eine unsichtbare Hilfs-Node, die die Logik hält
		var interactable = Node3D.new()
		interactable.add_to_group("interactable")
		
		# Die eigentliche Logik-Funktion, die vom Player aufgerufen wird
		interactable.set_meta("interact", func():
			_execute_interaction())
		
		target.add_child(interactable)

	func _execute_interaction():
    States.set_state(States.PlayerState.BUSY)
    
    # 1. Balken über die Factory erstellen
    var hud = target.get_tree().get_nodes_in_group("hud")[0] # HUD finden
    var bar = Factory.create_progress_bar(250.0)
    
    # Balken mittig am Bildschirm positionieren
    bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    hud.add_child(bar)
    
    # 2. Timer & Update (Animation per Script)
    var tween = target.get_tree().create_tween()
    tween.tween_property(bar, "value", 100.0, duration).from(0.0)
    
    await target.get_tree().create_timer(duration).timeout
    
    # 3. Aufräumen
    bar.queue_free()
    if on_done.is_valid(): on_done.call()
    States.set_state(States.PlayerState.FREE)

func create(node: Node3D) -> Task:
	return Task.new(node)