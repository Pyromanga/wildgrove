extends Node
## StateService.gd — Zentraler Zustandsverwalter

enum PlayerState { FREE, BUSY, MENU }
var current_state: PlayerState = PlayerState.FREE

func set_state(new_state: PlayerState) -> void:
	current_state = new_state
	# Zugriff nun über den Kernel, nicht mehr direkt über den Autoload-Namen
	Kernel.events.log("Player Status: " + PlayerState.keys()[new_state])

func is_free() -> bool:
	return current_state == PlayerState.FREE