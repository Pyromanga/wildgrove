# InteractableData.gd
extends Resource
class_name InteractableData

@export var id: String = "object"
@export var label: String = "Interagieren"
@export var duration: float = 1.5
@export var xp_type: String = "none"
@export var xp_amount: int = 10
@export var drops: Dictionary = {}  # { "item_id": quantity }
@export var inspect_text: String = ""
