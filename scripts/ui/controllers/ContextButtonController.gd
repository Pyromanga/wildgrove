class_name ContextButtonController

var _visuals: ContextButtonVisuals
var _event_bus: Object


func setup(visuals: ContextButtonVisuals, event_bus: Object) -> void:
	_visuals = visuals
	_event_bus = event_bus
	_visuals.button.pressed.connect(_on_pressed)


func _on_pressed() -> void:
	# Nur noch ein Event feuern!
	_event_bus.request_context_menu.emit()
