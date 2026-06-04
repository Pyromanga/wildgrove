class_name InteractionUIController

var _visuals: InteractionVisuals


func setup(visuals: InteractionVisuals, world_events: Object) -> void:
	_visuals = visuals
	world_events.interaction_started.connect(_on_started)
	world_events.interaction_finished.connect(_on_finished)
	world_events.interaction_cancelled.connect(_on_cancelled)


func _on_started(_label: String, duration: float) -> void:
	_visuals.set_value(0)
	_visuals.set_visible(true)

	var tween = _visuals.create_tween()
	tween.tween_property(_visuals.bar, "value", 100.0, duration)


func _on_finished(_label: String) -> void:
	_visuals.set_visible(false)


func _on_cancelled(_label: String) -> void:
	_visuals.set_visible(false)
