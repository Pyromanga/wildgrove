# scripts/ui/components/interaction_button_component.gd
class_name InteractionButtonComponent extends BaseUIComponent

func build(hud: HUD) -> InteractionButtonController:
    # 1. Position vom Service (LayoutManager) holen
    var pos = LayoutManager.get_action_button_position(0)
    
    # 2. Visuals bauen
    var visuals = InteractionButtonVisuals.new(hud, pos)
    
    # 3. Controller bauen & koppeln
    var ctrl = InteractionButtonController.new()
    ctrl.setup(visuals)
    
    return ctrl