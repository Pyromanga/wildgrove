extends Node

var _config: GameConfig
var _services_to_wait_for: Array[String]

func _ready() -> void:
    _config = GameConfig.new([
        "debug_console", "debug_service", "events", "data", "states",
        "utils", "builder", "ui_factory", "factory3d",
        "inventory", "skill_system"
    ])
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

    # Welt bauen
    var world := WorldFactory.new().create_world()
    add_child(world)

    # TouchInput als Child vom Player holen (wird von Player._build_player_nodes gesetzt)
    # Kernel.touch wird direkt im Player via Kernel.get_service("touch") geholt

    # HUD aufbauen
    var hud: HUD = Kernel.ui_factory.create_hud()
    add_child(hud)

    # Inventory-UI verbinden
    var inv_ui := InventoryUIController.new()
    add_child(inv_ui)
    inv_ui.setup(hud, Kernel.inventory)