extends Node

var _config: GameConfig
var _services_to_wait_for: Array[String]

func _ready() -> void:
    _config = GameConfig.new(["debug_service", "events"])
    _services_to_wait_for = _config.required_services.duplicate()
    
    ServiceLoader.new().setup_services(self)
    _check_services()

func _check_services() -> void:
    for s_name in _config.required_services:
        if Kernel.has_service(s_name):
            _services_to_wait_for.erase(s_name)
    
    if _services_to_wait_for.is_empty():
        _start_game()
    else:
        Kernel.service_registered.connect(_on_service_registered)

func _on_service_registered(service_name: String) -> void:
    _services_to_wait_for.erase(service_name)
    
    if _services_to_wait_for.is_empty():
        Kernel.service_registered.disconnect(_on_service_registered)
        _start_game()

func _start_game() -> void:
    Logger.log_debug("Alle Services bereit – Spiel startet.", "Main")
    # TODO: Nächste Scene laden, z.B.:
    # get_tree().change_scene_to_file("res://scenes/World.tscn")