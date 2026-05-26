extends Node

# Erzeugt einen Fortschrittsbalken im 3D Raum
func create_3d_bar(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "ProgressBar"
	root.position.y = 2.5
	root.visible = false
	parent.add_child(root)
	
	var bg = _create_mesh(Vector2(1.2, 0.2), Color.BLACK)
	root.add_child(bg)
	
	var fill = _create_mesh(Vector2(1.1, 0.15), Color.YELLOW)
	fill.name = "Fill"
	fill.position.z = 0.01
	root.add_child(fill)
	return root

func _create_mesh(size: Vector2, color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	mi.mesh.size = size
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = StandardMaterial3D.BILLBOARD_ENABLED
	mi.material_override = mat
	return mi