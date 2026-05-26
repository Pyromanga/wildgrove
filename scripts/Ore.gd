extends Node3D

func _ready():
	# Visuelles (Einfacher grauer Block)
	var m = MeshInstance3D.new()
	m.mesh = BoxMesh.new()
	add_child(m)

	# Interaktion 'bestellen'
	Builder.create(self)\
		.set_label("Eisenerz abbauen")\
		.set_duration(4.0)\
		.on_complete(func(): 
			GameEvents.emit_xp("mining", 40)
			queue_free()
		).build()