extends ServiceNode
class_name SceneManager

const LOG_CAT := "SceneManager"

func configure(_deps: Dictionary) -> void:
    Logger.log_info("SceneManager konfiguriert.", LOG_CAT)

func change_scene(path: String) -> void:
    Logger.log_info("Wechsle Szene zu: %s" % path, LOG_CAT)
    get_tree().call_deferred("change_scene_to_file", path)