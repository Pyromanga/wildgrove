class_name BuildModeComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> BuildModeController:
	var visuals := BuildModeVisuals.new(hud)
	var ctrl := BuildModeController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
