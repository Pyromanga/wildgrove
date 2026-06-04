class_name NotificationComponent extends BaseUIComponent


func build(hud: HUD) -> NotificationController:
	var visuals := NotificationVisuals.new(hud)
	var ctrl := NotificationController.new()
	ctrl.setup(visuals)
	return ctrl
