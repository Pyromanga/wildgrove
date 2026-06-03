class_name HUDBuilder

static func build_all(hud: HUD) -> Dictionary:
    var registry: Dictionary = {}

    # 1. Interaktion (Balken) - braucht World-Events
    registry["interaction"] = InteractionComponent.new().build(hud, EventBus.world)

    # 2. Interaktion (Button)
    registry["interaction_button"] = InteractionButtonComponent.new().build(hud)

    # 3. Inventar - braucht den Service
    registry["inventory"] = InventoryComponent.new().build(hud, Services.inventory)

    # 4. Floating Text - braucht Player-Events
    registry["floating_text"] = FloatingTextComponent.new().build(hud, EventBus.player)

    # 5. Benachrichtigungen & Rest
    registry["notification"] = NotificationComponent.new().build(hud)
    registry["joystick"] = JoystickComponent.new().build(hud)
    
    # Kontext-Menü
    registry["context_button"] = ContextButtonComponent.new().build(hud, EventBus.ui)
    registry["context_menu"] = ContextMenuComponent.new().build(hud, EventBus.ui)

    return registry