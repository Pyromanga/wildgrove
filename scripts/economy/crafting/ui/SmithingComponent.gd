class_name SmithingComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> SmithingUIController:
	var visuals := SmithingVisuals.new(hud)
	var ctrl := SmithingUIController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
