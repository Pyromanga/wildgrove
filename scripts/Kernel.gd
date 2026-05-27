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
var hud: Node

func _ready() -> void:
    # 1. Logging starten
    log_init("Kernel-Bootstrap gestartet.")
    
    # 2. Services nacheinander laden
    # Hinweis: Wenn ein Service einen anderen braucht, muss er hier unten drunter stehen
    events       = _add_service("res://scripts/services/GameEvents.gd", "Events")
    data         = _add_service("res://scripts/services/DataService.gd", "Data")
    states       = _add_service("res://scripts/services/StateService.gd", "States")
    utils        = _add_service("res://scripts/services/Utils.gd", "Utils")
    inventory    = _add_service("res://scripts/InventorySystem.gd", "Inventory")
    
    world_factory = _add_service("res://scripts/factories/WorldFactory.gd", "WorldFactory")
    ui_factory    = _add_service("res://scripts/factories/UIFactory.gd", "UIFactory")
    
    touch        = _add_service("res://scripts/services/TouchInput.gd", "TouchInput")
    builder      = _add_service("res://scripts/services/InteractionBuilder.gd", "Builder")
    skill_system = _add_service("res://scripts/services/SkillSystem.gd", "SkillSystem")
    hud          = _add_service("res://scripts/HUD.gd", "HUD")
    
    log_init("Alle Services erfolgreich initialisiert.")

## Sauberes Logging mit Zeitstempel und Pfad
func log_init(msg: String) -> void:
    print_rich("[color=cyan][Kernel][/color] ", msg)

## Hilfsfunktion zum Laden und Einbinden von Services
func _add_service(path: String, node_name: String) -> Node:
    var script_res = load(path)
    if not script_res:
        push_error("Kernel: Konnte Skript nicht finden: " + path)
        return null
        
    var service_instance = script_res.new()
    
    if service_instance is Node:
        service_instance.name = node_name
        add_child(service_instance)
        print_rich("  -> Service [color=yellow]", node_name, "[/color] geladen.")
        return service_instance
    else:
        push_error("Kernel: " + node_name + " erbt nicht von Node!")
        service_instance.free()
        return null