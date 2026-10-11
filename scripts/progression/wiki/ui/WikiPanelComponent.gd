class_name WikiPanelComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> WikiPanelController:
	var visuals := WikiPanelVisuals.new(hud)
	var ctrl := WikiPanelController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
