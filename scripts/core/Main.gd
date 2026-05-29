extends Node

var _config: GameConfig
var _services_to_wait_for: Array[String]

func _ready() -> void:
    Logger.log_debug("Main._ready() gestartet", "Main")
    _config = GameConfig.new([
        "debug_service", "debug_console", "events", "data", "states",
        "utils", "builder", "ui_factory", "factory3d",
        "inventory", "skill_system"
    ])
    _services_to_wait_for = _config.required_services.duplicate()
    Kernel.service_registered.connect(_on_service_registered)
    Logger.log_debug("ServiceLoader wird gestartet...", "Main")
    ServiceLoader.new().setup_services(self)
    Logger.log_debug("ServiceLoader fertig", "Main")

func _on_service_registered(service_name: String) -> void:
    _services_to_wait_for.erase(service_name)
    Logger.log_debug("Registriert: " + service_name + " | Offen: " + str(_services_to_wait_for), "Main")
    if _services_to_wait_for.is_empty():
        Kernel.service_registered.disconnect(_on_service_registered)
        _start_game()

func _start_game() -> void:
    Logger.log_debug("=== _start_game() ===", "Main")

    Logger.log_debug("WorldFactory.create_world()...", "Main")
    var world := WorldFactory.new().create_world()
    Logger.log_debug("World gebaut, add_child...", "Main")
    add_child(world)
    Logger.log_debug("World im Tree", "Main")

    Logger.log_debug("HUD wird erstellt...", "Main")
    var hud: HUD = Kernel.ui_factory.create_hud()
    Logger.log_debug("HUD gebaut, add_child...", "Main")
    add_child(hud)
    Logger.log_debug("HUD im Tree", "Main")

    Logger.log_debug("InventoryUIController wird erstellt...", "Main")
    var inv_ui := InventoryUIController.new()
    add_child(inv_ui)
    inv_ui.setup(hud, Kernel.inventory)
    Logger.log_debug("=== Spiel bereit ===", "Main")