extends ServiceNode
# justified: get_tree().call_deferred('change_scene_to_file') -- direkter SceneTree-Zugriff noetig.
class_name SceneManager

const LOG_CAT := "SceneManager"

var _bus: IEventBus

func configure(deps: ServiceDeps) -> void:
	_bus = deps.require(ServiceKeys.EVENT_BUS) as IEventBus
	AppLogger.log_info("SceneManager konfiguriert.", LOG_CAT)

func on_ready() -> void:
	_bus.ui().scene_reload_requested.connect(
		func() -> void: change_scene("res://scenes/World.tscn")
	)
	AppLogger.log_info("SceneManager bereit.", LOG_CAT)

func on_cleanup() -> void:
	if _bus and _bus.ui().scene_reload_requested.is_connected(change_scene.bind("res://scenes/World.tscn")):
		pass  # Lambda-Disconnect nicht möglich — Signal wird mit SceneManager freigegeben
	AppLogger.log_info("SceneManager cleanup.", LOG_CAT)

## FIX (Round 113 Nachtrag): PLAYING statt LOADING gemappt war ein Henne-Ei-
## Deadlock — PLAYING wird erst über world_scene_ready erreicht (GameManager.
## _on_world_scene_ready()), und world_scene_ready kann nur feuern, wenn
## WorldScopeInitializer (Child-Node IN World.tscn) bereits existiert und
## ready ist. Mit PLAYING als Trigger wurde World.tscn also nie geladen —
## Session blieb für immer auf MainMenu.tscn hängen (LOADING-State intern
## erreicht, aber sichtbar nichts passiert). LOADING ist der State, der laut
## GameManager._on_session_ready()-Kommentar exakt "Welt wird gebootet"
## bedeutet — das ist der richtige Zeitpunkt für den Szenenwechsel.
const STATE_SCENE_MAP := {
	GameEnums.State.MAIN_MENU: "res://scenes/MainMenu.tscn",
	GameEnums.State.LOADING: "res://scenes/World.tscn",
	GameEnums.State.GAME_OVER: "res://scenes/GameOver.tscn"
}

func transition_to_state(state: GameEnums.State) -> void:
	var path = STATE_SCENE_MAP.get(state)
	if path:
		AppLogger.log_info(
			"Wechsle Szene für State %s -> %s" % [GameEnums.State.keys()[state], path], LOG_CAT
		)
		if not get_tree():
			AppLogger.log_error("SceneManager hat keinen SceneTree — Szenenwechsel abgebrochen!", LOG_CAT)
			return
		get_tree().call_deferred("change_scene_to_file", path)
		AppLogger.log_debug("call_deferred(change_scene_to_file) abgesetzt.", LOG_CAT)
	else:
		AppLogger.log_debug(
			"Kein Szenenwechsel für State: %s" % GameEnums.State.keys()[state], LOG_CAT
		)

func change_scene(path: String) -> void:
	AppLogger.log_info("Wechsle Szene zu: %s" % path, LOG_CAT)
	get_tree().call_deferred("change_scene_to_file", path)
