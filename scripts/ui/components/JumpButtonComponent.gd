class_name JumpButtonComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext = null) -> JumpButtonController:
	var visuals := JumpButtonVisuals.new(hud)
	var ctrl := JumpButtonController.new()
	hud.add_child(ctrl)
	ctrl.setup(visuals, ctx)
	return ctrl
