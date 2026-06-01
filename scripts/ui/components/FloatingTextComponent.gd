# scripts/ui/components/floating_text_component.gd
class_name FloatingTextComponent extends BaseUIComponent

func build(hud: HUD, player_events: Object, skill_events: Object) -> FloatingTextController:
    var visuals = FloatingTextVisuals.new(hud)
    var ctrl = FloatingTextController.new()
    
    # Injection der Abhängigkeiten
    ctrl.setup(visuals, player_events, skill_events)
    
    return ctrl