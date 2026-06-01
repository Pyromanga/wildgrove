class_name ContextMenuComponent extends BaseUIComponent

func build(hud: HUD, event_bus: Object) -> ContextMenuController:
    var ctrl = ContextMenuController.new()
    ctrl.setup(hud, event_bus)
    return ctrl