extends ServiceNode
class_name SceneManager

const LOG_CAT := "SceneManager"


func configure(_deps: Dictionary) -> void:
	Logger.log_info("SceneManager konfiguriert.", LOG_CAT)


const STATE_SCENE_MAP := {
	GameEnums.State.MAIN_MENU: "res://scenes/MainMenu.tscn",
	GameEnums.State.PLAYING: "res://scenes/World.tscn",
	GameEnums.State.GAME_OVER: "res://scenes/GameOver.tscn"
}


func transition_to_state(state: GameEnums.State) -> void:
	var path = STATE_SCENE_MAP.get(state)
	if path:
		Logger.log_info(
			"Wechsle Szene für State %s: %s" % [GameEnums.State.keys()[state], path], LOG_CAT
		)
		get_tree().call_deferred("change_scene_to_file", path)
	else:
		Logger.log_debug(
			"Kein Szenenwechsel für State: %s" % GameEnums.State.keys()[state], LOG_CAT
		)


func change_scene(path: String) -> void:
	Logger.log_info("Wechsle Szene zu: %s" % path, LOG_CAT)
	get_tree().call_deferred("change_scene_to_file", path)
