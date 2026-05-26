extends Node
## Kernel.gd — Der zentrale Service-Manager

# Instanzen der Services
var world_factory: Node
var ui_factory: Node
var data: Node
var states: Node
var events: Node
var utils: Node
var builder: Node
var skill_system: Node

func _ready() -> void:
	# Initialisiere alle Services als Kinder des Kernels
	events = _add_service("res://scripts/services/GameEvents.gd", "Events")
	data = _add_service("res://scripts/services/DataService.gd", "Data")
	states = _add_service("res://scripts/services/StateService.gd", "States")
	utils = _add_service("res://scripts/services/Utils.gd", "Utils")
	
	world_factory = _add_service("res://scripts/factories/WorldFactory.gd", "WorldFactory")
	ui_factory = _add_service("res://scripts/factories/UIFactory.gd", "UIFactory")
	
	# Jetzt sind sie innerhalb der Funktion korrekt zugewiesen
	builder = _add_service("res://scripts/services/InteractionBuilder.gd", "Builder")
	skill_system = _add_service("res://scripts/services/SkillSystem.gd", "SkillSystem")

func _add_service(path: String, node_name: String) -> Node:
	var s = load(path).new()
	s.name = node_name
	add_child(s)
	return s