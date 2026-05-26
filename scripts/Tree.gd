extends Node3D

func _ready() -> void:
	# 1. Aussehen (Stamm)
	var trunk = MeshInstance3D.new()
	trunk.mesh = CylinderMesh.new()
	add_child(trunk)
	
	# 2. Verhalten mit dem Builder 'bestellen'
	Builder.create(self)\
		.set_label("Eiche fällen")\
		.set_duration(3.5)\
		.on_complete(_on_felled)\
		.build()

func _on_felled() -> void:
	GameEvents.emit_xp("woodcutting", 25)
	queue_free() # Baum weg