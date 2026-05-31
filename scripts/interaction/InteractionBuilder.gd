extends ServiceBase
class_name InteractionBuilder

## Der InteractionBuilder verwaltet den zeitlichen Ablauf von Aktionen.
## Er kümmert sich um den Player-Status (BUSY) und den Fortschritts-Tween.

signal interaction_started(label: String, duration: float)
signal interaction_completed(label: String)
signal interaction_cancelled(label: String)

var _active_action: InteractableAction = null
var _active_tween: Tween = null

func _ready() -> void:
	super() # Registriert den Service im Kernel
	
	# Bricht Interaktion ab, wenn der Spieler sich bewegt
	if Kernel.events and Kernel.events.player:
		Kernel.events.player.movement_interrupted.connect(cancel_interaction)

## Startet eine Aktion (wird von der InteractableComponent aufgerufen)
func execute_action(action: InteractableAction) -> void:
	if not Kernel.states.is_free():
		Logger.log_debug("Abbruch: Spieler BUSY", "Builder")
		return
	if _active_action != null:
		Logger.log_debug("Abbruch: Aktion bereits aktiv", "Builder")
		return

	Logger.log_debug("Starte: " + action.label, "Builder")
	_active_action = action
	
	# Spieler sperren
	Kernel.states.set_state(Kernel.states.PlayerState.BUSY)
	interaction_started.emit(action.label, action.duration)

	# Fortschritts-Timer starten
	_active_tween = create_tween()
	_active_tween.tween_method(func(_v: float): pass, 0.0, 1.0, action.duration)
	_active_tween.finished.connect(_on_tween_finished)

func _on_tween_finished() -> void:
	if _active_action == null:
		return

	var completed_action: InteractableAction = _active_action
	_cleanup()

	Logger.log_debug("Abgeschlossen: " + completed_action.label, "Builder")
	interaction_completed.emit(completed_action.label)

	# Callback am Ende ausführen (gibt XP, Drops etc.)
	if completed_action.on_complete.is_valid():
		completed_action.on_complete.call()

	# Spieler wieder freigeben
	Kernel.states.set_state(Kernel.states.PlayerState.FREE)

func cancel_interaction() -> void:
	if _active_action == null:
		return
	var label_str: String = _active_action.label
	Logger.log_debug("Abgebrochen: " + label_str, "Builder")
	_cleanup()
	interaction_cancelled.emit(label_str)
	Kernel.states.set_state(Kernel.states.PlayerState.FREE)

func _cleanup() -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	_active_action = null

func is_busy() -> bool:
	return _active_action != null