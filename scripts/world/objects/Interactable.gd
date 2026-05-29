extends Node3D
## Interactable.gd — Die Basis-Logik für alle 3D-Interaktionen

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
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 2.0
	area.add_child(col)
	add_child(area)

	# Lambda über mehrere Zeilen mit richtiger Einrückung
	area.body_entered.connect(
		func(b: Node3D):
			if b.is_in_group("player"):
				Logger.log_debug(">>> SPIELER IN INTERACTIONS-REICHWEITE: " + task.label + " bei " + str(global_position), "Interactable")
	)

# Schnittstelle für den Player
func start_interaction() -> void:
	if task:
		Kernel.builder.execute_interaction(task)