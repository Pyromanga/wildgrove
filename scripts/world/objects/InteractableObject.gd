extends Node3D
class_name InteractableObject

var actions: Array[InteractableAction] = []
var default_action_id: String = ""

func _ready() -> void:
    add_to_group("interactable")
    _setup_visuals()
    _register_actions()

    for action in actions:
        action.on_complete = func(): _handle_completion(action)

    var built = Kernel.builder.build_interactable(self)
    Logger.log_debug("Kinder nach build: " + str(get_children()), "InteractableObject")
    Logger.log_debug("InteractableObject: gebaut | Default: " + default_action_id + " | Parent: " + name, "InteractableObject")

func get_default_action() -> InteractableAction:
    for a in actions:
        if a.id == default_action_id:
            return a
    if actions.size() > 0:
        return actions[0]
    return null

func get_action(id: String) -> InteractableAction:
    for a in actions:
        if a.id == id:
            return a
    return null

func _handle_completion(action: InteractableAction) -> void:
    if action.xp_type != "none" and action.xp_amount > 0:
        Kernel.events.player.emit_xp(action.xp_type, action.xp_amount)
    if action.inspect_text != "":
        Kernel.ui_factory.show_popup(action.inspect_text)
    if action.id != "inspect":
        Kernel.inventory.add_item("log_normal", 3)
    _on_action_finished(action)
    if action.id != "inspect":
        queue_free()

func _setup_visuals() -> void:
    pass

func _register_actions() -> void:
    pass

func _on_action_finished(_action: InteractableAction) -> void:
    pass