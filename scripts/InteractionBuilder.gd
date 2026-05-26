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
		# 1. Player einfrieren
		States.set_state(States.PlayerState.BUSY)
		GameEvents.log("Starte: " + label)
		
		# 2. Timer für die Dauer (Script-Only Lösung)
		await target.get_tree().create_timer(duration).timeout
		
		# 3. Fertig: Callback ausführen & Player befreien
		if on_done.is_valid():
			on_done.call()
		
		States.set_state(States.PlayerState.FREE)
		GameEvents.log(label + " beendet.")

func create(node: Node3D) -> Task:
	return Task.new(node)