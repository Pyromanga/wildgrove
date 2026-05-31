extends ServiceBase
class_name Factory3D

## Factory3D — Erschafft visuelle Objekte im 3D-Raum

# Eigene Klasse statt Meta-Callable — typsicher und autocomplete-fähig
class Bar3D extends Node3D:
    var _fill: MeshInstance3D

    func setup(fill: MeshInstance3D) -> void:
        _fill = fill

    func update(percent: float) -> void:
        var p := clamp(percent, 0.0, 1.0)
        _fill.scale.x = p
        _fill.position.x = (p - 1.0) * (1.1 / 2.0)

func create_3d_bar(parent: Node3D) -> Bar3D:
    var root := Bar3D.new()
    root.name = "ProgressBar3D"
    root.position.y = 2.5
    root.visible = false

    var bg := _create_3d_shape(QuadMesh.new(), Color.BLACK)
    bg.mesh.size = Vector2(1.2, 0.2)
    root.add_child(bg)

    var fill := _create_3d_shape(QuadMesh.new(), Color.YELLOW)
    fill.mesh.size = Vector2(1.1, 0.15)
    fill.name = "Fill"
    fill.position.z = 0.01
    root.add_child(fill)

    root.setup(fill)
    parent.add_child(root)
    Logger.log_debug("3D-Bar erstellt für: " + parent.name, "Factory3D")
    return root

const TREE_TRUNK_COLOR  := Color(0.4, 0.25, 0.1)
const TREE_LEAVES_COLOR := Color(0.1, 0.5,  0.1)

func create_simple_tree(parent: Node3D) -> Node3D:
    var root := Node3D.new()
    root.name = "Tree"

    var trunk := _create_3d_shape(CylinderMesh.new(), TREE_TRUNK_COLOR)
    trunk.scale = Vector3(0.3, 1.5, 0.3)
    trunk.position.y = 0.75
    root.add_child(trunk)

    var leaves := _create_3d_shape(SphereMesh.new(), TREE_LEAVES_COLOR)
    leaves.scale = Vector3(1.2, 1.2, 1.2)
    leaves.position.y = 1.8
    root.add_child(leaves)

    parent.add_child(root)
    return root  # konsistent: immer zurückgeben

func _create_3d_shape(mesh: Mesh, color: Color) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
    mat.billboard_mode = StandardMaterial3D.BILLBOARD_ENABLED
    mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
    mi.material_override = mat
    return mi