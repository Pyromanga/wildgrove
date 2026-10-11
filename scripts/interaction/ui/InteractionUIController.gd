class_name InteractionUIController

## InteractionUIController — treibt den HUD-Fortschrittsbalken für Interaktionen.
##
## Empfängt EventBus.world-Signale (werden via world_events-Parameter übergeben).
## Jetzt ist EventBus.world die einzige Signal-Quelle — InteractionExecutor emittiert
## dort hin, dieser Controller lauscht dort. Kein doppelter Signalkanal mehr.

var _visuals: InteractionVisuals
var _world_events: Object

## BUGFIX (entdeckt im Zuge von Bug #2, gleiche Root Cause): kein `extends Node`
## (RefCounted) und verbindet sich mit dem langlebigen world_events-Objekt —
## ohne teardown() bleibt dieser Controller nach jedem HUD-Rebuild
## (world_scene_ready) als Zombie-Listener am Leben, siehe FloatingTextController
## für die ausführliche Erklärung desselben Musters. Konkrete Folge hier: nach
## einem Rebuild zeigt der neue Controller den Fortschrittsbalken korrekt an,
## während der alte Zombie parallel auf einer bereits aus dem Baum entfernten
## `_visuals` operiert (Fehler/leere Updates) statt sauber freigegeben zu werden.
var _is_setup: bool = false

func setup(visuals: InteractionVisuals, world_events: Object) -> void:
	if _is_setup:
		teardown()
	_visuals = visuals
	_world_events = world_events
	world_events.interaction_started.connect(_on_started)
	world_events.interaction_finished.connect(_on_finished)
	world_events.interaction_cancelled.connect(_on_cancelled)
	_is_setup = true

## MUSS von HUDManager vor dem Verwerfen dieses Controllers aufgerufen werden
## (siehe HUDManager._on_world_scene_ready()) — sonst bleibt dieser Controller
## als Zombie-Listener am Leben.
func teardown() -> void:
	if is_instance_valid(_world_events):
		if _world_events.interaction_started.is_connected(_on_started):
			_world_events.interaction_started.disconnect(_on_started)
		if _world_events.interaction_finished.is_connected(_on_finished):
			_world_events.interaction_finished.disconnect(_on_finished)
		if _world_events.interaction_cancelled.is_connected(_on_cancelled):
			_world_events.interaction_cancelled.disconnect(_on_cancelled)
	_is_setup = false

func _on_started(_action_id: String, _label: String, duration: float) -> void:
	_visuals.set_value(0)
	_visuals.set_visible(true)

	var tween = _visuals.create_tween()
	tween.tween_property(_visuals.bar, "value", 100.0, duration)

func _on_finished(_action_id: String, _label: String) -> void:
	_visuals.set_visible(false)

func _on_cancelled(_action_id: String, _label: String) -> void:
	_visuals.set_visible(false)
