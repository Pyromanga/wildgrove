extends Node3D
## OakTree.gd — Fällbarer Baum im World.

func _ready() -> void:
	if Kernel.factory3d:
		Kernel.factory3d.create_simple_tree(self)
	else:
		Logger.log_error("Factory3D nicht verfügbar — Baum ohne Grafik.", "OakTree")

	var d := InteractableData.new()
	d.id        = "chop"
	d.label     = "Eiche fällen"
	d.duration  = 3.0
	d.xp_type   = "woodcutting"
	d.xp_amount = 25
	d.drops     = {"log_normal": 3}

	var comp := InteractableComponent.new()
	comp.data = d
	add_child(comp)

func _on_interacted(action_id: String) -> void:
	if action_id == "chop":
		queue_free()