extends Node
## Factory.gd — Erzeugt UI-Elemente für die 3D-Welt

static func create_3d_bar(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "ProgressBar"
	root.position.y = 2.5
	root.visible = false
	parent.add_child(root)
	
	var bg = MeshInstance3D.new()
	bg.mesh = QuadMesh.new(); bg.mesh.size = Vector2(1.2, 0.2)
	bg.material_override = _quick_mat(Color.BLACK)
	root.add_child(bg)
	
	var fill = MeshInstance3D.new()
	fill.name = "Fill"
	fill.mesh = QuadMesh.new(); fill.mesh.size = Vector2(1.1, 0.15)
	fill.material_override = _quick_mat(Color.YELLOW)
	fill.position.z = 0.01
	root.add_child(fill)
	return root

static func _quick_mat(c: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = StandardMaterial3D.BILLBOARD_ENABLED
	return m