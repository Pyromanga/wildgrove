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
    ServiceLoader.new().setup_services(self)
    Logger.log_debug("Im Kernel: " + str(Kernel.services.keys()), "Main")
    Logger.log_debug("Noch offen: " + str(_services_to_wait_for), "Main")

func _on_service_registered(service_name: String) -> void:
    _services_to_wait_for.erase(service_name)
    Logger.log_debug("Registriert: " + service_name + " | Offen: " + str(_services_to_wait_for), "Main")
    if _services_to_wait_for.is_empty():
        Kernel.service_registered.disconnect(_on_service_registered)
        _start_game()

func _start_game() -> void:
    Logger.log_debug("=== _start_game() ===", "Main")

    Logger.log_debug("WorldFactory wird erstellt...", "Main")
    var factory := WorldFactory.new()
    if not factory:
        Logger.log_error("WorldFactory.new() ist null!", "Main")
        return
    Logger.log_debug("WorldFactory OK", "Main")

    Logger.log_debug("create_world()...", "Main")
    var world := factory.create_world()
    if not world:
        Logger.log_error("create_world() hat null zurückgegeben!", "Main")
        return
    Logger.log_debug("World OK: " + world.name, "Main")

    add_child(world)
    Logger.log_debug("World im Tree", "Main")

    Logger.log_debug("ui_factory Service vorhanden: " + str(Kernel.has_service("ui_factory")), "Main")
    if not Kernel.has_service("ui_factory"):
        Logger.log_error("ui_factory fehlt!", "Main")
        return

    Logger.log_debug("HUD wird erstellt...", "Main")
    var hud: HUD = Kernel.ui_factory.create_hud()
    if not hud:
        Logger.log_error("create_hud() hat null zurückgegeben!", "Main")
        return
    Logger.log_debug("HUD OK", "Main")

    add_child(hud)
    Logger.log_debug("HUD im Tree", "Main")

    Logger.log_debug("InventoryUIController wird erstellt...", "Main")
    var inv_ui := InventoryUIController.new()
    if not inv_ui:
        Logger.log_error("InventoryUIController.new() ist null!", "Main")
        return
    add_child(inv_ui)

    Logger.log_debug("inventory Service vorhanden: " + str(Kernel.has_service("inventory")), "Main")
    if not Kernel.has_service("inventory"):
        Logger.log_error("inventory Service fehlt!", "Main")
        return

    inv_ui.setup(hud, Kernel.inventory)
    Logger.log_debug("=== Spiel bereit ===", "Main")