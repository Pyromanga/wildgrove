extends ServiceBase
class_name Factory3D

## Factory3D — Erschafft visuelle Objekte im 3D-Raum
## Bietet Methoden für echtes 3D (Bäume) und Billboard-UI (Bars)

# --- Konstanten für das Styling ---
const COLOR_TRUNK  := Color(0.4, 0.25, 0.1)  # Braun
const COLOR_LEAVES := Color(0.1, 0.5, 0.1)   # Grün
const COLOR_BAR_BG := Color(0.0, 0.0, 0.0, 0.7)
const COLOR_BAR_HP := Color(0.2, 0.8, 0.3)

# ─────────────────────────────────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────────────────────────────────

## Erstellt einen einfachen 3D-Baum (Zylinder + Kugel) ohne Billboard-Effekt.
func create_simple_tree(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Tree_Root"
	
	# Stamm (Echtes 3D)
	var trunk = _create_3d_shape(CylinderMesh.new(), COLOR_TRUNK, false)
	trunk.scale = Vector3(0.3, 1.5, 0.3)
	trunk.position.y = 0.75
	root.add_child(trunk)

	# Krone (Echtes 3D)
	var leaves = _create_3d_shape(SphereMesh.new(), COLOR_LEAVES, false)
	leaves.scale = Vector3(1.2, 1.2, 1.2)
	leaves.position.y = 1.8
	root.add_child(leaves)

	parent.add_child(root)
	Logger.log_debug("3D-Baum instanziiert für " + parent.name, "Factory3D")
	return root

## Erstellt eine 3D-Fortschrittsanzeige, die immer zur Kamera schaut.
func create_3d_bar(parent: Node3D) -> Bar3D:
	var root = Bar3D.new()
	root.name = "UI_ProgressBar3D"
	root.position.y = 2.5
	root.visible = false # Standardmäßig unsichtbar

	# Hintergrund (Billboard!)
	var bg_mesh = QuadMesh.new()
	bg_mesh.size = Vector2(1.2, 0.2)
	var bg = _create_3d_shape(bg_mesh, COLOR_BAR_BG, true)
	root.add_child(bg)

	# Füllung (Billboard!)
	var fill_mesh = QuadMesh.new()
	fill_mesh.size = Vector2(1.1, 0.15)
	var fill = _create_3d_shape(fill_mesh, COLOR_BAR_HP, true)
	fill.name = "Fill"
	fill.position.z = 0.01 # Leicht davor, um Z-Fighting zu verhindern
	root.add_child(fill)

	root.setup(fill)
	parent.add_child(root)
	return root

# ─────────────────────────────────────────────────────────────────────────
# Interne Hilfsmethoden
# ─────────────────────────────────────────────────────────────────────────

## Universelle Methode zur Erzeugung von Meshes mit Material-Steuerung.
func _create_3d_shape(mesh: Mesh, color: Color, is_ui_element: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	
	if is_ui_element:
		# UI-Settings: Schaut zur Kamera, ignoriert Licht (leuchtet selbst)
		mat.billboard_mode = StandardMaterial3D.BILLBOARD_ENABLED
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.fixed_size = true # Optional: Bar bleibt gleich groß, egal wie weit weg
	else:
		# Welt-Settings: Steht fest im Raum, reagiert auf Licht/Schatten
		mat.billboard_mode = StandardMaterial3D.BILLBOARD_DISABLED
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	
	mi.material_override = mat
	return mi

# ─────────────────────────────────────────────────────────────────────────
# Hilfsklasse für die 3D-Bar
# ─────────────────────────────────────────────────────────────────────────

class Bar3D extends Node3D:
	var _fill: MeshInstance3D
	var _max_width: float = 1.1

	func setup(fill_node: MeshInstance3D) -> void:
		_fill = fill_node
		if _fill.mesh is QuadMesh:
			_max_width = _fill.mesh.size.x

	func update(percent: float) -> void:
		var p := clamp(percent, 0.0, 1.0)
		_fill.scale.x = p
		# Verschiebung nach links, damit die Bar von links nach rechts schrumpft
		_fill.position.x = (p - 1.0) * (_max_width / 2.0)