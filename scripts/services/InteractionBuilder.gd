extends ServiceBase
class_name InteractionBuilder

var _active_tween: Tween = null
var _active_bar: ProgressBar = null
var _cancel_cooldown: bool = false

func build_interactable(target: InteractableObject) -> Node3D:
    var node := Node3D.new()
    node.set_script(load("res://scripts/world/objects/Interactable.gd"))
    node.set_meta("target", target)
    target.add_child(node)
    return node

func execute_action(action: InteractableAction) -> void:
    if not Kernel.states.is_free():
        Logger.log_debug("ABBRUCH: Spieler bereits BUSY", "Builder")
        return
    if _cancel_cooldown:
        Logger.log_debug("ABBRUCH: Cancel-Cooldown aktiv", "Builder")
        return

    Logger.log_debug("START execute_action: " + action.label, "Builder")
    Kernel.states.set_state(Kernel.states.PlayerState.BUSY)

    var hud_nodes = get_tree().get_nodes_in_group("hud")
    var hud_root: Node = hud_nodes[0] if hud_nodes.size() > 0 else get_tree().root

    var bar: ProgressBar = Kernel.ui_factory.create_progress_bar(250.0)
    bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    hud_root.add_child(bar)
    _active_bar = bar

    var tween: Tween = bar.create_tween()
    _active_tween = tween
    tween.tween_property(bar, "value", 100.0, action.duration).from(0.0)
    await tween.finished

    _active_tween = null
    _active_bar = null

    if Kernel.states.is_free():
        Logger.log_debug("Interaktion wurde abgebrochen", "Builder")
        return

    bar.queue_free()

    if action.on_complete.is_valid():
        Logger.log_debug("Rufe Callback auf: " + action.label, "Builder")
        action.on_complete.call()

    Kernel.states.set_state(Kernel.states.PlayerState.FREE)
    Logger.log_debug("Aktion beendet, Spieler FREE", "Builder")

func cancel_interaction() -> void:
    if Kernel.states.is_free():
        return
    Logger.log_debug("Interaktion abgebrochen!", "Builder")
    if _active_tween:
        _active_tween.kill()
        _active_tween = null
    if _active_bar:
        _active_bar.queue_free()
        _active_bar = null
    _cancel_cooldown = true
    Kernel.states.set_state(Kernel.states.PlayerState.FREE)
    get_tree().create_timer(0.5).timeout.connect(func(): _cancel_cooldown = false)

func is_interactable(node: Node) -> bool:
    return node.is_in_group("interactable")