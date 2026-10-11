class_name TerrainEditGhost
extends Node3D

## TerrainEditGhost — Vorschau-Scheibe für Graben/Füllen (siehe GroundToolController).
##
## Analog zu BuildGhost (Bau-Vorschau im Baumodus): eine flache, halbtransparente Scheibe auf
## dem Boden. Ihr Alpha-Verlauf bildet EXAKT TerrainEditLayer.falloff() nach (ebener Kern bis
## core_radius, danach Kosinus-Abfall bis outer_radius) — der Geist zeigt also nicht nur WO
## gegraben/aufgeschüttet würde, sondern auch WIE VIEL an jedem Punkt bewirkt wird. Ein heller
## Rand nahe outer_radius markiert die Außengrenze, im selben Stil wie InteractionOutline
## (Umrandungs-Highlight beim Antippen).
##
## Farbe zeigt Modus (erdig-orange = Graben, kühles Blau = Füllen) UND Gültigkeit (rot =
## blockiert, z.B. "building_nearby") — dieselbe State-Idee wie BuildGhost.State, nur mit fest
## zwei Modi statt einem generischen NO_MATERIALS-Zustand (Vorschau prüft kein Inventar).
##
## Kein eigenes _process() — GroundToolController schreibt Position/Zustand jeden Frame direkt
## über apply_state(), analog BuildModeController → BuildGhost.

enum Mode { DIG, FILL, PLANE }

const COL_PLANE_OK     := Color(0.25, 0.85, 0.55, 0.50)
const COL_PLANE_RIM    := Color(0.60, 1.00, 0.80, 0.90)

const COL_DIG_OK      := Color(0.85, 0.52, 0.16, 0.50)
const COL_DIG_RIM      := Color(1.00, 0.75, 0.30, 0.90)
const COL_FILL_OK      := Color(0.30, 0.70, 0.95, 0.50)
const COL_FILL_RIM     := Color(0.55, 0.90, 1.00, 0.90)
const COL_BLOCKED      := Color(0.95, 0.22, 0.22, 0.45)
const COL_BLOCKED_RIM  := Color(1.00, 0.35, 0.35, 0.90)

static var _shared_shader: Shader = null

var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _mode: int = Mode.DIG

func _init() -> void:
	name = "TerrainEditGhost"
	_mesh = MeshInstance3D.new()
	_mesh.name = "GhostDisc"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false

## radius/core_radius: siehe WorldTerrainEditor.BRUSH_RADIUS/CORE_RADIUS — dieselben Werte,
## die der echte Pinsel benutzt, damit der Geist nie eine andere Fläche zeigt als das Ergebnis.
func configure(radius: float, core_radius: float, mode: int) -> void:
	_mode = mode
	var plane := PlaneMesh.new()
	# PlaneMesh liegt per Default in der XZ-Ebene (Normale +Y) — genau die Ausrichtung, die ein
	# Boden-Decal braucht, ohne zusätzliche Rotation.
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	_mesh.mesh = plane
	_material = ShaderMaterial.new()
	_material.shader = _get_shared_shader()
	_material.set_shader_parameter("core_radius", core_radius)
	_material.set_shader_parameter("outer_radius", radius)

	_mesh.material_override = _material

## Position (Bodenhöhe am Pinselmittelpunkt, siehe GroundToolController._update_one_preview())
## und Gültigkeit (siehe WorldService.preview_terrain_edit()) — schaltet auch die Farbe um.
func apply_state(pos: Vector3, ok: bool) -> void:
	global_position = pos
	var fill_col: Color = COL_BLOCKED
	var rim_col: Color = COL_BLOCKED_RIM
	if ok:
		match _mode:
			Mode.DIG:
				fill_col = COL_DIG_OK
				rim_col = COL_DIG_RIM
			Mode.FILL:
				fill_col = COL_FILL_OK
				rim_col = COL_FILL_RIM
			_:
				fill_col = COL_PLANE_OK
				rim_col = COL_PLANE_RIM
	_material.set_shader_parameter("fill_color", fill_col)
	_material.set_shader_parameter("rim_color", rim_col)

func _get_shared_shader() -> Shader:
	if _shared_shader == null:
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform float core_radius = 2.9;
uniform float outer_radius = 5.0;
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 0.5);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float dist = length(centered) * outer_radius;
	if (dist > outer_radius) {
		discard;
	}
	// Identische Kurve wie TerrainEditLayer.falloff(): 1.0 im Kern, dann Kosinus-Abfall zum Rand —
	// die Alpha-Stärke an jedem Punkt entspricht damit 1:1 der Wirkung, die der echte Pinsel dort hätte.
	float weight;
	if (dist <= core_radius) {
		weight = 1.0;
	} else {
		weight = 0.5 * (1.0 + cos(PI * (dist - core_radius) / max(outer_radius - core_radius, 0.001)));
	}
	float rim = smoothstep(outer_radius - 0.18, outer_radius - 0.02, dist);
	ALBEDO = mix(fill_color.rgb, rim_color.rgb, rim);
	ALPHA = mix(fill_color.a * weight, rim_color.a, rim);
}
"""
		_shared_shader = shader
	return _shared_shader
