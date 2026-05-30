extends Node3D
class_name InteractableObject

var label: String = "Interagieren"
var duration: float = 2.0
var xp_type: String = "none"
var xp_amount: int = 10

func _ready() -> void:
    add_to_group("interactable")
    _setup_visuals()
    
    var built = Kernel.builder.create(self)\
        .set_label(label)\
        .set_duration(duration)\
        .on_complete(_handle_completion)\
        .build()
    Logger.log_debug("Kinder nach build: " + str(get_children()), "InteractableObject")
    Logger.log_debug("InteractableObject: Child gebaut? " + str(built) + " | Label: " + label + " | Parent: " + name, "InteractableObject")

func start_interaction() -> void:
    for child in get_children():
        if child.has_method("start_interaction"):
            child.start_interaction()
            return

func _handle_completion() -> void:
    Kernel.events.player.emit_xp(xp_type, xp_amount)
    Kernel.inventory.add_item("log_normal", 3)
    _on_interaction_finished()
    queue_free()

func _setup_visuals() -> void:
    pass

func _on_interaction_finished() -> void:
    pass