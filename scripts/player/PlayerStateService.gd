extends ServiceNode
class_name PlayerStateService

## PlayerStateService — Verwaltet den Mikro-State des Spielers.
## FREE:  Spieler kann sich bewegen und interagieren.
## BUSY:  Spieler führt eine Aktion aus (Holz hacken, graben, ...).
## MENU:  Ein Menü ist offen, Input gesperrt.
##
## NICHT verwechseln mit GameManager-States (BOOT, PLAYING, PAUSED...) —
## das sind Makro-States des Spiels, dieser hier ist Mikro-State des Spielers.

const LOG_CAT := "PlayerStates"

enum PlayerState { FREE, BUSY, MENU }

var _current: PlayerState = PlayerState.FREE

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	super._ready()

func init() -> void:
	super.init()

func on_ready() -> void:
	super.on_ready()
	Logger.log_info("PlayerStateService bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func set_state(new_state: PlayerState) -> void:
	if new_state == _current:
		return
	Logger.log_debug("%s → %s" % [_state_name(_current), _state_name(new_state)], LOG_CAT)
	_current = new_state

	# Touch-Input zurücksetzen wenn State wechselt
	if new_state == PlayerState.FREE:
		var touch_nodes := get_tree().get_nodes_in_group("touch_input")
		if not touch_nodes.is_empty():
			touch_nodes[0].reset_input()

func get_state() -> PlayerState:
	return _current

func is_free() -> bool:
	return _current == PlayerState.FREE

func is_busy() -> bool:
	return _current == PlayerState.BUSY

func is_in_menu() -> bool:
	return _current == PlayerState.MENU

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _state_name(s: PlayerState) -> String:
	return PlayerState.keys()[s]