extends ServiceNode
class_name InteractionBuilder

## InteractionBuilder — Verwaltet den zeitlichen Ablauf von Interaktionen.
## Muss ServiceNode sein (nicht Service) weil create_tween() einen Node braucht.

signal interaction_started(label: String, duration: float)
signal interaction_completed(label: String)
signal interaction_cancelled(label: String)

const LOG_CAT := "Builder"

var _active_action: InteractableAction = null
var _active_tween:  Tween              = null

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	super._ready()

func init() -> void:
	super.init()

func on_ready() -> void:
	super.on_ready()
	if Kernel.events and Kernel.events.player:
		Kernel.events.player.movement_interrupted.connect(cancel_interaction)
		Logger.log_info("Builder bereit.", LOG_CAT)
	else:
		Logger.log_warn("Events nicht verfügbar — movement_interrupted nicht verbunden.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func execute_action(action: InteractableAction) -> void:
	if not Kernel.states or not Kernel.states.is_free():
		Logger.log_debug("Abbruch: Spieler nicht frei.", LOG_CAT)
		return
	if _active_action != null:
		Logger.log_debug("Abbruch: Aktion bereits aktiv.", LOG_CAT)
		return

	Logger.log_info("Starte: '%s' (%.1fs)" % [action.label, action.duration], LOG_CAT)
	_active_action = action
	Kernel.states.set_state(PlayerStateService.PlayerState.BUSY)
	interaction_started.emit(action.label, action.duration)

	_active_tween = create_tween()
	_active_tween.tween_method(func(_v: float): pass, 0.0, 1.0, action.duration)
	_active_tween.finished.connect(_on_tween_finished)

func cancel_interaction() -> void:
	if _active_action == null:
		return
	var label := _active_action.label
	_cleanup()
	Logger.log_info("Abgebrochen: '%s'" % label, LOG_CAT)
	interaction_cancelled.emit(label)
	if Kernel.states:
		Kernel.states.set_state(PlayerStateService.PlayerState.FREE)

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

	Logger.log_info("Abgeschlossen: '%s'" % completed.label, LOG_CAT)
	interaction_completed.emit(completed.label)

	if completed.on_complete.is_valid():
		completed.on_complete.call()

	if Kernel.states:
		Kernel.states.set_state(PlayerStateService.PlayerState.FREE)

func _cleanup() -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	_active_action = null