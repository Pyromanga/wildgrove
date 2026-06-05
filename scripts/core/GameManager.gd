extends ServiceNode
class_name GameManager

const LOG_CAT := "GameManager"

var _current_state: GameEnums.State = GameEnums.State.BOOT
var _scene_manager: SceneManager
var _config: GameConfig


func configure(deps: Dictionary) -> void:
	_scene_manager = deps.get("scenemanager")
	_config = load("res://config/GameConfig.tres") as GameConfig
	if not _config:
		Logger.log_warn("GameConfig.tres nicht geladen — Übergänge unkontrolliert.", LOG_CAT)


func start_game() -> void:
	# MainMenu ist bereits die laufende Startszene (run/main_scene in project.godot).
	# Wir setzen den State intern ohne einen Szenenwechsel auszulösen.
	_current_state = GameEnums.State.MAIN_MENU
	Logger.log_info("State initialisiert: MAIN_MENU", LOG_CAT)
	EventBus.system.emit_state_changed(_current_state)


func change_state(new_state: GameEnums.State) -> void:
	if new_state == _current_state:
		return

	if not StateValidator.is_transition_allowed(_current_state, new_state, _config):
		return

	Logger.log_info(
		(
			"State: %s → %s"
			% [GameEnums.State.keys()[_current_state], GameEnums.State.keys()[new_state]]
		),
		LOG_CAT
	)
	_current_state = new_state

	if _scene_manager:
		_scene_manager.transition_to_state(_current_state)

	EventBus.system.emit_state_changed(_current_state)


func get_state() -> GameEnums.State:
	return _current_state


func is_playing() -> bool:
	return _current_state == GameEnums.State.PLAYING
