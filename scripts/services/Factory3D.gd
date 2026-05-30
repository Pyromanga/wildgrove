extends ServiceBase
class_name Factory3D
## Factory.gd — Erschafft visuelle Hilfsmittel im 3D-Raum

## Erzeugt einen Fortschrittsbalken im 3D-Raum
func create_3d_bar(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "ProgressBar"
	root.position.y = 2.5  # Über dem Objekt
	root.visible = false
	parent.add_child(root)
	
	# Hintergrund (schwarz)
	var bg = _create_mesh(Vector2(1.2, 0.2), Color.BLACK)
	root.add_child(bg)
	
	# Füllung (Gelb/Grün)
	var fill = _create_mesh(Vector2(1.1, 0.15), Color.YELLOW)
	fill.name = "Fill"
	fill.position.z = 0.01  # Leicht vor den Hintergrund
	root.add_child(fill)
	
	# Update-Funktion als Meta-Daten anhängen (wird vom Builder genutzt)
	root.set_meta("update_bar", func(percent: float):
		fill.scale.x = clamp(percent, 0.0, 1.0)
		fill.position.x = (fill.scale.x - 1.0) * (1.1 / 2.0)
	)
	
	return root

func _create_mesh(size: Vector2, color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	mi.mesh.size = size
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = StandardMaterial3D.BILLBOARD_ENABLED
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	
	mi.material_override = mat
	return mi
	
# In Factory3D.gd hinzufügen
func create_simple_tree(parent: Node3D) -> void:
    # Stamm
    var trunk = _create_3d_shape(CylinderMesh.new(), Color(0.4, 0.25, 0.1)) # Braun
    trunk.scale = Vector3(0.3, 1.5, 0.3)
    trunk.position.y = 0.75
    parent.add_child(trunk)
    
    # Krone
    var leaves = _create_3d_shape(SphereMesh.new(), Color(0.1, 0.5, 0.1)) # Grün
    leaves.scale = Vector3(1.2, 1.2, 1.2)
    leaves.position.y = 1.8
    parent.add_child(leaves)

func _create_3d_shape(mesh: Mesh, color: Color) -> MeshInstance3D:
    var mi = MeshInstance3D.new()
    mi.mesh = mesh
    var mat = StandardMaterial3D.new()
    mat.albedo_color = color
    mi.material_override = mat
    return mi