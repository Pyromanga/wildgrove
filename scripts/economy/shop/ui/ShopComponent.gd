class_name ShopComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> ShopUIController:
	var visuals := ShopVisuals.new(hud)
	var ctrl := ShopUIController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
