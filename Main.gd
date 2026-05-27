extends Node

# Welche Services müssen zwingend da sein, bevor das Spiel startet?
const REQUIRED_SERVICES = ["data", "events", "world_factory"]
var _services_to_wait_for = REQUIRED_SERVICES.duplicate()

func _ready() -> void:
    Logger.log_debug("Main: Initialisiere Start-Sequenz...", "Main")
    
    # Prüfen, was schon da ist
    for s_name in REQUIRED_SERVICES:
        if Kernel.has_service(s_name):
            _services_to_wait_for.erase(s_name)
    
    # Wenn noch was fehlt, warten wir auf das Signal
    if _services_to_wait_for.is_empty():
        _start_game()
    else:
        Kernel.service_registered.connect(_on_service_registered)

func _on_service_registered(s_name: String) -> void:
    if _services_to_wait_for.has(s_name):
        _services_to_wait_for.erase(s_name)
        Logger.log_debug("Main: Wartet noch auf: " + str(_services_to_wait_for), "Main")
        
        if _services_to_wait_for.is_empty():
            Kernel.service_registered.disconnect(_on_service_registered)
            _start_game()

func _start_game() -> void:
    Logger.log_debug("Main: Alle kritischen Services bereit. Starte Spiel.", "Main")
    var world = Kernel.world_factory.create_world()
    add_child(world)