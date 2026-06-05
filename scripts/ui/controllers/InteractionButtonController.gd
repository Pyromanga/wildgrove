class_name InteractionButtonController
extends Node

## InteractionButtonController — zeigt/versteckt den Interaktions-Button.
##
## Muss via hud.add_child(ctrl) in den SceneTree eingehängt werden damit
## _ready() und _process() feuern. Das erledigt InteractionButtonComponent.build().
## Vorher war der Controller ein Node, wurde aber NIE in den Tree eingefügt
## → _process() feuerte nie → Button zeigte nie etwas an.
##
## Busy-Zustand:  event-getrieben via EventBus.world
## Proximity:     [STUB-Polling] bis InteractionSensor EventBus.world.proximity_changed emittiert
##
## [STUB] Vollständige event-getriebene Lösung für Phase 2:
##   InteractionSensor emittiert proximity_changed(target: Node3D, in_range: bool)
##   → _process() entfernen, stattdessen:
##   EventBus.world.proximity_changed.connect(_on_proximity_changed)

var _visuals: InteractionButtonVisuals
var _has_target: bool = false
var _is_busy: bool = false


func setup(visuals: InteractionButtonVisuals) -> void:
	_visuals = visuals


func _ready() -> void:
	EventBus.world.interaction_started.connect(_on_interaction_started)
	EventBus.world.interaction_finished.connect(_on_interaction_ended)
	EventBus.world.interaction_cancelled.connect(_on_interaction_ended)
	_update_button()


func _process(_delta: float) -> void:
	## [STUB-Polling] Wird ersetzt durch EventBus.world.proximity_changed
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		if _has_target:
			_has_target = false
			_update_button()
		return

	var player: Node = players[0]
	var target: Node3D = null
	if player.has_method("get_closest_interactable"):
		target = player.get_closest_interactable()

	var new_has_target := is_instance_valid(target)
	if new_has_target != _has_target:
		_has_target = new_has_target
		_update_button()


func _on_interaction_started(_label: String, _duration: float) -> void:
	_is_busy = true
	_update_button()


func _on_interaction_ended(_label: String) -> void:
	_is_busy = false
	_update_button()


func _update_button() -> void:
	_visuals.set_active(_has_target and not _is_busy)
