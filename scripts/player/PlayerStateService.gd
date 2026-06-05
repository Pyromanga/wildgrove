extends ServiceNode
class_name PlayerStateService

## PlayerStateService — Verwaltet den Mikro-State des Spielers (Input-Control).
##
## Kein SaveSystem mehr: Der Micro-State (FREE/BUSY/MENU) ist immer flüchtig.
## Beim Laden wird er stets auf FREE zurückgesetzt — Speichern ist sinnlos.
## Früher war "playerstates" als Dep von sich selbst auf SaveSystem eingetragen;
## das ist jetzt entfernt (auch in BootstrapConfig.tres).

const LOG_CAT := "PlayerStates"

enum State { FREE, BUSY, MENU }

var _current: State = State.FREE


# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(_deps: Dictionary) -> void:
	Logger.log_debug("Konfiguriert (kein Savesystem-Provider mehr).", LOG_CAT)


# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────
func on_ready() -> void:
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

	if new_state == State.FREE:
		_reset_inputs()


func get_state() -> State:
	return _current


func is_free() -> bool:
	return _current == State.FREE


func is_busy() -> bool:
	return _current == State.BUSY


func is_in_menu() -> bool:
	return _current == State.MENU


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _reset_inputs() -> void:
	if is_inside_tree():
		get_tree().call_group("touch_input", "reset_input")


func _on_game_state_changed(game_state: int) -> void:
	if game_state != GameEnums.State.PLAYING:
		set_state(State.MENU)
	else:
		set_state(State.FREE)


func _state_name(s: State) -> String:
	var keys = State.keys()
	if s >= 0 and s < keys.size():
		return keys[s]
	return "UNKNOWN"
