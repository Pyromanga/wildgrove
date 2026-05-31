extends Node3D
class_name InteractableObject

var actions: Array[InteractableAction] = []
var default_action_id: String = ""
var detection_radius: float = 2.0  # für Interactable nutzbar

func _ready() -> void:
    add_to_group("interactable")
    _setup_visuals()
    _register_actions()
    for action in actions:
        action.on_complete = func(): _handle_completion(action)
    Kernel.builder.build_interactable(self)

func get_default_action() -> InteractableAction:
    for a in actions:
        if a.id == default_action_id:
            return a
    return actions[0] if actions.size() > 0 else null

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
    # Drops kommen von der Action selbst, nicht hardcoded
    for item_id in action.drops:
        Kernel.inventory.add_item(item_id, action.drops[item_id])
    _on_action_finished(action)

# --- Override-Hooks für Subklassen ---
func _setup_visuals() -> void:
    pass

func _register_actions() -> void:
    pass

func _on_action_finished(_action: InteractableAction) -> void:
    pass  # Subklasse entscheidet ob queue_free(), respawn, etc.