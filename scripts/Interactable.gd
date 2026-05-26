extends Node3D
## Interactable.gd — Die Basis-Logik für alle 3D-Interaktionen

var task = null

func _ready() -> void:
	# Task-Daten sicher abrufen
	if has_meta("task"):
		task = get_meta("task")
		_setup_detection_area()
	else:
		push_error("Interactable: Kein 'task' Meta gefunden!")

func _setup_detection_area() -> void:
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 2.0
	
	area.add_child(col)
	add_child(area)
	
	# Event-Feedback über den Kernel
	area.body_entered.connect(func(b): 
		if b.is_in_group("player"): 
			Kernel.events.log("Interaktion möglich: " + task.label)
	)

# Schnittstelle für den Player
func start_interaction() -> void:
	if task:
		Kernel.builder.execute_interaction(task)