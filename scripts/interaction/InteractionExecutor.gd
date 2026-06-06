extends ServiceNode
class_name InteractionExecutor

## InteractionExecutor — verwaltet den zeitlichen Ablauf von Interaktionen.
##
## Umbenannt von "InteractionBuilder" (alter Dateiname: InteractionBuilder.gd) — der Begriff "Builder" impliziert ein
## Erzeugungsmuster (GoF Builder), was hier falsch ist. Dieser Service
## FÜHRT Aktionen AUS, er baut keine Objekte.
##
## Früher hatte dieser Service eigene Signale (interaction_started, etc.) die
## WorldEvents dupliziert haben. Jetzt emittiert er ausschließlich über
## EventBus.world — eine einzige Signalquelle für alle Interaktions-Events.

const LOG_CAT := "InteractionExecutor"

## Abhängigkeiten via DI
var _player_states: PlayerStateService

var _active_action: InteractableAction = null
var _active_tween: Tween = null


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
	EventBus.player.movement_interrupted.connect(cancel_interaction)
	Logger.log_info("InteractionExecutor bereit.", LOG_CAT)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func execute_action(action: InteractableAction) -> void:
	if not _player_states or not _player_states.is_free():
		Logger.log_debug("Abbruch: Spieler ist beschäftigt oder Service fehlt.", LOG_CAT)
		return

	if _active_action != null:
		return

	Logger.log_info("Starte: '%s' / id='%s' (%.1fs)" % [action.label, action.id, action.duration], LOG_CAT)
	_active_action = action

	_player_states.set_state(PlayerStateService.State.BUSY)

	EventBus.world.emit_interaction_started(action.id, action.label, action.duration)

	_active_tween = create_tween()
	_active_tween.tween_interval(action.duration)
	_active_tween.finished.connect(_on_tween_finished)


func cancel_interaction() -> void:
	if _active_action == null:
		return

	var action_id := _active_action.id
	var label     := _active_action.label
	_cleanup()

	Logger.log_info("Abgebrochen: '%s' / id='%s'" % [label, action_id], LOG_CAT)
	EventBus.world.emit_interaction_cancelled(action_id, label)

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

	Logger.log_info("Erfolgreich: '%s' / id='%s'" % [completed.label, completed.id], LOG_CAT)
	EventBus.world.emit_interaction_finished(completed.id, completed.label)

	if completed.on_complete.is_valid():
		completed.on_complete.call()

	if _player_states:
		_player_states.set_state(PlayerStateService.State.FREE)


func _cleanup() -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	_active_action = null
