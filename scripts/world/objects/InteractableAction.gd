class_name InteractableAction
extends RefCounted

var id: String
var label: String
var duration: float = 0.0
var xp_type: String = "none"
var xp_amount: int = 0
var inspect_text: String = ""
var on_complete: Callable

func _init(p_id: String, p_label: String) -> void:
    id = p_id
    label = p_label