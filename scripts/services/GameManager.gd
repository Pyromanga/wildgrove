extends ServiceNode
class_name GameManager

## GameManager.gd
## Verwaltet den globalen GameState und Szenen-Wechsel.
## Abhängig von: savesystem, states (siehe ServiceLoader deps)

const LOG_CAT := "GameManager"

enum GameState {
	BOOT,           # Spiel startet gerade
	MAIN_MENU,      # Hauptmenü
	LOADING,        # Szene wird geladen
	PLAYING,        # Spiel läuft normal
	PAUSED,         # Pausiert (Menü offen)
	CUTSCENE,       # Cutscene läuft — Input gesperrt
	GAME_OVER,      # Spieler gestorben
	CREDITS,        # Abspann
}

var _current_state: GameState = GameState.BOOT
var _previous_state: GameState = GameState.BOOT
var _save_system: SaveSystem
var _events: GameEvents
@export var config: GameConfig

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	Logger.log_debug("GameManager._ready()", LOG_CAT)
	super._ready()

func init() -> void:
    super.init()
    var save_system = Kernel.get_service("savesystem")
    if save_system:
        save_system.register_save_provider(self)

func on_ready() -> void:
	super.on_ready()
	Logger.log_debug("on_ready() — verbinde Events...", LOG_CAT)

	_events = Kernel.get_service("events") as GameEvents
	if not _events:
		Logger.log_warn("GameEvents nicht gefunden — State-Änderungen werden nicht gebroadcastet.", LOG_CAT)
		return

	# Auf Player-Events reagieren
	_events.player.player_died.connect(_on_player_died)
	Logger.log_debug("player.player_died verbunden.", LOG_CAT)

	Logger.log_info("on_ready() abgeschlossen. GameManager vollständig aktiv.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func get_state() -> GameState:
	return _current_state

func get_state_name() -> String:
	return _state_name(_current_state)

## Wechselt in einen neuen GameState.
## Validiert den Übergang — nicht alle Wechsel sind erlaubt.
func change_state(new_state: GameState) -> void:
	Logger.log_info("change_state(): %s → %s" % [_state_name(_current_state), _state_name(new_state)], LOG_CAT)

	if new_state == _current_state:
		Logger.log_warn("change_state(): bereits in State '%s' — ignoriert." % _state_name(new_state), LOG_CAT)
		return

	if not _is_valid_transition(_current_state, new_state):
		Logger.log_error("Ungültiger State-Übergang: %s → %s!" % [_state_name(_current_state), _state_name(new_state)], LOG_CAT)
		return

	_previous_state = _current_state
	_current_state = new_state

	Logger.log_debug("State gewechselt. Previous: %s, Current: %s" % [_state_name(_previous_state), _state_name(_current_state)], LOG_CAT)

	if _events:
		_events.system.emit_state_changed(_current_state)

## Kehrt zum vorherigen State zurück (z.B. Pause → Playing).
func revert_state() -> void:
	Logger.log_info("revert_state(): %s → %s" % [_state_name(_current_state), _state_name(_previous_state)], LOG_CAT)
	change_state(_previous_state)

func is_playing() -> bool:
	return _current_state == GameState.PLAYING

func is_paused() -> bool:
	return _current_state == GameState.PAUSED

## Speichert den aktuellen Spielstand über das SaveSystem.
func save_game(player_data: Dictionary) -> bool:
	Logger.log_info("save_game() aufgerufen...", LOG_CAT)

	if not _save_system:
		Logger.log_error("SaveSystem nicht verfügbar — Speichern nicht möglich!", LOG_CAT)
		return false

	var state := _build_save_state(player_data)
	Logger.log_debug("Save-State aufgebaut: %s" % str(state.keys()), LOG_CAT)

	var success := _save_system.save_state(state)
	if success:
		Logger.log_info("Spiel erfolgreich gespeichert.", LOG_CAT)
	else:
		Logger.log_error("Speichern fehlgeschlagen!", LOG_CAT)
	return success

# ─────────────────────────────────────────────
# Private
# ─────────────────────────────────────────────

func _apply_save_state(state: Dictionary) -> void:
	Logger.log_debug("_apply_save_state() — wende Spielstand an...", LOG_CAT)

	# Welt-Daten
	var world_data: Dictionary = state.get("world", {})
	Logger.log_debug("Welt: Tag %d, Stunde %d, Seed %d" % [
		world_data.get("day", 1),
		world_data.get("hour", 6),
		world_data.get("seed", 0)
	], LOG_CAT)

	# Spieler-Daten
	var player_data: Dictionary = state.get("player", {})
	Logger.log_debug("Spieler: '%s', Level %d" % [
		player_data.get("name", "?"),
		player_data.get("level", 0)
	], LOG_CAT)

	# Nach BOOT → MAIN_MENU wenn Save existiert, sonst neues Spiel
	if _save_system.has_save():
		Logger.log_info("Spielstand gefunden → State: MAIN_MENU", LOG_CAT)
		_current_state = GameState.MAIN_MENU
	else:
		Logger.log_info("Kein Spielstand → neues Spiel, State: MAIN_MENU", LOG_CAT)
		_current_state = GameState.MAIN_MENU

func _build_save_state(player_data: Dictionary) -> Dictionary:
	Logger.log_debug("_build_save_state()...", LOG_CAT)
	return {
		"player": player_data,
		"world": {
			# Später: Kernel.get_service("worldservice").get_save_data()
		},
	}

func _is_valid_transition(from: GameState, to: GameState) -> bool:
    # 1. Fallback: Falls die Config im Editor nicht zugewiesen wurde
    if not config:
        Logger.log_error("GameManager: Keine GameConfig zugewiesen! Transitions verweigert.", LOG_CAT)
        return false
    
    # 2. Hole die Strings für den Vergleich
    var from_str = _state_name(from)
    var to_str = _state_name(to)
    
    # 3. Hole die Liste aus der Resource (Single Source of Truth!)
    var allowed_targets = config.valid_transitions.get(from_str, [])
    
    # 4. Prüfen
    var is_allowed = to_str in allowed_targets
    
    if not is_allowed:
        Logger.log_warn("Übergang %s → %s nicht in der Config erlaubt." % [from_str, to_str], LOG_CAT)
    
    return is_allowed

func _state_name(state: GameState) -> String:
	return GameState.keys()[state]

# ─────────────────────────────────────────────
# Event-Handler
# ─────────────────────────────────────────────

func _on_player_died() -> void:
	Logger.log_warn("_on_player_died() empfangen → wechsle zu GAME_OVER", LOG_CAT)
	change_state(GameState.GAME_OVER)