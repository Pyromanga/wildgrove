class_name TradeComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> TradeUIController:
	var visuals := TradeVisuals.new(hud)
	var ctrl := TradeUIController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
