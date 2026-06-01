# scripts/ui/components/interaction_component.gd
class_name InteractionComponent extends BaseUIComponent

func build(hud: HUD) -> InteractionUIController:
    # 1. Visuals bauen
    var visuals = InteractionVisuals.new(hud)
    
    # 2. Controller bauen & koppeln
    var ctrl = InteractionUIController.new()
    ctrl.setup(visuals)
    
    return ctrl