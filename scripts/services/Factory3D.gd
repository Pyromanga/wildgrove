extends ServiceNode
class_name Factory3D

# --- Konstanten ---
const COLOR_TRUNK: Color  = Color(0.4, 0.25, 0.1)
const COLOR_LEAVES: Color = Color(0.1, 0.5, 0.1)
const COLOR_BAR_BG: Color = Color(0.0, 0.0, 0.0, 0.7)
const COLOR_BAR_HP: Color = Color(0.2, 0.8, 0.3)
extends ServiceNode
class_name MeinService

func init() -> void:
    super.init()
    
func create_simple_tree(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Tree_Root"
	
	var trunk: MeshInstance3D = _create_3d_shape(CylinderMesh.new(), COLOR_TRUNK, false)
	trunk.scale = Vector3(0.3, 1.5, 0.3)
	trunk.position.y = 0.75
	root.add_child(trunk)

	var leaves: MeshInstance3D = _create_3d_shape(SphereMesh.new(), COLOR_LEAVES, false)
	leaves.scale = Vector3(1.2, 1.2, 1.2)
	leaves.position.y = 1.8
	root.add_child(leaves)

	parent.add_child(root)
	return root

func create_3d_bar(parent: Node3D) -> Bar3D:
	var root: Bar3D = Bar3D.new()
	root.name = "UI_ProgressBar3D"
	root.position.y = 2.5
	root.visible = false

	var bg_mesh: QuadMesh = QuadMesh.new()
	bg_mesh.size = Vector2(1.2, 0.2)
	var bg: MeshInstance3D = _create_3d_shape(bg_mesh, COLOR_BAR_BG, true)
	root.add_child(bg)

	var fill_mesh: QuadMesh = QuadMesh.new()
	fill_mesh.size = Vector2(1.1, 0.15)
	var fill: MeshInstance3D = _create_3d_shape(fill_mesh, COLOR_BAR_HP, true)
	fill.name = "Fill"
	fill.position.z = 0.01
	root.add_child(fill)

	root.setup(fill)
	parent.add_child(root)
	return root

func _create_3d_shape(mesh: Mesh, color: Color, is_ui_element: bool) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	
	if is_ui_element:
		mat.billboard_mode = StandardMaterial3D.BILLBOARD_ENABLED
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.billboard_mode = StandardMaterial3D.BILLBOARD_DISABLED
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	
	mi.material_override = mat
	return mi

# --- Hilfsklasse ---

class Bar3D extends Node3D:
	var _fill: MeshInstance3D
	var _max_width: float = 1.1

	func setup(fill_node: MeshInstance3D) -> void:
		_fill = fill_node
		# Explizites Casting auf QuadMesh für den Compiler
		var q_mesh: QuadMesh = _fill.mesh as QuadMesh
		if q_mesh:
			_max_width = q_mesh.size.x

	func update(percent: float) -> void:
		# Hier lag vermutlich der Fehler: Explizite Typ-Zuweisung für p
		var p: float = clamp(percent, 0.0, 1.0)
		_fill.scale.x = p
		_fill.position.x = (p - 1.0) * (_max_width / 2.0)