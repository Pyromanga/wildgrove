class_name SkillPanelComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> SkillPanelController:
	var visuals := SkillPanelVisuals.new(hud)
	var ctrl := SkillPanelController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
