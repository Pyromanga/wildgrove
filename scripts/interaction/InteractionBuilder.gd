extends ServiceNode
class_name InteractionBuilder

## InteractionBuilder — Verwaltet den zeitlichen Ablauf von Interaktionen.

signal interaction_started(label: String, duration: float)
signal interaction_completed(label: String)
signal interaction_cancelled(label: String)

const LOG_CAT := "Builder"

# Abhängigkeiten via DI
var _player_states: PlayerStateService

var _active_action: InteractableAction = null
var _active_tween:  Tween              = null

# ─────────────────────────────────────────────
# Phase 4: Configure (Enterprise DI)
# ─────────────────────────────────────────────
func configure(deps: Dictionary) -> void:
	_player_states = deps.get("playerstates") as PlayerStateService
	Logger.log_debug("Konfiguriert mit PlayerStates.", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────
func on_ready() -> void:
	# EventBus ist Infrastruktur und darf global genutzt werden
	EventBus.player.movement_interrupted.connect(cancel_interaction)
	Logger.log_info("InteractionBuilder bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func execute_action(action: InteractableAction) -> void:
	# Check gegen die injizierte Referenz statt Services.player_states
	if not _player_states or not _player_states.is_free():
		Logger.log_debug("Abbruch: Spieler ist beschäftigt oder Service fehlt.", LOG_CAT)
		return
		
	if _active_action != null:
		return
		
	Logger.log_info("Starte: '%s' (%.1fs)" % [action.label, action.duration], LOG_CAT)
	_active_action = action
	
	_player_states.set_state(PlayerStateService.State.BUSY)
	interaction_started.emit(action.label, action.duration)
	
	# Tween-Management
	_active_tween = create_tween()
	_active_tween.tween_interval(action.duration)
	_active_tween.finished.connect(_on_tween_finished)

func cancel_interaction() -> void:
	if _active_action == null:
		return
		
	var label := _active_action.label
	_cleanup()
	
	Logger.log_info("Abgebrochen: '%s'" % label, LOG_CAT)
	interaction_cancelled.emit(label)
	
	if _player_states:
		_player_states.set_state(PlayerStateService.State.FREE)

func is_busy() -> bool:
	return _active_action != null

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _on_tween_finished() -> void:
	if _active_action == null:
		return
		
	var completed := _active_action
	_cleanup()
	
	Logger.log_info("Erfolgreich: '%s'" % completed.label, LOG_CAT)
	interaction_completed.emit(completed.label)
	
	# Callback-Sicherheit
	if completed.on_complete.is_valid():
		completed.on_complete.call()
		
	if _player_states:
		_player_states.set_state(PlayerStateService.State.FREE)

func _cleanup() -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	_active_action = null