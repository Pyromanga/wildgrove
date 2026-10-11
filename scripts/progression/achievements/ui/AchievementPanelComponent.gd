class_name AchievementPanelComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> AchievementPanelController:
	var visuals := AchievementPanelVisuals.new(hud)
	var ctrl := AchievementPanelController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
