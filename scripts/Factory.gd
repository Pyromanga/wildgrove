extends Node
## Factory.gd — Erzeugt standardisierte Elemente

static func create_3d_bar(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "ProgressBar"
	root.position.y = 2.5
	root.visible = false
	parent.add_child(root)
	
	# Hintergrund (QuadMesh)
	var bg = MeshInstance3D.new()
	bg.mesh = QuadMesh.new(); bg.mesh.size = Vector2(1.2, 0.2)
	bg.material_override = _get_unshaded_mat(Color.BLACK)
	root.add_child(bg)
	
	# Füllung
	var fill = MeshInstance3D.new()
	fill.name = "Fill"
	fill.mesh = QuadMesh.new(); fill.mesh.size = Vector2(1.1, 0.15)
	fill.material_override = _get_unshaded_mat(Color.YELLOW)
	fill.position.z = 0.01
	root.add_child(fill)
	return root

static func _get_unshaded_mat(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	return m