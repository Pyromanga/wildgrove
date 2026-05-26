extends Node

enum PlayerState { FREE, BUSY, MENU }
var current_state = PlayerState.FREE

func set_state(new_state: PlayerState):
	current_state = new_state
	GameEvents.log("Player Status: " + PlayerState.keys()[new_state])

func is_free() -> bool:
	return current_state == PlayerState.FREE