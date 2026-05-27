extends Node

# Wir fügen den debug_service zur Pflicht-Liste hinzu
const REQUIRED_SERVICES = ["debug_service"] 
var _services_to_wait_for = REQUIRED_SERVICES.duplicate()

func _ready() -> void:
    Logger.log_debug("Main: Initialisiere Start-Sequenz...", "Main")
    
    # Check-Logik... (wie oben besprochen)
    for s_name in REQUIRED_SERVICES:
        if Kernel.has_service(s_name):
            _services_to_wait_for.erase(s_name)
    
    if _services_to_wait_for.is_empty():
        _start_game()
    else:
        Kernel.service_registered.connect(_on_service_registered)

func _on_service_registered(s_name: String) -> void:
    if _services_to_wait_for.has(s_name):
        _services_to_wait_for.erase(s_name)
        Logger.log_debug("Main: Erhalten! Wartet noch auf: " + str(_services_to_wait_for), "Main")
        
        if _services_to_wait_for.is_empty():
            Kernel.service_registered.disconnect(_on_service_registered)
            _start_game()

func _start_game() -> void:
    Logger.log_debug("Main: System-Test erfolgreich. Alle VIPs sind da!", "Main")