# res://tests/mocks/MockContextPlayer.gd
extends Node3D
class_name MockContextPlayer

## Minimaler Test-Double für ContextMenuController._on_open_requested() (BUGFIX 2026-09-26,
## "Kontextmenü soll alles anzeigen was in der Nähe ist"): zeichnet auf, OB
## get_all_nearby_context_actions() statt des alten Einzel-Ziel-Pfads get_context_actions()
## aufgerufen wurde — ohne einen echten Player (Multiplayer-Sync, Sensor, Kamera, ...)
## aufbauen zu müssen. Muss in Gruppe "player" stehen, damit IUIContext.get_local_player()
## (Default-Implementierung, scannt die Gruppe) ihn findet.

var actions_to_return: Array[InteractableAction] = []
var all_nearby_call_count: int = 0
var single_target_call_count: int = 0

func get_all_nearby_context_actions() -> Array[InteractableAction]:
	all_nearby_call_count += 1
	return actions_to_return

func get_context_actions() -> Array[InteractableAction]:
	single_target_call_count += 1
	return actions_to_return
