extends ServiceNode
class_name PlayerStateService

## PlayerStateService — Verwaltet den Mikro-State des Spielers (Input-Control).
## Koppelt Bewegung und Interaktion von Menü-Zuständen ab.

const LOG_CAT := "PlayerStates"

enum State { FREE, BUSY, MENU }

var _current: State = State.FREE

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	# Dieser Service ist meist ein "Blatt-Service" (keine deps).
	Logger.log_debug("Initialisiert.", LOG_CAT)

func on_ready() -> void:
	# Wir könnten hier auf den EventBus hören, um bei GAME_OVER 
	# automatisch in den MENU State zu gehen.
	EventBus.system.state_changed.connect(_on_game_state_changed)
	Logger.log_info("PlayerStateService bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func set_state(new_state: State) -> void:
	if new_state == _current:
		return
		
	Logger.log_debug("Wechsel: %s → %s" % [_state_name(_current), _state_name(new_state)], LOG_CAT)
	_current = new_state

	# Signalisierung an die Welt
	# EventBus.player.state_changed.emit(new_state)

	# Touch-Input Handling (Sauberer über Gruppen-Call)
	if new_state == State.FREE:
		get_tree().call_group("touch_input", "reset_input")

func get_state() -> State:
	return _current

func is_free() -> bool: return _current == State.FREE
func is_busy() -> bool: return _current == State.BUSY
func is_in_menu() -> bool: return _current == State.MENU

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _on_game_state_changed(game_state: GameEnums.State) -> void:
	# Wenn das Spiel pausiert oder ins Menü geht, erzwingen wir den MENU State für den Spieler
	if game_state != GameEnums.State.PLAYING:
		set_state(State.MENU)
	else:
		set_state(State.FREE)

func _state_name(s: State) -> String:
	return State.keys()[s]