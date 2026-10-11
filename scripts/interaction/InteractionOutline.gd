class_name InteractionOutline
extends RefCounted

## InteractionOutline — Umrandungs-Highlight für ein angetipptes Interactable
## (Baum, Erz, NPC, Tier, Bauteil — irgendetwas in der Gruppe "interactable").
##
## Technik: klassischer "Inverted Hull" — pro MeshInstance3D des Ziels wird ein
## Klon als Kind derselben MeshInstance3D angehängt (folgt Transform/Position
## automatisch, kein eigenes _process() nötig), dessen Shader die Vertices
## entlang ihrer Normalen nach außen schiebt und nur die Rückseiten rendert
## (cull_front) — die Original-Vorderseite verdeckt die Innenseite der Hülle,
## übrig bleibt ein sichtbarer Rand. Funktioniert für JEDES Mesh ohne
## Sonderfall pro Entity-Typ — Voraussetzung für "gilt für so ziemlich alles,
## was man interagieren kann" (siehe InteractionTargetPicker-Klassenkommentar).
##
## Kein eigener Node — reines RefCounted, das seine erzeugten Kind-Nodes selbst
## aufräumt (destroy()). Ein InteractionTargetPicker hält jeweils höchstens
## eine Instanz (das aktuell angetippte Ziel).

const OUTLINE_WIDTH: float = 0.035
const OUTLINE_COLOR: Color = Color(1.0, 0.92, 0.35, 1.0)  # warmes Gelb, gut sichtbar auf Grün/Braun

static var _shared_shader: Shader = null

var _target: Node3D = null
var _clones: Array[MeshInstance3D] = []

func _init(target: Node3D) -> void:
	_target = target
	for mi in _find_mesh_instances(target):
		_clones.append(_build_outline_clone(mi))

## Muss aufgerufen werden, sobald das Highlight nicht mehr gebraucht wird
## (Ziel gewechselt/abgewählt, oder Ziel despawnt) — entfernt alle Klone.
func destroy() -> void:
	for clone in _clones:
		if is_instance_valid(clone):
			clone.queue_free()
	_clones.clear()
	_target = null

## true wenn das umrandete Ziel noch im Baum lebt — InteractionTargetPicker
## räumt sonst selbst über destroy() auf (z.B. wenn der Baum gerade abgeerntet wird).
func is_target_valid() -> bool:
	return is_instance_valid(_target)

func get_target() -> Node3D:
	return _target

# ─────────────────────────────────────────────
# Aufbau
# ─────────────────────────────────────────────

func _find_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, found)
	return found

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and not (node as MeshInstance3D).name.begins_with("__outline__"):
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

func _build_outline_clone(source: MeshInstance3D) -> MeshInstance3D:
	var clone := MeshInstance3D.new()
	clone.name = "__outline__%s" % source.name
	clone.mesh = source.mesh
	clone.skeleton = source.skeleton
	clone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clone.material_override = _get_shared_material()
	# Identity-Transform relativ zum Original — als dessen Kind bewegt/dreht/
	# skaliert es sich automatisch mit, ohne eigenen _process()-Tick.
	clone.transform = Transform3D.IDENTITY
	source.add_child(clone)
	return clone

func _get_shared_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _get_shared_shader()
	mat.set_shader_parameter("outline_width", OUTLINE_WIDTH)
	mat.set_shader_parameter("outline_color", OUTLINE_COLOR)
	return mat

func _get_shared_shader() -> Shader:
	if _shared_shader == null:
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_always, skip_vertex_transform;

uniform float outline_width = 0.035;
uniform vec4 outline_color : source_color = vec4(1.0, 0.92, 0.35, 1.0);

void vertex() {
	vec3 offset_normal = normalize(NORMAL) * outline_width;
	VERTEX = (MODEL_MATRIX * vec4(VERTEX + offset_normal, 1.0)).xyz;
	NORMAL = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	VERTEX = (VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
"""
		_shared_shader = shader
	return _shared_shader
