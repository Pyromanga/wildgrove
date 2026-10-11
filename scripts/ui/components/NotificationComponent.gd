class_name NotificationComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> NotificationController:
	var visuals := NotificationVisuals.new(hud)
	var ctrl := NotificationController.new()
	ctrl.setup(visuals, ctx)
	return ctrl
