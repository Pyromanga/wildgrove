class_name InteractionUIController

## InteractionUIController — treibt den HUD-Fortschrittsbalken für Interaktionen.
##
## Empfängt EventBus.world-Signale (werden via world_events-Parameter übergeben).
## Früher verband sich InteractableComponent direkt mit Services.builder-Signalen.
## Jetzt ist EventBus.world die einzige Signal-Quelle — InteractionExecutor emittiert
## dort hin, dieser Controller lauscht dort. Kein doppelter Signalkanal mehr.

var _visuals: InteractionVisuals


func setup(visuals: InteractionVisuals, world_events: Object) -> void:
	_visuals = visuals
	world_events.interaction_started.connect(_on_started)
	world_events.interaction_finished.connect(_on_finished)
	world_events.interaction_cancelled.connect(_on_cancelled)


func _on_started(_action_id: String, _label: String, duration: float) -> void:
	_visuals.set_value(0)
	_visuals.set_visible(true)

	var tween = _visuals.create_tween()
	tween.tween_property(_visuals.bar, "value", 100.0, duration)


func _on_finished(_action_id: String, _label: String) -> void:
	_visuals.set_visible(false)


func _on_cancelled(_action_id: String, _label: String) -> void:
	_visuals.set_visible(false)
