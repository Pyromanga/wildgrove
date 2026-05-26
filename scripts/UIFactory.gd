extends Node
## UIFactory.gd — Erstellt standardisierte UI-Elemente

static func create_3d_progress_bar(parent: Node3D, offset: Vector3 = Vector2(0, 2.5, 0)) -> Node3D:
	var root = Node3D.new()
	root.name = "ProgressBar"
	root.position = offset
	root.visible = false
	parent.add_child(root)
	
	# Hintergrund
	var bg = MeshInstance3D.new()
	var bg_m = QuadMesh.new(); bg_m.size = Vector2(1.2, 0.2)
	bg.mesh = bg_m
	var mat_bg = StandardMaterial3D.new()
	mat_bg.albedo_color = Color.BLACK
	mat_bg.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	bg.material_override = mat_bg
	root.add_child(bg)
	
	# Füllung
	var fill = MeshInstance3D.new()
	fill.name = "Fill"
	var fill_m = QuadMesh.new(); fill_m.size = Vector2(1.1, 0.15)
	fill.mesh = fill_m
	var mat_fill = StandardMaterial3D.new()
	mat_fill.albedo_color = Color.YELLOW
	mat_fill.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	fill.material_override = mat_fill
	fill.position.z = 0.01
	root.add_child(fill)
	
	return root