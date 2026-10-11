class_name PetPanelComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> PetPanelController:
	var visuals := PetPanelVisuals.new(hud)
	var ctrl := PetPanelController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
