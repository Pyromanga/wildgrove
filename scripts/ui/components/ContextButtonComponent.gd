class_name ContextButtonComponent extends BaseUIComponent

func build(hud: HUD, event_bus: Object) -> ContextButtonController:
    var visuals = ContextButtonVisuals.new(hud)
    var ctrl = ContextButtonController.new()
    ctrl.setup(visuals, event_bus)
    return ctrl