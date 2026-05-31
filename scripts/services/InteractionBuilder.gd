extends ServiceBase
class_name InteractionBuilder

signal interaction_started(label: String, duration: float)
signal interaction_completed(label: String)
signal interaction_cancelled(label: String)

var _active_action: InteractableAction = null
var _active_tween: Tween = null

func execute_action(action: InteractableAction) -> void:
    if not Kernel.states.is_free():
        Logger.log_debug("Abbruch: Spieler BUSY", "Builder")
        return
    if _active_action != null:
        Logger.log_debug("Abbruch: Aktion bereits aktiv", "Builder")
        return

    Logger.log_debug("Starte: " + action.label, "Builder")
    _active_action = action
    Kernel.states.set_state(Kernel.states.PlayerState.BUSY)
    interaction_started.emit(action.label, action.duration)

    # Tween auf einem stabilen Node (dem Service selbst)
    _active_tween = create_tween()
    # Dummy-Property tweenen — wir brauchen nur das finished-Signal
    var _progress := [0.0]
    _active_tween.tween_method(func(v: float): _progress[0] = v, 0.0, 1.0, action.duration)
    _active_tween.finished.connect(_on_tween_finished)

func _on_tween_finished() -> void:
    if _active_action == null:
        return  # wurde gecancelt während tween lief

    var completed_action := _active_action
    _cleanup()

    Logger.log_debug("Abgeschlossen: " + completed_action.label, "Builder")
    interaction_completed.emit(completed_action.label)

    if completed_action.on_complete.is_valid():
        completed_action.on_complete.call()

    Kernel.states.set_state(Kernel.states.PlayerState.FREE)

func cancel_interaction() -> void:
    if _active_action == null:
        return
    Logger.log_debug("Abgebrochen: " + _active_action.label, "Builder")
    var cancelled_label := _active_action.label
    _cleanup()
    interaction_cancelled.emit(cancelled_label)
    Kernel.states.set_state(Kernel.states.PlayerState.FREE)

func _cleanup() -> void:
    if _active_tween:
        _active_tween.kill()
        _active_tween = null
    _active_action = null

func is_busy() -> bool:
    return _active_action != null
    
func _ready() -> void:
    super()  # ServiceBase.register
    Kernel.events.player.movement_interrupted.connect(cancel_interaction)