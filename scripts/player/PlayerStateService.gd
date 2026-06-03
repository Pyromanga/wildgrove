extends ServiceNode
class_name PlayerStateService

## PlayerStateService — Verwaltet den Mikro-State des Spielers (Input-Control).

const LOG_CAT := "PlayerStates"

enum State { FREE, BUSY, MENU }

var _current: State = State.FREE

func init() -> void:
	Logger.log_debug("Initialisiert.", LOG_CAT)

func on_ready() -> void:
	EventBus.system.state_changed.connect(_on_game_state_changed)
	Logger.log_info("PlayerStateService bereit.", LOG_CAT)

func set_state(new_state: State) -> void:
	if new_state == _current:
		return
	Logger.log_debug("Wechsel: %s → %s" % [_state_name(_current), _state_name(new_state)], LOG_CAT)
	_current = new_state
	if new_state == State.FREE:
		get_tree().call_group("touch_input", "reset_input")

func get_state() -> State:
	return _current

func is_free() -> bool:    return _current == State.FREE
func is_busy() -> bool:    return _current == State.BUSY
func is_in_menu() -> bool: return _current == State.MENU

func _on_game_state_changed(game_state: int) -> void:
	# FIX: state_changed emittiert int (via emit_state_changed in SystemEvents),
	# nicht GameEnums.State direkt — cast für den Vergleich nötig.
	if game_state != GameEnums.State.PLAYING:
		set_state(State.MENU)
	else:
		set_state(State.FREE)

func _state_name(s: State) -> String:
	return State.keys()[s]