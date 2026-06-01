class_name HUDBuilder

static func build_all(hud: HUD) -> Dictionary:
    var registry = {}

    # 1. Interaktion & Fortschritt
    # Wir injizieren hier die spezifischen Kernel-Events
    var interaction_comp = InteractionComponent.new()
    registry["interaction"] = interaction_comp.build(hud, Kernel.events.world)
    
    # 2. Buttons
    var btn_comp = InteractionButtonComponent.new()
    registry["interaction_button"] = btn_comp.build(hud)

    # 3. Kontext (Hier injizieren wir den Kontext-Manager)
    var context_comp = ContextComponent.new()
    registry["context"] = context_comp.build(hud, Kernel.ui_factory)

    # 4. Joystick
    var joy_comp = JoystickComponent.new()
    registry["joystick"] = joy_comp.build(hud, Kernel.events.ui)

    # 5. Inventar (Hier injizieren wir das Service-Objekt)
    var inv_comp = InventoryComponent.new()
    registry["inventory"] = inv_comp.build(hud, Kernel.inventory)

    # 6. Feedback
    registry["notification"] = NotificationComponent.new().build(hud)
    registry["floating_text"] = FloatingTextComponent.new().build(hud, Kernel.events.player, Kernel.events.skill_system)

    return registry