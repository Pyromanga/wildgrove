extends Control
## MainMenuController — Controller für das Hauptmenü.

const LOG_CAT := "MainMenu"


func _ready() -> void:
	$StartButton.pressed.connect(_on_start_pressed)
	Logger.log_info("MainMenu bereit.", LOG_CAT)


func _on_start_pressed() -> void:
	if is_instance_valid(Services.game_manager):
		Services.game_manager.change_state(GameEnums.State.PLAYING)
	else:
		Logger.log_error("GameManager nicht verfügbar!", LOG_CAT)
