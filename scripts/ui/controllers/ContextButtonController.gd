class_name ContextButtonController
extends Node

## ContextButtonController — zeigt den Kontext-Button wenn ein Ziel in Reichweite.
##
## FIX/Upgrade: War ein reines RefCounted-Objekt ohne Node-Lifecycle.
## Jetzt extends Node damit _ready() feuert und EventBus-Verbindungen korrekt
## aufgebaut werden können.
##
## Lauscht auf proximity_changed um den Button ein/auszublenden statt ihn
## immer zu zeigen. ContextMenuComponent muss den Controller per hud.add_child()
## in den Tree einhängen.

var _visuals: ContextButtonVisuals
var _event_bus: UIEvents
var _has_target: bool = false


func setup(visuals: ContextButtonVisuals, event_bus: UIEvents) -> void:
	_visuals = visuals
	_event_bus = event_bus
	_visuals.button.pressed.connect(_on_pressed)


func _ready() -> void:
	EventBus.world.proximity_changed.connect(_on_proximity_changed)
	_update_visibility()


func _on_proximity_changed(_target: Node3D, in_range: bool) -> void:
	_has_target = in_range
	_update_visibility()


func _on_pressed() -> void:
	_event_bus.emit_request_context_menu()


func _update_visibility() -> void:
	if is_instance_valid(_visuals):
		_visuals.button.visible = _has_target
