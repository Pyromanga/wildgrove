class_name AppearancePanelComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> AppearancePanelController:
	var visuals := AppearancePanelVisuals.new(hud)
	var ctrl := AppearancePanelController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
