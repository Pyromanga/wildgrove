class_name ContextButtonController

var _visuals: ContextButtonVisuals
var _event_bus: Object


func setup(visuals: ContextButtonVisuals, event_bus: Object) -> void:
	_visuals = visuals
	_event_bus = event_bus
	_visuals.button.pressed.connect(_on_pressed)


func _on_pressed() -> void:
	# Nutzt die typisierte emit-Methode statt rohem Signal-Aufruf
	_event_bus.emit_request_context_menu()
