extends Node

var _config: GameConfig
var _services_to_wait_for: Array[String]

func _ready() -> void:
    _config = GameConfig.new([
        "debug_service", "debug_console", "events", "data", "states",
        "utils", "builder", "ui_factory", "factory3d",
        "inventory", "skill_system"
    ])
    _services_to_wait_for = _config.required_services.duplicate()

    # Signal VOR setup_services connecten damit kein emit verloren geht
    Kernel.service_registered.connect(_on_service_registered)

    ServiceLoader.new().setup_services(self)
    # Kein _check_services() hier – _on_service_registered übernimmt alles

func _on_service_registered(service_name: String) -> void:
    _services_to_wait_for.erase(service_name)
    Logger.log_debug("Warte noch auf: " + str(_services_to_wait_for), "Main")
    if _services_to_wait_for.is_empty():
        Kernel.service_registered.disconnect(_on_service_registered)
        _start_game()

func _start_game() -> void:
    Logger.log_debug("Alle Services bereit – Spiel startet.", "Main")

    var world := WorldFactory.new().create_world()
    add_child(world)

    var hud: HUD = Kernel.ui_factory.create_hud()
    add_child(hud)

    var inv_ui := InventoryUIController.new()
    add_child(inv_ui)
    inv_ui.setup(hud, Kernel.inventory)