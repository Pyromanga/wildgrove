extends ServiceNode
class_name InteractionBuilder

## InteractionBuilder — Verwaltet den zeitlichen Ablauf von Interaktionen.
## Muss ServiceNode sein, um Tweens für Progress-Bars zu verwalten.

signal interaction_started(label: String, duration: float)
signal interaction_completed(label: String)
signal interaction_cancelled(label: String)

const LOG_CAT := "Builder"

var _active_action: InteractableAction = null
var _active_tween:  Tween              = null

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	# Keine harten deps nötig, da er nur auf Events reagiert
	Logger.log_debug("Initialisiert.", LOG_CAT)

func on_ready() -> void:
	# EventBus statt Kernel.events
	EventBus.player.movement_interrupted.connect(cancel_interaction)
	Logger.log_info("InteractionBuilder bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func execute_action(action: InteractableAction) -> void:
	# Nutzt den neuen PlayerStateService
	if not Services.player_states.is_free():
		Logger.log_debug("Abbruch: Spieler ist gerade beschäftigt.", LOG_CAT)
		return
		
	if _active_action != null:
		return

	Logger.log_info("Starte: '%s' (%.1fs)" % [action.label, action.duration], LOG_CAT)
	
	_active_action = action
	Services.player_states.set_state(PlayerStateService.State.BUSY)
	
	interaction_started.emit(action.label, action.duration)

	_active_tween = create_tween()
	# Der Tween selbst tut nichts, außer die Zeit zu messen
	_active_tween.tween_interval(action.duration)
	_active_tween.finished.connect(_on_tween_finished)

func cancel_interaction() -> void:
	if _active_action == null:
		return
		
	var label := _active_action.label
	_cleanup()
	
	Logger.log_info("Abgebrochen: '%s'" % label, LOG_CAT)
	interaction_cancelled.emit(label)
	Services.player_states.set_state(PlayerStateService.State.FREE)

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

	# Führt das Callback aus (z.B. _handle_completion in der InteractableComponent)
	if completed.on_complete.is_valid():
		completed.on_complete.call()

	Services.player_states.set_state(PlayerStateService.State.FREE)

func _cleanup() -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	_active_action = null