extends ServiceNode
class_name GameManager

## GameManager — Verwaltet den globalen Spielzustand.
## Abhängigkeiten (deps): ["savesystem", "playerstates"]

const LOG_CAT := "GameManager"

var _current_state:  GameEnums.State = GameEnums.State.BOOT
var _previous_state: GameEnums.State = GameEnums.State.BOOT

# Lokale Referenzen statt globalem Zugriff während des Bootens
var _save_system: SaveSystem
var _scene_manager: SceneManager
@export var config: GameConfig

# ─────────────────────────────────────────────
# Phase 4: Configure (Injection)
# ─────────────────────────────────────────────

func configure(deps: Dictionary) -> void:
	_save_system = deps.get("savesystem") as SaveSystem
  _scene_manager = deps.get("scenemanager") as SceneManager
	
  if not _scene_manager:
    Logger.log_error("SceneManager fehlt in den Dependencies!", LOG_CAT)
	
	if _save_system:
		Logger.log_debug("configure() — Registriere als SaveProvider...", LOG_CAT)
		_save_system.register_save_provider(self)
	else:
		Logger.log_error("SaveSystem fehlt in Dependencies!", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────

func on_ready() -> void:
	Logger.log_debug("on_ready() — Verbinde Events...", LOG_CAT)
	# EventBus ist ein globales Infrastruktur-Autoload, das ist hier sicher.
	EventBus.player.player_died.connect(_on_player_died)

# ─────────────────────────────────────────────
# Phase 6: Start (Gerufen vom Orchestrator)
# ─────────────────────────────────────────────

func start_game() -> void:
	Logger.log_info("start_game() — Orchestrator gibt Startschuss.", LOG_CAT)
	
	# JETZT erst laden wir das Spiel, da alle Services (Inventory etc.) 
	# im Services-Autoload bereitstehen.
	if _save_system:
		_save_system.load_game()
	
	# Erster State-Wechsel
	change_state(GameEnums.State.MAIN_MENU)
	Logger.log_info("GameManager vollständig aktiv. State: MAIN_MENU", LOG_CAT)

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

func is_playing() -> bool:
	return _current_state == GameEnums.State.PLAYING

func change_state(new_state: GameEnums.State) -> void:
	if new_state == _current_state: return
	
	if not _is_valid_transition(_current_state, new_state):
		Logger.log_error("Ungültiger Übergang...", LOG_CAT)
		return
		
	_previous_state = _current_state
	_current_state  = new_state
	
	Logger.log_info("State → %s" % _state_name(_current_state), LOG_CAT)
	
	# --- NEUE, SAUBERE SZENENWECHSEL LOGIK ---
	if _scene_manager:
		match _current_state:
			GameEnums.State.MAIN_MENU:
				_scene_manager.change_scene("res://scenes/MainMenu.tscn")
			GameEnums.State.PLAYING:
				_scene_manager.change_scene("res://scenes/World.tscn")
	# ----------------------------------------

	EventBus.system.emit_state_changed(_current_state)

# Die save_game Methode nutzt jetzt die lokale Referenz
func save_game() -> bool:
	if _save_system:
		return _save_system.save_game()
	return false

# ─────────────────────────────────────────────
# Ergänzende Öffentliche API
# ─────────────────────────────────────────────

func get_state() -> GameEnums.State:
	return _current_state

func get_state_name() -> String:
	return _state_name(_current_state)

func is_paused() -> bool:
	return _current_state == GameEnums.State.PAUSED

func revert_state() -> void:
	Logger.log_info(
		"revert_state(): %s → %s" % [_state_name(_current_state), _state_name(_previous_state)],
		LOG_CAT
	)
	change_state(_previous_state)

func apply_save_state(state: Dictionary) -> void:
	# Wird vom SaveSystem gerufen, wenn Daten geladen wurden
	Logger.log_debug("apply_save_state() aufgerufen.", LOG_CAT)
	
	# Hier setzen wir den geladenen State um
	# Falls im Save "PLAYING" stand, gehen wir zum Main Menu (Sicherheits-Standard)
	_current_state = GameEnums.State.MAIN_MENU
	Logger.log_info("State nach Save-Load: MAIN_MENU", LOG_CAT)

# ─────────────────────────────────────────────
# Intern & Hilfsfunktionen
# ─────────────────────────────────────────────

func _is_valid_transition(from: GameEnums.State, to: GameEnums.State) -> bool:
	if config:
		var from_str: String = _state_name(from)
		var to_str:   String = _state_name(to)
		var allowed: Array   = config.valid_transitions.get(from_str, [])
		var ok := to_str in allowed
		if not ok:
			Logger.log_warn("Übergang %s → %s laut Config nicht erlaubt." % [from_str, to_str], LOG_CAT)
		return ok
	
	# Fallback, falls keine Resource zugewiesen ist
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
	# Gibt den String-Namen des Enums zurück (z.B. "PLAYING")
	return GameEnums.State.keys()[state]

func _on_player_died() -> void:
	Logger.log_warn("Spieler gestorben → GAME_OVER", LOG_CAT)
	change_state(GameEnums.State.GAME_OVER)