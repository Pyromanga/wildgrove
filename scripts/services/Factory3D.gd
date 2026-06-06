class_name Factory3D
extends RefCounted

## Factory3D — Programmatische Erzeugung von 3D-Hilfsobjekten.
##
## REFACTOR (Session 4): Kein ServiceNode mehr.
##   VORHER: extends ServiceNode — lief durch die komplette 8-phasige Boot-Pipeline,
##           hatte eine ghost "data"-Dependency, belegte einen Registrierungsslot.
##   NACHHER: Normale RefCounted-Klasse. Wird einmal in WorldService instantiiert
##            und als öffentliche Variable `factory3d` exponiert.
##
## Zugriff für Entities/Components: Services.world.factory3d
##   (WorldService ist sowieso die Voraussetzung für 3D-Entities)
##
## Bar3D extends Node3D (muss im Tree leben für Tweens) — deshalb kein pure static.

const LOG_CAT := "Factory3D"

const COLOR_TRUNK: Color  = Color(0.40, 0.25, 0.10)
const COLOR_LEAVES: Color = Color(0.10, 0.50, 0.10)
const COLOR_BAR_BG: Color = Color(0.00, 0.00, 0.00, 0.70)
const COLOR_BAR_HP: Color = Color(0.20, 0.80, 0.30)


func create_simple_tree(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Tree_Root"

	var trunk := _create_3d_shape(CylinderMesh.new(), COLOR_TRUNK, false)
	trunk.scale    = Vector3(0.3, 1.5, 0.3)
	trunk.position = Vector3(0.0, 0.75, 0.0)
	root.add_child(trunk)

	var leaves := _create_3d_shape(SphereMesh.new(), COLOR_LEAVES, false)
	leaves.scale    = Vector3(1.2, 1.2, 1.2)
	leaves.position = Vector3(0.0, 1.8, 0.0)
	root.add_child(leaves)

	if parent:
		parent.add_child(root)
	return root


func create_3d_bar(parent: Node3D) -> Bar3D:
	var bar_node := Bar3D.new()
	bar_node.name      = "UI_ProgressBar3D"
	bar_node.position  = Vector3(0.0, 2.5, 0.0)
	bar_node.visible   = false

	var bg_mesh      := QuadMesh.new()
	bg_mesh.size      = Vector2(1.2, 0.2)
	var bg            := _create_3d_shape(bg_mesh, COLOR_BAR_BG, true)
	bar_node.add_child(bg)

	var fill_mesh    := QuadMesh.new()
	fill_mesh.size    = Vector2(1.1, 0.15)
	var fill          := _create_3d_shape(fill_mesh, COLOR_BAR_HP, true)
	fill.name         = "Fill"
	fill.position.z   = 0.01
	bar_node.add_child(fill)

	bar_node.setup(fill)

	if parent:
		parent.add_child(bar_node)
	return bar_node


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _create_3d_shape(mesh: Mesh, color: Color, is_ui_element: bool) -> MeshInstance3D:
	var mi  := MeshInstance3D.new()
	mi.mesh  = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = color
	mat.transparency  = StandardMaterial3D.TRANSPARENCY_ALPHA

	if is_ui_element:
		mat.billboard_mode = StandardMaterial3D.BILLBOARD_ENABLED
		mat.shading_mode   = StandardMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.billboard_mode = StandardMaterial3D.BILLBOARD_DISABLED
		mat.shading_mode   = StandardMaterial3D.SHADING_MODE_PER_PIXEL

	mi.material_override = mat
	return mi


# ─────────────────────────────────────────────
# Hilfsklassen
# ─────────────────────────────────────────────


class Bar3D extends Node3D:
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
		_fill.scale.x    = p
		_fill.position.x = (p - 1.0) * (_max_width / 2.0)
