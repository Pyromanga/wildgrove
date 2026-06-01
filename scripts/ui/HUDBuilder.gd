class_name HUDBuilder

## Baut das gesamte HUD auf.
## Gibt ein Dictionary mit allen Controllern zurück.
static func build_all(hud: HUD) -> Dictionary:
    var registry = {}

    # 1. Interaktion-System (Buttons & Balken)
    # Wir bündeln diese hier, da sie zusammengehören
    registry["interaction"] = InteractionComponent.new().build(hud)
    registry["interaction_button"] = InteractionButtonComponent.new().build(hud)
    
    # 2. Kontext-System
    registry["context"] = ContextComponent.new().build(hud)
    
    # 3. Eingabe & Navigation
    registry["joystick"] = JoystickComponent.new().build(hud)
    
    # 4. Daten-Module
    registry["inventory"] = InventoryComponent.new().build(hud)
    
    # 5. Feedback-Systeme
    registry["notification"] = NotificationComponent.new().build(hud)
    registry["floating_text"] = FloatingTextComponent.new().build(hud)

    return registry