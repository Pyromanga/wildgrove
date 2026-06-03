class_name JoystickComponent extends BaseUIComponent

func build(hud: HUD) -> JoystickController:
	var visuals := JoystickVisuals.new(hud)
	var ctrl    := JoystickController.new()
	ctrl.setup(visuals, EventBus.ui)
	return ctrl