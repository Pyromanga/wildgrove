extends Node3D
## Main.gd — Der Orchestrator (nur noch Szenen-Verwaltung)

func _ready() -> void:
	# 1. Pipeline-Check: Ist der Kernel da? (Er ist ein Autoload, also muss er da sein)
	Kernel.events.log("Spiel-Bootstrap gestartet.")
	
	# 2. Welt laden
	var world = load("res://scenes/World.tscn").instantiate() # Oder per Script, wie du es hattest
	add_child(world)
	
	# 3. UI-Aufbau über die UI-Factory
	# Anstatt manuell zu bauen, nutzen wir den Service!
	var hud = Kernel.ui_factory.create_hud() # Methode in UIFactory ergänzen
	add_child(hud)
	
	# 4. Signale verbinden: Alle laufen über Kernel.events
	Kernel.events.xp_gained.connect(_on_xp_gained)

func _on_xp_gained(skill: String, amt: int) -> void:
	print("Main: XP erhalten für " + skill)