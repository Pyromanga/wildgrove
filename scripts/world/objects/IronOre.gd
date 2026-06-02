extends Node3D
## IronOre.gd — Abbaubarer Erzblock.

func _ready() -> void:
	_setup_visuals()

	var d := InteractableData.new()
	d.id        = "mine_iron"
	d.label     = "Eisenerz abbauen"
	d.duration  = 4.0
	d.xp_type   = "mining"
	d.xp_amount = 40
	d.drops     = {"iron_ore": 1}

	var comp := InteractableComponent.new()
	comp.data = d
	add_child(comp)

func _setup_visuals() -> void:
	var m   := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	m.mesh   = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.5, 0.4)
	m.material_override = mat
	add_child(m)

func _on_interacted(action_id: String) -> void:
	if action_id == "mine_iron":
		queue_free()