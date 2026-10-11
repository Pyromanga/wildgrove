class_name BankComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> BankUIController:
	var visuals := BankVisuals.new(hud)
	var ctrl := BankUIController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
