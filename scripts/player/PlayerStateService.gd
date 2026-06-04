extends ServiceNode
class_name PlayerStateService

## PlayerStateService — Verwaltet den Mikro-State des Spielers (Input-Control).
## Abhängigkeiten (deps): ["savesystem"]

const LOG_CAT := "PlayerStates"

enum State { FREE, BUSY, MENU }

var _current: State = State.FREE
var _save_system: SaveSystem


# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(deps: Dictionary) -> void:
	_save_system = deps.get("savesystem") as SaveSystem

	if _save_system:
		_save_system.register_save_provider(self)

	Logger.log_debug("Konfiguriert.", LOG_CAT)


# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────
func on_ready() -> void:
	# Infrastruktur-Zugriff ist hier okay
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

	# Nur Input-Reset triggern, wenn wir wieder Kontrolle übergeben
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
# Save-Interface (Optional, falls nötig)
# ─────────────────────────────────────────────


func get_save_key() -> String:
	return "player_state"


func get_save_data() -> Dictionary:
	# Meistens wollen wir beim Laden FREE sein,
	# aber wir könnten hier 'busy' speichern, falls Quests das brauchen.
	return {"current_micro_state": _current}


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _reset_inputs() -> void:
	if is_inside_tree():
		get_tree().call_group("touch_input", "reset_input")


func _on_game_state_changed(game_state: int) -> void:
	# Synchronisation mit der globalen State Machine
	if game_state != GameEnums.State.PLAYING:
		set_state(State.MENU)
	else:
		set_state(State.FREE)


func _state_name(s: State) -> String:
	var keys = State.keys()
	if s >= 0 and s < keys.size():
		return keys[s]
	return "UNKNOWN"
