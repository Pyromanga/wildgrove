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

    return registry