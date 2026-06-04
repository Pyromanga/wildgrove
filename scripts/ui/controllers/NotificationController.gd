# scripts/ui/controllers/notification_controller.gd
class_name NotificationController

var _visuals: NotificationVisuals


func setup(visuals: NotificationVisuals) -> void:
	_visuals = visuals


func show(text: String) -> void:
	_visuals.show_popup(text)
	Logger.log_debug("Popup angezeigt: " + text, "UI/Notification")
