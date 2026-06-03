class_name InteractionButtonController
extends Node

## InteractionButtonController — zeigt/versteckt den Interaktions-Button.
##
## FIX: setup() nahm früher (visuals, player) als 2 Args.
## InteractionButtonComponent hat aber keinen Player-Zugriff zur Build-Zeit
## (der Player existiert noch nicht wenn HUDBuilder läuft).
##
## Lösung: Player wird lazy via Gruppe "player" aufgelöst.
## Das ist sicher weil _process() erst läuft wenn der Node im Baum ist,
## und der Player bis dahin längst in der Szene existiert.

var _visuals: InteractionButtonVisuals

# FIX: Nur 1 Argument — kein Player mehr zur Init-Zeit nötig.
func setup(visuals: InteractionButtonVisuals) -> void:
	_visuals = visuals

func _process(_delta: float) -> void:
	# Lazy Player-Lookup — einmal pro Frame, aber nur wenn sichtbar/aktiv.
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_visuals.set_active(false)
		return

	var player: Node = players[0]
	var target: Node3D = null
	if player.has_method("get_closest_interactable"):
		target = player.get_closest_interactable()

	_visuals.set_active(is_instance_valid(target))