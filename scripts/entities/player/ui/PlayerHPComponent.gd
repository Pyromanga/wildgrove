class_name PlayerHPComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> PlayerHPController:
	var visuals := PlayerHPVisuals.new(hud)
	var ctrl := PlayerHPController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
