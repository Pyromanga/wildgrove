extends Node
## Kernel.gd — Der zentrale Service-Manager

# --- Service-Referenzen ---
var world_factory: Node
var ui_factory: Node
var data: Node
var states: Node
var events: Node
var utils: Node
var builder: Node
var skill_system: Node
var touch: Node
var inventory: Node

func _ready() -> void:
	# Initialisierung der Services in logischer Abhängigkeits-Reihenfolge
	# 1. Basis-Services (werden von anderen Diensten benötigt)
	events = _add_service("res://scripts/services/GameEvents.gd", "Events")
	data = _add_service("res://scripts/services/DataService.gd", "Data")
	utils = _add_service("res://scripts/services/Utils.gd", "Utils")
	states = _add_service("res://scripts/services/StateService.gd", "States")
	inventory = _add_service("res://scripts/InventorySystem.gd", "Inventory")
	# 2. Fabriken (erzeugen Spiel-Elemente)
	world_factory = _add_service("res://scripts/factories/WorldFactory.gd", "WorldFactory")
	ui_factory = _add_service("res://scripts/factories/UIFactory.gd", "UIFactory")
	
	# 3. Logik-Module (nutzen Basis-Services und Fabriken)
	touch = _add_service("res://scripts/services/TouchInput.gd", "TouchInput")
	builder = _add_service("res://scripts/services/InteractionBuilder.gd", "Builder")
	skill_system = _add_service("res://scripts/services/SkillSystem.gd", "SkillSystem")
	
	print_rich("[color=green]Kernel:[/color] Alle Services erfolgreich initialisiert.")

## Hilfsfunktion zum Laden und Einbinden von Services
func _add_service(path: String, node_name: String) -> Node:
	var res = load(path)
	if not res:
		push_error("Kernel: Konnte Service nicht laden: " + path)
		return null
		
	var s = res.new()
	s.name = node_name
	add_child(s)
	return s