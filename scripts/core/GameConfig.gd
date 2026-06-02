class_name GameConfig extends Resource

## GameConfig — Konfiguriert erlaubte State-Übergänge.
## Wird GameManager als @export zugewiesen.
## HINWEIS: Nutzt GameEnums.State (nicht mehr GameState).

@export var valid_transitions: Dictionary = {
	GameEnums.State.BOOT:      [GameEnums.State.MAIN_MENU, GameEnums.State.LOADING],
	GameEnums.State.MAIN_MENU: [GameEnums.State.LOADING, GameEnums.State.CREDITS],
	GameEnums.State.LOADING:   [GameEnums.State.PLAYING, GameEnums.State.MAIN_MENU],
	GameEnums.State.PLAYING:   [GameEnums.State.PAUSED, GameEnums.State.GAME_OVER,
								GameEnums.State.CUTSCENE, GameEnums.State.LOADING,
								GameEnums.State.MAIN_MENU],
	GameEnums.State.PAUSED:    [GameEnums.State.PLAYING, GameEnums.State.MAIN_MENU],
	GameEnums.State.CUTSCENE:  [GameEnums.State.PLAYING, GameEnums.State.MAIN_MENU],
	GameEnums.State.GAME_OVER: [GameEnums.State.MAIN_MENU, GameEnums.State.LOADING],
	GameEnums.State.CREDITS:   [GameEnums.State.MAIN_MENU],
}