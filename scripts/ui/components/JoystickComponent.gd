# scripts/ui/components/joystick_component.gd
class_name JoystickComponent extends BaseUIComponent

func build(hud: HUD) -> JoystickController:
    var visuals = JoystickVisuals.new(hud)
    var ctrl = JoystickController.new()
    
    # Injection passiert hier:
    ctrl.setup(visuals, Kernel.events.ui)
    
    return ctrl