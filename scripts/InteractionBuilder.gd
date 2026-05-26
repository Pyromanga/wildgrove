extends Node

class Task:
	var target: Node3D
	var label: String = "Interagieren"
	var duration: float = 2.0
	var callback: Callable
	
	func _init(node: Node3D):
		target = node

	func set_label(l: String) -> Task:
		label = l
		return self

	func set_duration(d: float) -> Task:
		duration = d
		return self

	func on_complete(c: Callable) -> Task:
		callback = c
		return self

	func build() -> void:
		# Hier wird die schwere Logik 'eingespritzt'
		var script = load("res://scripts/Interactable.gd")
		var interactable = Node3D.new()
		interactable.set_script(script)
		
		# Werte übertragen
		interactable.label = label
		interactable.duration = duration
		if callback.is_valid():
			interactable.completed.connect(callback)
		
		target.add_child(interactable)
		GameEvents.log("Builder: %s konfiguriert" % label)

func create(node: Node3D) -> Task:
	return Task.new(node)