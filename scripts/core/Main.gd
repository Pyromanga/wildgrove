extends Node

var _services_to_wait_for: Array[String]

func _ready() -> void:
    Logger.log_debug("Bootstrapping...", "Main")
    var loader := ServiceLoader.new()
    _services_to_wait_for = loader.get_required_names()
    Kernel.service_registered.connect(_on_service_registered)
    loader.setup_services(self)

func _on_service_registered(service_name: String) -> void:
    _services_to_wait_for.erase(service_name)
    if _services_to_wait_for.is_empty():
        Kernel.service_registered.disconnect(_on_service_registered)
        Logger.log_debug("Alle Services bereit, starte Spiel", "Main")
        _start_game()

func _start_game() -> void:
    var world := WorldFactory.new().create_world()
    if not world:
        Logger.log_error("create_world() hat null zurückgegeben", "Main")
        return
    add_child(world)

    if not Kernel.has_service("ui_factory"):
        Logger.log_error("ui_factory fehlt", "Main")
        return

    var hud: HUD = Kernel.ui_factory.create_hud()
    if not hud:
        Logger.log_error("create_hud() hat null zurückgegeben", "Main")
        return
    add_child(hud)

    # InventoryUIController gehört zur UI-Schicht → UIFactory erstellt ihn
    Kernel.ui_factory.setup_inventory_controller(hud)

    Logger.log_debug("=== Spiel bereit ===", "Main")