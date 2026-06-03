extends ServiceNode
class_name GameManager

## GameManager — Verwaltet den globalen Spielzustand (State Machine).
## Abhängigkeiten (deps): ["savesystem", "playerstates"]

const LOG_CAT := "GameManager"

var _current_state:  GameEnums.State = GameEnums.State.BOOT
var _previous_state: GameEnums.State = GameEnums.State.BOOT

@export var config: GameConfig

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	Logger.log_debug("init() — Verbinde SaveSystem...", LOG_CAT)
	Services.save_system.register_save_provider(self)

func on_ready() -> void:
	Logger.log_debug("on_ready() — Verbinde Events...", LOG_CAT)
	EventBus.player.player_died.connect(_on_player_died)
	Services.save_system.load_game()
	Logger.log_info("GameManager vollständig aktiv.", LOG_CAT)

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return "gamemanager"

func get_save_data() -> Dictionary:
	return {"state": _state_name(_current_state)}

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func get_state() -> GameEnums.State:
	return _current_state

func get_state_name() -> String:
	return _state_name(_current_state)

func is_playing() -> bool:
	return _current_state == GameEnums.State.PLAYING

func is_paused() -> bool:
	return _current_state == GameEnums.State.PAUSED

func change_state(new_state: GameEnums.State) -> void:
	if new_state == _current_state:
		return
	if not _is_valid_transition(_current_state, new_state):
		Logger.log_error(
			"Ungültiger Übergang: %s → %s" % [_state_name(_current_state), _state_name(new_state)],
			LOG_CAT
		)
		return
	_previous_state = _current_state
	_current_state  = new_state
	Logger.log_info("State → %s" % _state_name(_current_state), LOG_CAT)
	EventBus.system.emit_state_changed(_current_state)

func revert_state() -> void:
	Logger.log_info(
		"revert_state(): %s → %s" % [_state_name(_current_state), _state_name(_previous_state)],
		LOG_CAT
	)
	change_state(_previous_state)

func save_game(player_data: Dictionary) -> bool:
	# FIX: War Services.save_system.save_state(state) — Methode heißt save_game().
	# GameManager sammelt hier den State und delegiert an SaveSystem.
	# SaveSystem selbst fragt alle Provider via get_save_data() ab,
	# daher reicht ein einfacher save_game()-Aufruf ohne Extra-Payload.
	return Services.save_system.save_game()

func apply_save_state(state: Dictionary) -> void:
	Logger.log_debug("apply_save_state() aufgerufen.", LOG_CAT)
	var world_data:  Dictionary = state.get("world",  {})
	var player_data: Dictionary = state.get("player", {})
	Logger.log_debug(
		"Welt: Tag %d, Stunde %d" % [world_data.get("day", 1), world_data.get("hour", 6)],
		LOG_CAT
	)
	Logger.log_debug(
		"Spieler: '%s', Level %d" % [player_data.get("name", "?"), player_data.get("level", 0)],
		LOG_CAT
	)
	_current_state = GameEnums.State.MAIN_MENU
	Logger.log_info("State nach Save-Load: MAIN_MENU", LOG_CAT)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _is_valid_transition(from: GameEnums.State, to: GameEnums.State) -> bool:
	if config:
		var from_str: String = _state_name(from)
		var to_str:   String = _state_name(to)
		var allowed: Array   = config.valid_transitions.get(from_str, [])
		var ok := to_str in allowed
		if not ok:
			Logger.log_warn("Übergang %s → %s nicht in Config erlaubt." % [from_str, to_str], LOG_CAT)
		return ok
	Logger.log_warn("Keine GameConfig — nutze Fallback-Transitions.", LOG_CAT)
	return _fallback_transition_allowed(from, to)

func _fallback_transition_allowed(from: GameEnums.State, to: GameEnums.State) -> bool:
	const FALLBACK: Dictionary = {
		GameEnums.State.BOOT:      [GameEnums.State.MAIN_MENU],
		GameEnums.State.MAIN_MENU: [GameEnums.State.LOADING, GameEnums.State.CREDITS],
		GameEnums.State.LOADING:   [GameEnums.State.PLAYING],
		GameEnums.State.PLAYING:   [GameEnums.State.PAUSED, GameEnums.State.GAME_OVER, GameEnums.State.CUTSCENE],
		GameEnums.State.PAUSED:    [GameEnums.State.PLAYING, GameEnums.State.MAIN_MENU],
		GameEnums.State.GAME_OVER: [GameEnums.State.MAIN_MENU],
		GameEnums.State.CUTSCENE:  [GameEnums.State.PLAYING],
		GameEnums.State.CREDITS:   [GameEnums.State.MAIN_MENU],
	}
	var allowed: Array = FALLBACK.get(from, [])
	return to in allowed

func _state_name(state: GameEnums.State) -> String:
	return GameEnums.State.keys()[state]

func _on_player_died() -> void:
	Logger.log_warn("Spieler gestorben → GAME_OVER", LOG_CAT)
	change_state(GameEnums.State.GAME_OVER)