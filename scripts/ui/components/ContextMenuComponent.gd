class_name ContextMenuComponent extends BaseUIComponent

# FIX: Kein Override-Konflikt mehr, da BaseUIComponent kein build() hat.
func build(hud: HUD, ctx: IUIContext) -> ContextMenuController:
	var ctrl := ContextMenuController.new()
	ctrl.setup(hud, ctx)
	return ctrl
