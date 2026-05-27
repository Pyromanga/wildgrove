# HUD.gd
func _ready() -> void:
    # Nur für das Spiel, nicht für Tests (oder als Default)
    initialize()

func initialize() -> void:
    add_to_group("hud")
    _build_ui()
    _connect_bus()
    # Sicherstellen, dass wir nicht doppelt verbinden
    if not Kernel.inventory.inventory_changed.is_connected(_refresh_inventory_ui):
        Kernel.inventory.inventory_changed.connect(_refresh_inventory_ui)
    _refresh_inventory_ui()