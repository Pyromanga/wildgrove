func build(hud: HUD) -> InteractionUIController:
    var visuals = InteractionVisuals.new(hud)
    var ctrl = InteractionUIController.new()
    
    # Injection: Der Builder/Component bestimmt, welche Welt-Events genutzt werden
    ctrl.setup(visuals, Kernel.events.world)
    
    return ctrl