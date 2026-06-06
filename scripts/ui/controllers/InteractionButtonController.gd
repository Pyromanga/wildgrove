class_name InteractionButtonController
extends Node

## InteractionButtonController — zeigt/versteckt den Interaktions-Button.
##
## Muss via hud.add_child(ctrl) in den SceneTree eingehängt werden damit
## _ready() und _process() feuern. Das erledigt InteractionButtonComponent.build().
##
## FIX (Stub aufgelöst): _process()-Polling durch EventBus.world.proximity_changed
## ersetzt. InteractionSensor emittiert jetzt proximity_changed wenn sich der
## nächste Interagierbare ändert — kein Frame-by-Frame get_nodes_in_group() mehr.

var _visuals: InteractionButtonVisuals
var _has_target: bool = false
var _is_busy: bool = false


func setup(visuals: InteractionButtonVisuals) -> void:
	_visuals = visuals


func _ready() -> void:
	EventBus.world.interaction_started.connect(_on_interaction_started)
	EventBus.world.interaction_finished.connect(_on_interaction_ended)
	EventBus.world.interaction_cancelled.connect(_on_interaction_ended)
	# Stub aufgelöst: event-getrieben statt Polling
	EventBus.world.proximity_changed.connect(_on_proximity_changed)
	_update_button()


func _on_proximity_changed(target: Node3D, in_range: bool) -> void:
	var new_has_target := in_range and is_instance_valid(target)
	if new_has_target != _has_target:
		_has_target = new_has_target
		_update_button()


func _on_interaction_started(_action_id: String, _label: String, _duration: float) -> void:
	_is_busy = true
	_update_button()


func _on_interaction_ended(_action_id: String, _label: String) -> void:
	_is_busy = false
	_update_button()


func _update_button() -> void:
	if is_instance_valid(_visuals):
		_visuals.set_active(_has_target and not _is_busy)
