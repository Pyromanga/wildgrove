class_name TerrainWaterBuilder
extends RefCounted

## TerrainWaterBuilder — Wasseroberfläche eines Chunks.
##
## Vorher: EINE flache PlaneMesh pro Chunk auf der globalen water_level-Höhe. Das sah beim
## Meer/See gut aus, aber für Flüsse falsch: TerrainField.get_water_level_at() liefert seit
## dem BUGFIX (2026-09-20, "Wasser/Flüsse & Seen sind alle auf einer Ebene") pro Punkt einen
## eigenen Wert (Flüsse folgen der lokalen Geländehöhe statt weltweit gleich zu sein) — eine
## einzelne flache Ebene könnte das nicht mehr darstellen, sobald sich der Wasserspiegel
## innerhalb eines Chunks ändert (z.B. Fluss verlässt eine Senke bergauf).
##
## Jetzt: ein Höhenfeld wie TerrainMeshBuilder, ein Vertex pro Geländevertex, y = lokaler
## Wasserspiegel an dieser Stelle. Trockene Vertices (Wasserspiegel <= Gelände) werden über
## Vertex-Alpha ausgeblendet, nicht weggelassen — dadurch bleibt das Gitter durchgehend
## (keine Löcher/Nähte) und Uferlinien blenden weich statt hart abzuschneiden.
##
## Kein Kollision: der Spieler geht durchs Wasser auf dem Grund, nicht darüber.
## SCHWIMMEN/WATEN/ANGELN: Diese Klasse ist nur Optik. Spielmechanik fragt
## TerrainField.get_water_depth_at()/is_water_at() — dieselbe Wahrheit wie die Optik.

## Ab dieser Tiefe volle Deckkraft (Alpha). Darunter blendet die Uferlinie weich aus statt
## hart abzuschneiden (vorher: reiner Tiefentest der flachen Ebene → z.T. harte Kante).
const FULL_OPACITY_DEPTH: float = 0.5
## Unterhalb dieser Tiefe entsteht gar kein Vertex-Wasser (verhindert Z-Fighting/Schimmern
## an Stellen, die nur hauchdünn unter dem Spiegel liegen).
const MIN_DEPTH: float = 0.05

const WATER_COLOR := Color(0.14, 0.42, 0.72, 0.62)

## Ab dieser Wassertiefe ist die Tiefenfärbung voll "tief" (dunkles Blau statt Türkis).
const DEEP_COLOR_DEPTH: float = 10.0

static var _shared_material: ShaderMaterial = null

## Ist irgendein Vertex des Chunks tief genug unter seinem (lokalen!) Wasserspiegel, dass
## eine Wasserfläche gebraucht wird?
func needs_surface(terrain_heights: PackedFloat32Array, water_heights: PackedFloat32Array) -> bool:
	for i in range(terrain_heights.size()):
		if water_heights[i] - terrain_heights[i] > MIN_DEPTH:
			return true
	return false

## Baut die Wasser-Oberfläche in lokalen Chunk-Koordinaten. `terrain_heights`/`water_heights`
## im selben Zeilen/Spalten-Layout wie TerrainMeshBuilder.build_terrain_mesh() erwartet
## (siehe TerrainChunkBuilder.sample_heights()).
func build_surface(
	terrain_heights: PackedFloat32Array,
	water_heights:   PackedFloat32Array,
	resolution:      int,
	chunk_size:      float
) -> MeshInstance3D:
	var n    := resolution + 1
	var step := chunk_size / float(resolution)
	var half := chunk_size * 0.5

	var verts:   PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors:  PackedColorArray   = PackedColorArray()
	var indices: PackedInt32Array   = PackedInt32Array()

	for z_i in range(n):
		for x_i in range(n):
			var i:     int   = z_i * n + x_i
			var vx:    float = x_i * step - half
			var vz:    float = z_i * step - half
			var depth: float = water_heights[i] - terrain_heights[i]
			# Vertex-Farbe trägt KEINE Wasserfarbe mehr, sondern Daten für den Shader:
			#   r = Tiefe 0..1 (Türkis flach → dunkelblau tief), a = Uferkante (0 am Ufer → 1).
			var edge: float = clampf(depth / FULL_OPACITY_DEPTH, 0.0, 1.0)
			var depth01: float = clampf(depth / DEEP_COLOR_DEPTH, 0.0, 1.0)

			verts.append(Vector3(vx, water_heights[i], vz))
			normals.append(_water_normal(terrain_heights, water_heights, n, step, x_i, z_i))
			colors.append(Color(depth01, 0.0, 0.0, edge * WATER_COLOR.a))

	for z_i in range(resolution):
		for x_i in range(resolution):
			var i00: int = z_i * n + x_i
			var i10: int = i00 + 1
			var i01: int = (z_i + 1) * n + x_i
			var i11: int = i01 + 1
			indices.append(i00); indices.append(i01); indices.append(i10)
			indices.append(i10); indices.append(i01); indices.append(i11)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR]  = colors
	arr[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	var mi := MeshInstance3D.new()
	mi.mesh              = mesh
	mi.material_override = _get_material()
	mi.cast_shadow        = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Normale der Wasserfläche aus dem Wasserspiegel-Feld (zentrale Differenzen). Nur NASSE Nachbarn
## zählen: sonst würde der Sprung zwischen Flusswasser (z.B. +12 m) und trockenem Nachbarn
## (globaler Spiegel 0 m) jede Uferkante eines Bergbachs wie einen Wasserfall aussehen lassen.
## Flach = (0,1,0); eine Wasserfall-Fläche (Spiegel springt um Meter auf ~2 m) = fast waagerecht.
## Der Shader nutzt sie nur für Fall-Schaum/Streifen (die Kräuselung bleibt Shader-Sache).
func _water_normal(
	terrain_heights: PackedFloat32Array, water_heights: PackedFloat32Array,
	n: int, step: float, x_i: int, z_i: int
) -> Vector3:
	var hc: float = water_heights[z_i * n + x_i]
	var xl: int = x_i - 1 if x_i > 0 and _is_wet(terrain_heights, water_heights, z_i * n + x_i - 1) else x_i
	var xr: int = x_i + 1 if x_i < n - 1 and _is_wet(terrain_heights, water_heights, z_i * n + x_i + 1) else x_i
	var zl: int = z_i - 1 if z_i > 0 and _is_wet(terrain_heights, water_heights, (z_i - 1) * n + x_i) else z_i
	var zr: int = z_i + 1 if z_i < n - 1 and _is_wet(terrain_heights, water_heights, (z_i + 1) * n + x_i) else z_i
	var dx: float = 0.0
	var dz: float = 0.0
	if xr != xl:
		dx = (water_heights[z_i * n + xr] - water_heights[z_i * n + xl]) / (float(xr - xl) * step)
	if zr != zl:
		dz = (water_heights[zr * n + x_i] - water_heights[zl * n + x_i]) / (float(zr - zl) * step)
	if hc != hc:  # NaN-Schutz
		return Vector3.UP
	return Vector3(-dx, 1.0, -dz).normalized()

func _is_wet(terrain_heights: PackedFloat32Array, water_heights: PackedFloat32Array, i: int) -> bool:
	return water_heights[i] - terrain_heights[i] > MIN_DEPTH

static func _get_material() -> ShaderMaterial:
	if _shared_material == null:
		var shader := Shader.new()
		# Gleicher Backface-Normal-Fix wie TerrainMeshBuilder (siehe BUGFIX 2026-09-20
		# dort): CULL_DISABLED (Kamera kann unter Wasser sein) flippt bei StandardMaterial3D
		# die Normale für Rückseiten nicht automatisch -> Beleuchtung von unten wäre falsch.
		#
		# Wellen/Schaum (2026-09-24, "Texturen"): vorher komplett flache, statische
		# Farbfläche. Jetzt: fbm-Noise auf Welt-XZ, mit TIME verschoben (=Wellen laufen),
		# moduliert Farbe (helle/dunkle Wellenbänder) + eine per Normal-Storung angenäherte
		# Kräuselung (zwei leicht versetzte Noise-Samples als Gradient) + Schaum-Schwelle
		# an Wellenkämmen UND an der ohnehin vorhandenen Ufer-Alpha-Kante (COLOR.a aus
		# TerrainWaterBuilder.build_surface() — flach am Ufer, tief in der Mitte: an der
		# Kante entsteht so echte Gischt statt eines harten Farbschnitts).
		shader.code = """
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

float water_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float water_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = water_hash(i);
	float b = water_hash(i + vec2(1.0, 0.0));
	float c = water_hash(i + vec2(0.0, 1.0));
	float d = water_hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float water_fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		total += water_noise(p) * amp;
		p *= 2.0;
		amp *= 0.5;
	}
	return total;
}

varying vec3 world_pos;
varying float steep_v;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = wp;
	// Wasserfall-Mass aus der Vertex-Normale (siehe TerrainWaterBuilder._water_normal()): 0 = eben.
	steep_v = 1.0 - clamp(NORMAL.y, 0.0, 1.0);
	// Meer/tiefer See: sanfte, langsame Dünung. Skaliert mit der Tiefe (COLOR.r) -> an Ufern und in
	// Flüssen null, daher nirgends Lücken zum Gelände. Nur von der Welt-Position abhängig -> nahtlos
	// über Chunk-Grenzen.
	float swell = water_fbm(wp.xz * 0.06 + vec2(TIME * 0.05, TIME * 0.035)) - 0.5;
	VERTEX.y += swell * 0.55 * smoothstep(0.15, 0.6, COLOR.r);
}

void fragment() {
	// COLOR.r = Wassertiefe 0..1, COLOR.a = Uferkante * Grunddeckkraft (siehe build_surface()).
	float depth01 = COLOR.r;
	float edge = clamp(COLOR.a / 0.62, 0.0, 1.0);

	// Zwei gegenläufig verschobene Wellenfelder -> weniger "Rolltreppen"-Look als eines.
	vec2 flow = world_pos.xz * 0.25 + vec2(TIME * 0.06, TIME * 0.04);
	vec2 flow2 = world_pos.xz * 0.11 - vec2(TIME * 0.035, -TIME * 0.05);
	float waves = water_fbm(flow) * 0.65 + water_fbm(flow2) * 0.35;

	float waves_dx = water_fbm(flow + vec2(0.35, 0.0)) * 0.65 + water_fbm(flow2 + vec2(0.35, 0.0)) * 0.35;
	float waves_dz = water_fbm(flow + vec2(0.0, 0.35)) * 0.65 + water_fbm(flow2 + vec2(0.0, 0.35)) * 0.35;
	vec3 ripple_normal = normalize(vec3((waves - waves_dx) * 2.5, 1.0, (waves - waves_dz) * 2.5));

	// Tiefenfarbe: flach = helles Tuerkis (Grund scheint durch), tief = dunkles Blau.
	vec3 shallow_col = vec3(0.28, 0.58, 0.64);
	vec3 deep_col = vec3(0.04, 0.19, 0.38);
	vec3 col = mix(shallow_col, deep_col, smoothstep(0.0, 1.0, depth01));
	col *= 1.0 + (waves - 0.5) * 0.18;

	// Schaum: an Wellenkaemmen UND an der Uferkante (edge klein -> Gischt).
	float crest_foam = smoothstep(0.74, 0.92, waves) * (0.35 + 0.65 * (1.0 - depth01));
	float shore_foam = 1.0 - smoothstep(0.0, 0.55, edge);
	float foam = clamp(crest_foam + shore_foam * 0.7, 0.0, 1.0);
	col = mix(col, vec3(0.92, 0.96, 0.98), foam * 0.55);

	// Fresnel: flacher Blick spiegelt mehr (Himmelston), steiler Blick sieht Wasser/Grund.
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	col = mix(col, vec3(0.55, 0.70, 0.82), fres * 0.35);

	// WASSERFALL: steile Wasserfläche -> weiss, mit nach unten laufenden Streifen. `fall` greift auch
	// die Nachbar-Vertices (Normalen aus Differenzen) -> Gischtkranz am Beckenrand.
	float fall = smoothstep(0.10, 0.40, steep_v);
	float streak = water_noise(vec2((world_pos.x + world_pos.z) * 2.3, world_pos.y * 0.8 + TIME * 3.5));
	col = mix(col, vec3(0.95, 0.98, 1.0), fall * (0.55 + 0.45 * streak));

	ALBEDO = col;
	// Flach: durchsichtiger (Grund sichtbar), tief: deckender.
	ALPHA = clamp(edge * mix(0.50, 0.88, smoothstep(0.0, 1.0, depth01)) + foam * 0.2 * edge + fall * 0.35 * edge, 0.0, 1.0);
	ROUGHNESS = clamp(0.05 + (1.0 - foam) * 0.05, 0.0, 1.0);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	NORMAL = FRONT_FACING ? ripple_normal : -ripple_normal;
}
"""
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_shared_material = mat
	return _shared_material
