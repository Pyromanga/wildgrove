class_name HUDBuilder

static func build_all(hud: HUD) -> Dictionary:
    var registry = {}

    # Initialisierung der UI-Module über ihre jeweiligen Component-Klassen
    registry["interaction"]        = InteractionComponent.new().build(hud)
    registry["interaction_button"] = InteractionButtonComponent.new().build(hud)
    registry["context"]            = ContextComponent.new().build(hud)
    registry["joystick"]           = JoystickComponent.new().build(hud)
    registry["inventory"]          = InventoryComponent.new().build(hud)
    registry["notification"]       = NotificationComponent.new().build(hud)
    registry["floating_text"]      = FloatingTextComponent.new().build(hud)

    return registry