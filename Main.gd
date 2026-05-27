extends Node
## Main.gd — Der Orchestrator

func _ready() -> void:
	Kernel.events.log("Spiel-Bootstrap gestartet.")
	
	# Welt über die Factory erstellen, nicht direkt laden!
	var world = Kernel.world_factory.create_world()
	add_child(world)
	
	var hud = Kernel.ui_factory.create_hud()
	add_child(hud)
	
	Kernel.events.xp_gained.connect(_on_xp_gained)

func _on_xp_gained(skill: String, amt: int) -> void:
	print("Main: XP erhalten für " + skill)