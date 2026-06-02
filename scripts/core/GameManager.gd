extends ServiceNode
class_name GameManager

const LOG_CAT := "GameManager"

# ─────────────────────────────────────────────
# State & Config
# ─────────────────────────────────────────────
var _current_state:  GameEnums.State = GameEnums.State.BOOT
var _previous_state: GameEnums.State = GameEnums.State.BOOT

@export var config: GameConfig

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

## Phase 4: Abhängigkeiten verknüpfen.
## WICHTIG: Da 'savesystem' in den deps steht, ist Services.save_system garantiert nicht null!
func init() -> void:
	Logger.log_debug("init() — Verbinde SaveSystem...", LOG_CAT)
	Services.save_system.register_save_provider(self)

## Phase 5: Signale connecten.
## WICHTIG: EventBus ist ein AutoLoad, also immer verfügbar.
func on_ready() -> void:
	Logger.log_debug("on_ready() — Verbinde Events...", LOG_CAT)
	
	# Wir nutzen den EventBus direkt, statt ihn als Service zu suchen
	EventBus.player.player_died.connect(_on_player_died)
	
	Logger.log_info("GameManager vollständig aktiv.", LOG_CAT)

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
	if new_state == _current_state: return

	if not _is_valid_transition(_current_state, new_state):
		Logger.log_error("Ungültiger Übergang: %s -> %s" % [_state_name(_current_state), _state_name(new_state)], LOG_CAT)
		return

	_previous_state = _current_state
	_current_state  = new_state

	Logger.log_info("State gewechselt -> %s" % _state_name(_current_state), LOG_CAT)

	# Signal über den EventBus feuern
	EventBus.system.emit_state_changed(_current_state)

func revert_state() -> void:
	Logger.log_info(
		"revert_state(): %s → %s" % [_state_name(_current_state), _state_name(_previous_state)],
		LOG_CAT
	)
	change_state(_previous_state)

## Speichert den aktuellen Spielstand.
func save_game(player_data: Dictionary) -> bool:
	var state := _build_save_state(player_data)
	
	# Direkter Zugriff auf Services
	var success: bool = Services.save_system.save_state(state)
	return success

# ─────────────────────────────────────────────
# Private & Helfer
# ─────────────────────────────────────────────

func _build_save_state(player_data: Dictionary) -> Dictionary:
	return {
		"player": player_data,
		"world": Services.world.get_save_data() if Services.world else {},
	}

# ... (_is_valid_transition, _state_name etc. bleiben identisch) ...




## Wendet einen geladenen Spielstand an.
## Wird vom SaveSystem nach dem Laden aufgerufen.
func apply_save_state(state: Dictionary) -> void:
	Logger.log_debug("apply_save_state() aufgerufen.", LOG_CAT)

	var world_data:  Dictionary = state.get("world",  {})
	var player_data: Dictionary = state.get("player", {})

	Logger.log_debug(
		"Welt: Tag %d, Stunde %d, Seed %d" % [
			world_data.get("day",  1),
			world_data.get("hour", 6),
			world_data.get("seed", 0),
		],
		LOG_CAT
	)
	Logger.log_debug(
		"Spieler: '%s', Level %d" % [player_data.get("name", "?"), player_data.get("level", 0)],
		LOG_CAT
	)

	# Nach BOOT immer ins MAIN_MENU — egal ob Save vorhanden oder nicht.
	# Der tatsächliche Spielstart passiert über UI-Events.
	_current_state = GameEnums.State.MAIN_MENU
	Logger.log_info("State nach Save-Load: MAIN_MENU", LOG_CAT)

# ─────────────────────────────────────────────
# Private
# ─────────────────────────────────────────────


## Prüft ob ein State-Übergang erlaubt ist.
## Nutzt GameConfig wenn gesetzt, sonst einen konservativen Hardcoded-Fallback.
func _is_valid_transition(from: GameEnums.State, to: GameEnums.State) -> bool:
	if config:
		var from_str := _state_name(from)
		var to_str   := _state_name(to)
		var allowed: Array = config.valid_transitions.get(from_str, [])
		var ok := to_str in allowed
		if not ok:
			Logger.log_warn("Übergang %s → %s nicht in Config erlaubt." % [from_str, to_str], LOG_CAT)
		return ok

	# Fallback: Config nicht gesetzt — minimal erlaubte Übergänge damit das Spiel startet.
	Logger.log_warn("Keine GameConfig — nutze Fallback-Transitions.", LOG_CAT)
	return _fallback_transition_allowed(from, to)

## Minimaler Fallback damit BOOT → MAIN_MENU und grundlegende Übergänge immer klappen.
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

# ─────────────────────────────────────────────
# Event-Handler
# ─────────────────────────────────────────────

func _on_player_died() -> void:
	Logger.log_warn("Spieler gestorben → GAME_OVER", LOG_CAT)
	change_state(GameEnums.State.GAME_OVER)