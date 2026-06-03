class_name ContextMenuComponent extends BaseUIComponent

# FIX: Kein Override-Konflikt mehr, da BaseUIComponent kein build() hat.
func build(hud: HUD, event_bus: Object) -> ContextMenuController:
	var ctrl := ContextMenuController.new()
	ctrl.setup(hud, event_bus)
	return ctrl