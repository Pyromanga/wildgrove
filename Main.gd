extends Node

var _config: GameConfig
var _services_to_wait_for: Array

func _ready() -> void:
    _config = GameConfig.new(["debug_service", "events"])
    _services_to_wait_for = _config.required_services.duplicate()
    
    # Ausgelagert: Die Erstellung passiert hier
    ServiceLoader.new().setup_services(self)
    
    # ... ab hier geht deine gewohnte Check-Logik weiter ...
    _check_services()

func _check_services() -> void:
    for s_name in _config.required_services:
        if Kernel.has_service(s_name):
            _services_to_wait_for.erase(s_name)
    
    if _services_to_wait_for.is_empty():
        _start_game()
    else:
        Kernel.service_registered.connect(_on_service_registered)