extends Node3D
## Main.gd — Der Orchestrator (nur noch Szenen-Verwaltung)

func _ready() -> void:
	# 1. Pipeline-Check
	Kernel.events.log("Spiel-Bootstrap gestartet.")
	
	# 2. Welt laden
	var world = load("res://scenes/World.tscn").instantiate()
	add_child(world)
	
	# 3. UI-Aufbau über die UI-Factory
	var hud = Kernel.ui_factory.create_hud()
	add_child(hud)
	
	# 4. Signale verbinden
	Kernel.events.xp_gained.connect(_on_xp_gained)

func _on_xp_gained(skill: String, amt: int) -> void:
	print("Main: XP erhalten für " + skill)