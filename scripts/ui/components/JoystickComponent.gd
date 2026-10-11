class_name JoystickComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> JoystickController:
	var visuals := JoystickVisuals.new(hud)
	var ctrl := JoystickController.new()
	ctrl.setup(visuals, ctx.bus().ui(), ctx.get_settings())
	return ctrl
