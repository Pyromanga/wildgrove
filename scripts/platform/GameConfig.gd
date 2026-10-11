class_name GameConfig extends Resource

## GameConfig — Konfiguriert erlaubte State-Übergänge.
## WICHTIG: Keys sind Strings (z.B. "BOOT"), keine Enum-Ints.
## StateValidator.is_transition_allowed() nutzt GameEnums.State.keys()[state]
## um den int in einen String zu konvertieren, und schlägt dann hier nach.

@export var valid_transitions: Dictionary = {
	"BOOT": ["MAIN_MENU", "LOADING"],
	"MAIN_MENU": ["LOADING", "CREDITS", "PLAYING"],
	"LOADING": ["PLAYING", "MAIN_MENU"],
	"PLAYING": ["PAUSED", "GAME_OVER", "CUTSCENE", "LOADING", "MAIN_MENU"],
	"PAUSED": ["PLAYING", "MAIN_MENU"],
	"CUTSCENE": ["PLAYING", "MAIN_MENU"],
	"GAME_OVER": ["MAIN_MENU", "LOADING"],
	"CREDITS": ["MAIN_MENU"],
}
