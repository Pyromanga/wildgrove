extends InteractableObject

func _init() -> void:
	# Werte setzen, bevor _ready() läuft
	label = "Eiche fällen"
	duration = 3.5
	xp_type = "woodcutting"
	xp_amount = 25

func _setup_visuals() -> void:
	var trunk = MeshInstance3D.new()
	trunk.mesh = CylinderMesh.new()
	add_child(trunk)