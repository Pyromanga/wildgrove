class_name BuildPanelComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> BuildPanelController:
	var visuals := BuildPanelVisuals.new(hud)
	var ctrl := BuildPanelController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
