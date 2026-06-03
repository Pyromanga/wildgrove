class_name HUDBuilder

static func build_all(hud: HUD) -> Dictionary:
    var registry: Dictionary = {}

    # Interaktion & Fortschritt (Nutzen jetzt den EventBus oder Services)
    registry["interaction"] = InteractionComponent.new().build(hud)
    registry["interaction_button"] = InteractionButtonComponent.new().build(hud)

    # Inventar (Direkter Zugriff auf den Service)
    registry["inventory"] = InventoryComponent.new().build(hud, Services.inventory)

    # Feedback (Floating Text hört auf den EventBus)
    registry["floating_text"] = FloatingTextComponent.new().build(hud)
# Innerhalb von HUDBuilder.build_all(hud):

# 1. Floating Text (XP & Level-Ups)
    var float_ctrl = FloatingTextController.new()
# Nutzt direkt den globalen EventBus
    float_ctrl.setup(visuals_ft, EventBus.player) 
    registry["floating_text"] = float_ctrl

# 2. Inventory (Service-Anbindung)
    var inv_ctrl = InventoryUIController.new()
# Nutzt den echten Service
    inv_ctrl.setup(visuals_inv, Services.inventory) 
    registry["inventory"] = inv_ctrl

# 3. Context & Joystick
    var joy_ctrl = JoystickController.new()
# Nutzt den UI-Zweig des EventBus
    joy_ctrl.setup(visuals_joy, EventBus.ui) 
     registry["joystick"] = joy_ctrl
    return registry