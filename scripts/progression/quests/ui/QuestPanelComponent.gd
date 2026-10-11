class_name QuestPanelComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> QuestPanelController:
	var visuals := QuestPanelVisuals.new(hud)
	var ctrl := QuestPanelController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
