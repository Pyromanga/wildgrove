class_name HUDBuilder

static func build_all(hud: HUD) -> Dictionary:
    var registry = {}
    
    # Zentrale Event-Buss-Referenz für die Entkopplung (z.B. Context-Signale)
    var ui_events = Kernel.events.ui 

    # 1. Interaktion & Fortschritt
    registry["interaction"] = InteractionComponent.new().build(hud, Kernel.events.world)
    registry["interaction_button"] = InteractionButtonComponent.new().build(hud)
    
    # 2. Kontext-System (Entkoppelt in Button und Menü)
    # Der Button braucht nur den Bus, das Menü braucht HUD + Bus
    registry["context_button"] = ContextButtonComponent.new().build(hud, ui_events)
    registry["context_menu"]   = ContextMenuComponent.new().build(hud, ui_events)
    
    # 3. Joystick
    registry["joystick"] = JoystickComponent.new().build(hud, ui_events)
    
    # 4. Inventar
    registry["inventory"] = InventoryComponent.new().build(hud, Kernel.inventory)
    
    # 5. Feedback
    registry["notification"] = NotificationComponent.new().build(hud)
    registry["floating_text"] = FloatingTextComponent.new().build(hud, Kernel.events.player, Kernel.events.skill_system)

    return registry