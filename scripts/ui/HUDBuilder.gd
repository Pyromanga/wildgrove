class_name HUDBuilder

static func build_all(hud: HUD) -> Dictionary:
    var registry = {}
    
    # Zentrale Event-Bus-Referenzen
    var world_events = Kernel.events.world
    var player_events = Kernel.events.player
    var skill_events = Kernel.events.skill_system
    var ui_events = Kernel.events.ui

    # 1. Interaktion & Fortschritt
    registry["interaction"] = InteractionComponent.new().build(hud, world_events)
    registry["interaction_button"] = InteractionButtonComponent.new().build(hud)
    
    # 2. Kontext-System (Entkoppelt)
    registry["context_button"] = ContextButtonComponent.new().build(hud, ui_events)
    registry["context_menu"]   = ContextMenuComponent.new().build(hud, ui_events)
    
    # 3. Joystick
    registry["joystick"] = JoystickComponent.new().build(hud, ui_events)
    
    # 4. Inventar
    registry["inventory"] = InventoryComponent.new().build(hud, Kernel.inventory)
    
    # 5. Feedback
    registry["notification"] = NotificationComponent.new().build(hud)
    
    # Hier ist die wichtige Anpassung für FloatingText:
    # Wir übergeben jetzt die beiden benötigten Event-Objekte aus dem Kernel
    registry["floating_text"] = FloatingTextComponent.new().build(hud, player_events, skill_events)

    return registry