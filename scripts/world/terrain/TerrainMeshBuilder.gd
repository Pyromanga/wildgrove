class_name TerrainMeshBuilder
extends RefCounted

## TerrainMeshBuilder — Baut Terrain-MeshInstance3D und Physics-Body aus einer Heightmap.
##
## Bekommt fertige Höhen (aus TerrainField, via TerrainChunkBuilder) — kennt selbst weder
## Noise noch Seed. Rein: Höhen rein, Mesh/Kollision raus.
##
## Verantwortung:
##   - Vertices, Normals, Colors, Indices assemblieren
##   - Normalen per Vertex berechnen (Durchschnitt anliegender Dreiecke)
##   - MeshInstance3D mit StandardMaterial3D zurückgeben
##   - StaticBody3D mit HeightMapShape3D zurückgeben
##
## Verwendet TerrainColorizer für Vertex-Farben.

const LOG_CAT := "TerrainMeshBuilder"

var _colorizer: TerrainColorizer

func _init() -> void:
	_colorizer = TerrainColorizer.new()

## Baut MeshInstance3D aus der Heightmap.
## biome_cb: Callable(world_x: float, world_z: float) -> Color (BiomeDefinition.
## terrain_color_grass des jeweiligen Bioms an dieser Weltposition, siehe
## TerrainChunkBuilder._biome_color()).
## water_heights (optional): LOKALER Wasserspiegel je Vertex, gleiches Layout wie `heights`
## (TerrainChunkBuilder.sample_water_levels()). Damit sind Flussbetten, die über dem Meeresspiegel
## liegen, trotzdem Gewässerboden und Ufer; ohne (leer) gilt überall `sea_level`.
## padded_heights (optional): Höhen mit EINEM Vertex Rand rundherum, (n+2)² Werte (siehe
## TerrainChunkBuilder.sample_heights_padded()). Damit werden die Normalen per zentraler Differenz
## über die Chunk-Grenze hinweg berechnet — Randvertices bekommen dieselbe Normale wie im
## Nachbar-Chunk. Ohne Rand schaut die Dreiecks-Mittelung nur auf den eigenen Chunk, und an
## steilen Berghängen sähe man Licht-/Farbnähte genau auf den Chunk-Grenzen.
func build_terrain_mesh(
	heights:      PackedFloat32Array,
	resolution:   int,
	size:         float,
	max_height:   float,
	sea_level:    float,
	world_offset: Vector2,
	biome_cb:     Callable,
	water_heights: PackedFloat32Array = PackedFloat32Array(),
	padded_heights: PackedFloat32Array = PackedFloat32Array()
) -> MeshInstance3D:
	var n    := resolution + 1
	var step := size / float(resolution)
	var half := size * 0.5

	var verts:   PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors:  PackedColorArray   = PackedColorArray()
	var indices: PackedInt32Array   = PackedInt32Array()
	# Biomfarbe je Vertex zwischenspeichern: die Färbung braucht die Normalen (Steigung), die erst
	# nach dem Dreiecks-Durchlauf feststehen — der Biom-Callback soll trotzdem nur einmal laufen.
	var biome_colors: PackedColorArray = PackedColorArray()

	for z_i in range(n):
		for x_i in range(n):
			var h:       float = heights[z_i * n + x_i]
			var vx:      float = x_i * step - half
			var vz:      float = z_i * step - half
			var world_x: float = world_offset.x + vx
			var world_z: float = world_offset.y + vz
			var biome:   Color = biome_cb.call(world_x, world_z) if biome_cb.is_valid() else _colorizer.COL_GRASS

			verts.append(Vector3(vx, h, vz))
			biome_colors.append(biome)
			normals.append(Vector3.UP)  # Placeholder, wird unten überschrieben

	for z_i in range(resolution):
		for x_i in range(resolution):
			var i00: int = z_i * n + x_i
			var i10: int = i00 + 1
			var i01: int = (z_i + 1) * n + x_i
			var i11: int = i01 + 1
			indices.append(i00); indices.append(i01); indices.append(i10)
			indices.append(i10); indices.append(i01); indices.append(i11)

	# Vertex-Normals: Durchschnitt der anliegenden Dreiecksnormalen
	var tri_normals: Array[Vector3] = []
	tri_normals.resize(verts.size())
	tri_normals.fill(Vector3.ZERO)

	for tri_i in range(0, indices.size(), 3):
		var a := indices[tri_i]; var b := indices[tri_i + 1]; var c := indices[tri_i + 2]
		var n_vec: Vector3 = (verts[b] - verts[a]).cross(verts[c] - verts[a]).normalized()
		tri_normals[a] += n_vec
		tri_normals[b] += n_vec
		tri_normals[c] += n_vec

	# BUGFIX (2026-09-20, "Boden rendert teilweise schwarz"): an Stellen mit
	# starken lokalen Höhensprüngen/Einschnitten (Flüsse, gegrabene Senken)
	# können sich die aufsummierten Dreiecksnormalen eines Vertex fast exakt
	# gegenseitig aufheben. tri_normals[i].normalized() liefert für einen
	# (nahezu) Nullvektor (0,0,0) zurück — ein Vertex ohne Normale erhält
	# dadurch nie Licht (Dot-Produkt immer 0) und erscheint komplett schwarz,
	# obwohl Mesh/Kollision an dieser Stelle völlig intakt sind (man kann
	# normal darüber laufen). Fallback auf Vector3.UP verhindert das.
	for i in range(verts.size()):
		var vertex_normal: Vector3 = tri_normals[i]
		normals[i] = vertex_normal.normalized() if vertex_normal.length_squared() > 0.0001 else Vector3.UP

	if padded_heights.size() == (n + 2) * (n + 2):
		var pn: int = n + 2
		for z_i in range(n):
			for x_i in range(n):
				var pi: int = (z_i + 1) * pn + (x_i + 1)
				var dx: float = (padded_heights[pi + 1] - padded_heights[pi - 1]) / (2.0 * step)
				var dz: float = (padded_heights[pi + pn] - padded_heights[pi - pn]) / (2.0 * step)
				normals[z_i * n + x_i] = Vector3(-dx, 1.0, -dz).normalized()

	# Vertex-Farben JETZT (mit Normalen): Steigung → Fels an Steilhängen, Schnee nur auf
	# flacheren Flächen, Wasserspiegel → Flussbett/Ufer. Siehe TerrainColorizer.terrain_color().
	var has_water: bool = water_heights.size() == heights.size()
	for z_i in range(n):
		for x_i in range(n):
			var i: int = z_i * n + x_i
			var wl: float = water_heights[i] if has_water else sea_level
			# Glatte, nahtlose Variation aus Weltkoordinaten (Chunk-Nähte bleiben unsichtbar).
			var jwx: float = world_offset.x + x_i * step - half
			var jwz: float = world_offset.y + z_i * step - half
			var jitter: float = sin(jwx * 0.031 + 1.7) * cos(jwz * 0.027 - 0.6)
			colors.append(_colorizer.terrain_color(heights[i], biome_colors[i], max_height, wl, normals[i].y, jitter))

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR]  = colors
	arr[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	# BUGFIX (2026-09-20, "Boden rendert je nach Blickrichtung/an Mulden schwarz"):
	# StandardMaterial3D mit CULL_DISABLED zeichnet zwar auch Backfaces (nötig,
	# falls die Kamera z.B. beim Fallen unters Mesh gerät), flippt aber NICHT
	# automatisch die Normale für die Rückseite. Schaut man von der Seite auf
	# ein Dreieck, für die man dessen Backface sieht (passiert v.a. an steilen
	# Mulden/Senken sowie je nach Kamerawinkel auch auf ebenen Flächen), zeigt
	# die Normale weiterhin "vorwärts" — also von der Kamera weg. Das Licht-
	# Skalarprodukt wird dadurch negativ, auf 0 geklemmt, und der Vertex wirkt
	# komplett schwarz, obwohl Mesh/Kollision intakt sind.
	# Fix: eigener Shader, der die Normale anhand des Fragment-Builtins
	# FRONT_FACING für Backfaces umkehrt, damit Beleuchtung von beiden Seiten
	# korrekt funktioniert.
	var shader := Shader.new()
	# Detail-Noise (2026-09-24, "Texturen"): das Terrain hatte bis hierhin nur
	# flache Vertex-Farbe (COLOR) — aus der Nähe komplett strukturlos. Statt
	# einer Bild-Textur (kein UV-Layout vorhanden, siehe Klassenkommentar)
	# moduliert der Fragment-Shader ALBEDO direkt mit Wert-Noise auf der
	# Welt-XZ-Position (zwei Frequenzen: grob = Flecken/Feuchtigkeitsschlieren,
	# fein = Sand-/Gras-Körnung) — "Textur" komplett aus Mathematik, kachelt
	# automatisch nahtlos (Noise ist eine reine Funktion von world_pos, keine
	# UV-Naht zwischen Chunks möglich). world_pos kommt aus dem Vertex-Shader
	# (MODEL_MATRIX * VERTEX), weil VERTEX selbst chunk-lokal ist (siehe
	# TerrainChunkBuilder-Kommentar "Kinder nutzen lokale Koordinaten").
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float roughness_val : hint_range(0.0, 1.0) = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Ganzzahliger Hash, exakt dasselbe Prinzip wie ProceduralTextureFactory._hash2()
// (GDScript) — hier als GLSL-Pendant, weil der Shader keine GDScript-Klassen
// aufrufen kann. Bewusst dieselbe Formel, damit Terrain-Grain und generierte
// Objekt-Texturen (Stein/Holz/...) optisch zur selben Familie gehören.
float grain_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float grain_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = grain_hash(i);
	float b = grain_hash(i + vec2(1.0, 0.0));
	float c = grain_hash(i + vec2(0.0, 1.0));
	float d = grain_hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	float coarse = grain_noise(world_pos.xz * 0.35) - 0.5;   // Flecken/Schlieren
	float fine   = grain_noise(world_pos.xz * 4.0)  - 0.5;   // Sand-/Gras-Körnung
	float detail = coarse * 0.10 + fine * 0.05;

	// Steilhaenge (Fels): horizontale Gesteinsschichten + groebere Kontraste statt glatter Flaeche.
	// Weltnormale aus der View-Space-NORMAL; Schichtung haengt an der Welt-Hoehe -> nahtlos ueber
	// Chunk-Grenzen, und die Baender laufen wie echte Strata waagerecht um den Berg.
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float steep = 1.0 - smoothstep(0.62, 0.90, abs(wn.y));
	float strata = grain_noise(vec2(world_pos.x * 0.04 + world_pos.z * 0.03, world_pos.y * 0.9)) - 0.5;
	float crack = grain_noise(world_pos.xz * 1.3 + vec2(world_pos.y * 0.7)) - 0.5;
	detail += steep * (strata * 0.34 + crack * 0.16);

	ALBEDO = clamp(COLOR.rgb * (1.0 + detail), 0.0, 1.0);
	ROUGHNESS = clamp(roughness_val + fine * 0.08, 0.0, 1.0);
	METALLIC = 0.0;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("roughness_val", 0.9)

	var mi := MeshInstance3D.new()
	mi.mesh              = mesh
	mi.material_override = mat
	mi.position.y        = 0.0
	return mi

## Baut StaticBody3D mit HeightMapShape3D aus der Heightmap.
func build_physics_body(
	heights:    PackedFloat32Array,
	resolution: int,
	size:       float
) -> StaticBody3D:
	var body  := StaticBody3D.new()
	var col   := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()

	shape.map_width = resolution + 1
	shape.map_depth = resolution + 1
	shape.map_data  = heights

	col.shape = shape
	body.add_child(col)

	# HeightMapShape3D: 1 Unit/Vertex → auf Weltgröße skalieren via StaticBody3D.scale
	var scale_xz: float = size / float(resolution)
	body.scale = Vector3(scale_xz, 1.0, scale_xz)
	return body
