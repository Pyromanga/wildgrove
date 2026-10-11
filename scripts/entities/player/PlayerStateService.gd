extends Service
class_name PlayerStateService

## PlayerStateService — Verwaltet den Mikro-State der Spieler (Input-Control).
##
## Verwaltet den Spieler-State (FREE/BUSY/MENU) und publiziert Änderungen via EventBus.
## Entities abonnieren EventBus.player.player_state_changed — kein direkter Poll nötig.
##
## set_state()/get_state() bekommen peer_id: int = 1 — bestehende Aufrufer unverändert.

const LOG_CAT := "PlayerStates"

enum State { FREE, BUSY, MENU }

## Multi-Tenant State: { peer_id: State }
var _current: Dictionary = {}
var _bus:     IEventBus

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _get_state(peer_id: int) -> State:
	return _current.get(peer_id, State.FREE) as State

# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(deps: ServiceDeps) -> void:
	# BUG-FIX (analog BUG-24 in WorldService): war fälschlich .require() —
	# widersprach dem dokumentierten Vertrag "configure() ohne deps" (siehe
	# test_player_state_service.gd) und crashte bei fehlendem event_bus
	# indirekt in on_ready()/on_cleanup()/set_state() mit
	# "Nonexistent function 'system' in base 'Nil'". Jetzt optional mit
	# Null-Guards an allen Nutzungsstellen.
	_bus = deps.get_optional(ServiceKeys.EVENT_BUS) as IEventBus
	AppLogger.log_debug("Konfiguriert.", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────
func on_ready() -> void:
	if is_instance_valid(_bus):
		_bus.system().state_changed.connect(_on_game_state_changed)
	else:
		AppLogger.log_warn("EventBus fehlt — state_changed nicht verbunden.", LOG_CAT)
	AppLogger.log_info("PlayerStateService bereit.", LOG_CAT)

func on_cleanup() -> void:
	if is_instance_valid(_bus) and _bus.system().state_changed.is_connected(_on_game_state_changed):
		_bus.system().state_changed.disconnect(_on_game_state_changed)
	AppLogger.log_info("PlayerStateService cleanup.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func set_state(new_state: State, peer_id: int = 1) -> void:
	if new_state == _get_state(peer_id):
		return

	AppLogger.log_debug(
		"Spieler %d: Wechsel: %s → %s" % [peer_id, _state_name(_get_state(peer_id)), _state_name(new_state)],
		LOG_CAT
	)
	_current[peer_id] = new_state

	if new_state == State.FREE:
		_reset_inputs()

	if is_instance_valid(_bus):
		_bus.player().emit_player_state_changed(new_state)

func get_state(peer_id: int = 1) -> State:
	return _get_state(peer_id)

func is_free(peer_id: int = 1) -> bool:
	return _get_state(peer_id) == State.FREE

func is_busy(peer_id: int = 1) -> bool:
	return _get_state(peer_id) == State.BUSY

func is_in_menu(peer_id: int = 1) -> bool:
	return _get_state(peer_id) == State.MENU

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _reset_inputs() -> void:
	if is_instance_valid(_bus):
		_bus.player().emit_input_reset_requested()

func _on_game_state_changed(game_state: int) -> void:
	# Systemweiter State-Wechsel betrifft alle lokalen Spieler.
	# In Tier 2/3 wird dies ggf. nur für den lokalen peer ausgelöst.
	if game_state != GameEnums.State.PLAYING:
		set_state(State.MENU)
	else:
		set_state(State.FREE)

func _state_name(s: State) -> String:
	var keys = State.keys()
	if s >= 0 and s < keys.size():
		return keys[s]
	return "UNKNOWN"
