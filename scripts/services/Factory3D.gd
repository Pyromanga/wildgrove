extends ServiceNode
class_name Factory3D

## Factory3D — Service zur programmatischen Erstellung von 3D-Hilfsobjekten.
## Abhängigkeiten (deps): ["data"] (Falls du später Item-Daten für Meshes brauchst)

const LOG_CAT := "Factory3D"

const COLOR_TRUNK: Color = Color(0.4, 0.25, 0.1)
const COLOR_LEAVES: Color = Color(0.1, 0.5, 0.1)
const COLOR_BAR_BG: Color = Color(0.0, 0.0, 0.0, 0.7)
const COLOR_BAR_HP: Color = Color(0.2, 0.8, 0.3)


# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(_deps: Dictionary) -> void:
	# Die Factory ist meist autark, könnte aber hier 'data' für
	# Mesh-Definitionen entgegennehmen.
	Logger.log_debug("Konfiguriert.", LOG_CAT)


# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────
func on_ready() -> void:
	Logger.log_info("Factory3D bereit.", LOG_CAT)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func create_simple_tree(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Tree_Root"

	var trunk := _create_3d_shape(CylinderMesh.new(), COLOR_TRUNK, false)
	trunk.scale = Vector3(0.3, 1.5, 0.3)
	trunk.position.y = 0.75
	root.add_child(trunk)

	var leaves := _create_3d_shape(SphereMesh.new(), COLOR_LEAVES, false)
	leaves.scale = Vector3(1.2, 1.2, 1.2)
	leaves.position.y = 1.8
	root.add_child(leaves)

	if parent:
		parent.add_child(root)
	return root


func create_3d_bar(parent: Node3D) -> Bar3D:
	# Wir nutzen hier die innere Klasse
	var bar_node := Bar3D.new()
	bar_node.name = "UI_ProgressBar3D"
	bar_node.position.y = 2.5
	bar_node.visible = false

	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(1.2, 0.2)
	var bg := _create_3d_shape(bg_mesh, COLOR_BAR_BG, true)
	bar_node.add_child(bg)

	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(1.1, 0.15)
	var fill := _create_3d_shape(fill_mesh, COLOR_BAR_HP, true)
	fill.name = "Fill"
	fill.position.z = 0.01
	bar_node.add_child(fill)

	bar_node.setup(fill)

	if parent:
		parent.add_child(bar_node)
	return bar_node


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _create_3d_shape(mesh: Mesh, color: Color, is_ui_element: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
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


# ─────────────────────────────────────────────
# Hilfsklassen
# ─────────────────────────────────────────────


class Bar3D:
	extends Node3D
	var _fill: MeshInstance3D
	var _max_width: float = 1.1

	func setup(fill_node: MeshInstance3D) -> void:
		_fill = fill_node
		var q_mesh := _fill.mesh as QuadMesh
		if q_mesh:
			_max_width = q_mesh.size.x

	func update(percent: float) -> void:
		if not is_instance_valid(_fill):
			return

		var p: float = clamp(percent, 0.0, 1.0)
		_fill.scale.x = p
		# Korrektur für die Ausrichtung: Damit der Balken von links schrumpft
		_fill.position.x = (p - 1.0) * (_max_width / 2.0)
