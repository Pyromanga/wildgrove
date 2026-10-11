class_name ChunkVegetationBuilder
extends RefCounted

## ChunkVegetationBuilder — Gras und Büsche als Deko pro Chunk (Wunsch 2026-10-05: "keine
## Büsche, kein Gras").
##
## Warum KEINE Entities: ein Chunk braucht hunderte Grasbüschel. Als Node3D mit
## InteractableComponent wäre das unbezahlbar. Hier: pro Chunk höchstens zwei MultiMeshInstance3D
## ("Grass", "Bushes") — jeweils EIN Draw-Call, keine Kollision, keine Interaktion. Sie hängen
## als Kinder am Chunk-Node und verschwinden mit ihm.
##
## DETERMINISMUS: gleicher (world_seed, coord) → gleiche Positionen. Rein optisch, muss zwischen
## Peers aber nicht synchron sein; ist es trotzdem.
##
## PERFORMANCE: Höhen kommen aus dem vom TerrainChunkBuilder ohnehin berechneten Höhenraster
## (bilinear), nicht aus TerrainField.get_height_at() pro Büschel. Biom/Bodenmaterial werden nur
## auf einem groben 8-m-Raster (64 Zellen/Chunk) abgefragt. visibility_range blendet ferne
## Chunks komplett aus.
##
## Gras wiegt sich im Wind (eigener kleiner Shader, Pivot-Phase über Weltposition wie
## MeshCache._build_sway_shader). Büsche sind statisch.

const NODE_GRASS: String = "Grass"
const NODE_BUSHES: String = "Bushes"
const NODE_FLOWERS: String = "Flowers"
## Größe einer Biom-Zelle in Metern (chunk_size muss ein Vielfaches sein, sonst Rest-Streifen
## ohne Vegetation — bei 64 m / 8 m = 8×8 Zellen exakt).
const CELL: float = 8.0
const MAX_GRASS_SLOPE_DEG: float = 36.0
const MAX_BUSH_SLOPE_DEG: float = 30.0
## Abstand zur Wasserlinie, ab dem etwas wächst.
const WATER_MARGIN: float = 0.25
const GRASS_VISIBLE_RANGE: float = 90.0
const BUSH_VISIBLE_RANGE: float = 150.0
const FLOWER_VISIBLE_RANGE: float = 80.0
## Blumen wachsen in Farbflecken: Anzahl Flecken pro Chunk und Streuung (σ in m) um das Zentrum.
const FLOWER_PATCHES: int = 4
const FLOWER_PATCH_SPREAD: float = 3.6
## Anteil der Blumen eines Flecks, der verstreut (statt im Fleck) wächst.
const FLOWER_STRAY_SHARE: float = 0.15
## Ab dieser Höhe (wie ChunkEntitySpawner.TREELINE) wächst nichts mehr.
const VEGETATION_LINE: float = 46.0
const SEED_SALT: int = 0x6E4A55

static var _tuft_mesh: ArrayMesh = null
static var _bush_mesh: ArrayMesh = null
static var _grass_material: ShaderMaterial = null
static var _flower_mesh: ArrayMesh = null
static var _flower_material: ShaderMaterial = null
static var _bush_material: StandardMaterial3D = null

var _field: TerrainField
var _base_seed: int

func _init(field: TerrainField, base_seed: int) -> void:
	_field = field
	_base_seed = base_seed

## Baut (bzw. ersetzt) Gras, Blumen und Büsche für den Chunk.
## heights/water_levels: (res+1)² Werte, Zeile für Zeile — siehe TerrainChunkBuilder.build().
## exclusions: Array[Vector3] (x = Welt-X, y = Welt-Z, z = Radius) — dauerhaft frei (Gebäude).
## cut_zones: dito, aber gemähte Kreise (Sense): Gras UND Blumen fehlen dort, Büsche bleiben.
## fresh_cut: ein NEUER Mähkreis (z <= 0 = keiner). Was darin wegfiele, wird gezählt und
## zurückgegeben ({"grass": n, "flowers": m}) — Grundlage für den Ertrag. Der Aufrufer nimmt
## ihn danach in cut_zones auf.
##
## WICHTIG (Determinismus): ALLE Zufallswerte eines Büschels werden VOR den Prüfungen gezogen.
## Sonst verschöbe jede Ablehnung (Zone, Wasser) die Positionen aller folgenden Büschel, und
## beim Neubau nach einem Mähen/Graben würde die ganze Wiese neu "gewürfelt".
func build(
	coord: Vector2i, chunk_node: Node3D, center: Vector2,
	heights: PackedFloat32Array, water_levels: PackedFloat32Array, res: int, chunk_size: float,
	exclusions: Array = [], cut_zones: Array = [], fresh_cut: Vector3 = Vector3(0.0, 0.0, -1.0)
) -> Dictionary:
	var stats: Dictionary = {"grass": 0, "flowers": 0}
	clear(chunk_node)
	if res <= 0 or heights.size() != (res + 1) * (res + 1):
		return stats

	var rng := RandomNumberGenerator.new()
	rng.seed = _base_seed ^ (coord.x * 1000003) ^ (coord.y * 999983) ^ SEED_SALT

	var cells: int = maxi(1, roundi(chunk_size / CELL))
	var cell_size: float = chunk_size / float(cells)
	var half: float = chunk_size * 0.5
	var edit: TerrainEditLayer = _field.get_edit_layer()

	# Pass 0: Biom + "natürlicher Boden?" je Zelle (64 Abfragen statt eine pro Büschel).
	var cell_biome: Array[BiomeDefinition] = []
	for cz in range(cells):
		for cx in range(cells):
			var wx_c: float = center.x - half + (float(cx) + 0.5) * cell_size
			var wz_c: float = center.y - half + (float(cz) + 0.5) * cell_size
			var biome: BiomeDefinition = _field.get_biome_at(wx_c, wz_c)
			var usable: bool = is_instance_valid(biome)
			# Nur natürlicher Boden: abgelegtes Material (Sand/Kies), Kies-Unterboden oder
			# umgegrabene/aufgeschüttete Zellen bleiben kahl.
			if usable and _field.get_material_at(wx_c, wz_c) != biome.surface_material:
				usable = false
			if usable and edit != null and absf(edit.get_delta_at(wx_c, wz_c)) > 0.05:
				usable = false
			cell_biome.append(biome if usable else null)

	var grass_tf: Array[Transform3D] = []
	var grass_data: Array[Color] = []
	var bush_tf: Array[Transform3D] = []
	var bush_col: Array[Color] = []
	var flower_tf: Array[Transform3D] = []
	var flower_col: Array[Color] = []

	# Pass 1: Gras + Büsche, zellenweise.
	for cz in range(cells):
		for cx in range(cells):
			var biome: BiomeDefinition = cell_biome[cz * cells + cx]
			if biome == null:
				continue
			if biome.grass_per_chunk <= 0 and biome.bush_per_chunk <= 0:
				continue
			var lx0: float = -half + float(cx) * cell_size
			var lz0: float = -half + float(cz) * cell_size
			var per_cell_grass: float = float(biome.grass_per_chunk) / float(cells * cells)
			var per_cell_bush: float = float(biome.bush_per_chunk) / float(cells * cells)
			var n_grass: int = int(per_cell_grass) + (1 if rng.randf() < fmod(per_cell_grass, 1.0) else 0)
			var n_bush: int = int(per_cell_bush) + (1 if rng.randf() < fmod(per_cell_bush, 1.0) else 0)
			var tip: Color = biome.grass_color_tip
			var ratio: float = clampf(biome.grass_color_base.get_luminance() / maxf(tip.get_luminance(), 0.01), 0.2, 1.0)

			for _i in range(n_grass):
				# Alles ziehen, DANN prüfen (siehe Kommentar an build()).
				var lx: float = lx0 + rng.randf() * cell_size
				var lz: float = lz0 + rng.randf() * cell_size
				var s: float = rng.randf_range(0.7, 1.5)
				var hs: float = rng.randf_range(0.8, 1.4)
				var yaw: float = rng.randf() * TAU
				var v: float = rng.randf_range(0.82, 1.18)
				var info: Vector2 = _sample(heights, res, chunk_size, lx, lz)
				if info.x >= VEGETATION_LINE or info.y > MAX_GRASS_SLOPE_DEG:
					continue
				if not _dry_and_free(info, water_levels, res, chunk_size, lx, lz, center, exclusions, 0.0):
					continue
				if _in_circles(center.x + lx, center.y + lz, cut_zones):
					continue
				if _in_circle(center.x + lx, center.y + lz, fresh_cut):
					stats["grass"] += 1
					continue
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s * hs, s))
				grass_tf.append(Transform3D(basis, Vector3(lx, info.x - 0.03, lz)))
				grass_data.append(Color(tip.r * v, tip.g * v, tip.b * v, ratio))

			for _j in range(n_bush):
				var bx: float = lx0 + rng.randf() * cell_size
				var bz: float = lz0 + rng.randf() * cell_size
				var bs: float = rng.randf_range(0.8, 1.7)
				var bh: float = rng.randf_range(0.8, 1.2)
				var byaw: float = rng.randf() * TAU
				var bv: float = rng.randf_range(0.8, 1.2)
				var binfo: Vector2 = _sample(heights, res, chunk_size, bx, bz)
				if binfo.x >= VEGETATION_LINE - 8.0 or binfo.y > MAX_BUSH_SLOPE_DEG:
					continue
				if not _dry_and_free(binfo, water_levels, res, chunk_size, bx, bz, center, exclusions, 0.6):
					continue
				var bbasis := Basis(Vector3.UP, byaw).scaled(Vector3(bs, bs * bh, bs))
				bush_tf.append(Transform3D(bbasis, Vector3(bx, binfo.x - 0.05, bz)))
				var bc: Color = biome.bush_color
				bush_col.append(Color(bc.r * bv, bc.g * bv, bc.b * bv, 1.0))

	# Pass 2: Blumen in Farbflecken. Flecken-Zentren werden immer gewürfelt (stabiler RNG-Strom).
	for _p in range(FLOWER_PATCHES):
		var px: float = rng.randf_range(-half, half)
		var pz: float = rng.randf_range(-half, half)
		var color_pick: float = rng.randf()
		var count_roll: float = rng.randf()
		var pcx: int = clampi(int((px + half) / cell_size), 0, cells - 1)
		var pcz: int = clampi(int((pz + half) / cell_size), 0, cells - 1)
		var pbiome: BiomeDefinition = cell_biome[pcz * cells + pcx]
		if pbiome == null or pbiome.flower_per_chunk <= 0 or pbiome.flower_colors.is_empty():
			continue
		var base_color: Color = pbiome.flower_colors[mini(int(color_pick * pbiome.flower_colors.size()), pbiome.flower_colors.size() - 1)]
		var n_flowers: int = roundi(float(pbiome.flower_per_chunk) / float(FLOWER_PATCHES) * (0.6 + 0.8 * count_roll))
		for _f in range(n_flowers):
			var stray: bool = rng.randf() < FLOWER_STRAY_SHARE
			var fx: float = clampf(rng.randf_range(-half, half) if stray else px + rng.randfn(0.0, FLOWER_PATCH_SPREAD), -half + 0.1, half - 0.1)
			var fz: float = clampf(rng.randf_range(-half, half) if stray else pz + rng.randfn(0.0, FLOWER_PATCH_SPREAD), -half + 0.1, half - 0.1)
			var fs: float = rng.randf_range(0.8, 1.3)
			var fyaw: float = rng.randf() * TAU
			var fv: float = rng.randf_range(0.88, 1.1)
			var fcx: int = clampi(int((fx + half) / cell_size), 0, cells - 1)
			var fcz: int = clampi(int((fz + half) / cell_size), 0, cells - 1)
			var fbiome: BiomeDefinition = cell_biome[fcz * cells + fcx]
			if fbiome == null or fbiome.flower_per_chunk <= 0:
				continue
			var finfo: Vector2 = _sample(heights, res, chunk_size, fx, fz)
			if finfo.x >= VEGETATION_LINE - 4.0 or finfo.y > MAX_GRASS_SLOPE_DEG:
				continue
			if not _dry_and_free(finfo, water_levels, res, chunk_size, fx, fz, center, exclusions, 0.1):
				continue
			if _in_circles(center.x + fx, center.y + fz, cut_zones):
				continue
			if _in_circle(center.x + fx, center.y + fz, fresh_cut):
				stats["flowers"] += 1
				continue
			var fbasis := Basis(Vector3.UP, fyaw).scaled(Vector3(fs, fs, fs))
			flower_tf.append(Transform3D(fbasis, Vector3(fx, finfo.x - 0.03, fz)))
			flower_col.append(Color(base_color.r * fv, base_color.g * fv, base_color.b * fv, 1.0))

	if not grass_tf.is_empty():
		chunk_node.add_child(_make_grass_node(grass_tf, grass_data))
	if not flower_tf.is_empty():
		chunk_node.add_child(_make_flower_node(flower_tf, flower_col))
	if not bush_tf.is_empty():
		chunk_node.add_child(_make_bush_node(bush_tf, bush_col))
	return stats

static func _in_circle(wx: float, wz: float, circle: Vector3) -> bool:
	if circle.z <= 0.0:
		return false
	var dx: float = wx - circle.x
	var dz: float = wz - circle.y
	return dx * dx + dz * dz < circle.z * circle.z

static func _in_circles(wx: float, wz: float, circles: Array) -> bool:
	for c: Variant in circles:
		if _in_circle(wx, wz, c as Vector3):
			return true
	return false

## Entfernt vorhandene Vegetations-Nodes (vor Neubau nach Geländeänderung).
func clear(chunk_node: Node3D) -> void:
	for node_name in [NODE_GRASS, NODE_FLOWERS, NODE_BUSHES]:
		var old: Node = chunk_node.get_node_or_null(node_name)
		if old != null:
			chunk_node.remove_child(old)  # Name sofort frei, sonst würde der Neubau umbenannt
			old.queue_free()

# ─────────────────────────────────────────────
# Platzierungsregeln
# ─────────────────────────────────────────────

func _dry_and_free(
	info: Vector2, water_levels: PackedFloat32Array, res: int, chunk_size: float,
	lx: float, lz: float, center: Vector2, exclusions: Array, extra_clearance: float
) -> bool:
	var water: float = _sample(water_levels, res, chunk_size, lx, lz).x
	if info.x <= water + WATER_MARGIN + extra_clearance:
		return false
	var wx: float = center.x + lx
	var wz: float = center.y + lz
	for zone: Variant in exclusions:
		var z: Vector3 = zone
		var dx: float = wx - z.x
		var dz: float = wz - z.y
		if dx * dx + dz * dz < z.z * z.z:
			return false
	# Straßen, Gassen und Dorfgrundstücke (Siedlungen) bleiben frei von Gras/Blumen/Büschen.
	if _field.get_settlements().blocks_vegetation(wx, wz, 0.4 + extra_clearance):
		return false
	return true

## Bilinear (Wert, Steigung in Grad) aus einem (res+1)²-Raster an lokaler Position (lx, lz)
## relativ zur Chunk-Mitte. Für das Wasserraster ist nur .x relevant.
static func _sample(grid: PackedFloat32Array, res: int, chunk_size: float, lx: float, lz: float) -> Vector2:
	var n: int = res + 1
	var step: float = chunk_size / float(res)
	var gx: float = clampf((lx + chunk_size * 0.5) / step, 0.0, float(res) - 0.0001)
	var gz: float = clampf((lz + chunk_size * 0.5) / step, 0.0, float(res) - 0.0001)
	var ix: int = int(gx)
	var iz: int = int(gz)
	var fx: float = gx - float(ix)
	var fz: float = gz - float(iz)
	var h00: float = grid[iz * n + ix]
	var h10: float = grid[iz * n + ix + 1]
	var h01: float = grid[(iz + 1) * n + ix]
	var h11: float = grid[(iz + 1) * n + ix + 1]
	var h: float = lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
	var sx: float = ((h10 - h00) + (h11 - h01)) * 0.5 / step
	var sz: float = ((h01 - h00) + (h11 - h10)) * 0.5 / step
	return Vector2(h, rad_to_deg(atan(sqrt(sx * sx + sz * sz))))

# ─────────────────────────────────────────────
# Nodes / Meshes / Materialien
# ─────────────────────────────────────────────

func _make_grass_node(transforms: Array[Transform3D], data: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _get_tuft_mesh()
	mm.instance_count = transforms.size()  # NACH use_custom_data/mesh setzen
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, data[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = NODE_GRASS
	inst.multimesh = mm
	inst.material_override = _get_grass_material()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visibility_range_end = GRASS_VISIBLE_RANGE
	return inst

func _make_flower_node(transforms: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _get_flower_mesh()
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = NODE_FLOWERS
	inst.multimesh = mm
	inst.material_override = _get_flower_material()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visibility_range_end = FLOWER_VISIBLE_RANGE
	return inst

func _make_bush_node(transforms: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _get_bush_mesh()
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = NODE_BUSHES
	inst.multimesh = mm
	inst.material_override = _get_bush_material()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visibility_range_end = BUSH_VISIBLE_RANGE
	return inst

## Grasbüschel: 5 schmale Dreiecks-Halme im Kreis, leicht nach außen geneigt (5 Dreiecke).
## UV.y = 0 an der Wurzel, 1 an der Spitze (Farbverlauf + Wind-Gewichtung im Shader).
static func _get_tuft_mesh() -> ArrayMesh:
	if _tuft_mesh != null:
		return _tuft_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades: int = 5
	for i in range(blades):
		var ang: float = float(i) * TAU / float(blades) + 0.3
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var root: Vector3 = dir * 0.12
		var blade_h: float = 0.55 + 0.12 * float(i % 3)
		var tip: Vector3 = root + dir * 0.18 + Vector3(0.0, blade_h, 0.0)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(root - side * 0.07)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(root + side * 0.07)
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(tip)
	st.generate_normals()
	_tuft_mesh = st.commit()
	return _tuft_mesh

## Busch: drei verschmolzene, niedrig aufgelöste Kugeln (ca. 190 Dreiecke).
static func _get_bush_mesh() -> ArrayMesh:
	if _bush_mesh != null:
		return _bush_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blobs: Array = [
		[0.55, Vector3(0.0, 0.38, 0.0)],
		[0.40, Vector3(0.38, 0.28, 0.12)],
		[0.42, Vector3(-0.32, 0.27, -0.16)],
	]
	for blob: Array in blobs:
		var r: float = blob[0]
		var sphere := SphereMesh.new()
		sphere.radius = r
		sphere.height = r * 1.7
		sphere.radial_segments = 8
		sphere.rings = 4
		st.append_from(sphere, 0, Transform3D(Basis.IDENTITY, blob[1]))
	_bush_mesh = st.commit()
	return _bush_mesh

static func _get_bush_material() -> StandardMaterial3D:
	if _bush_material == null:
		_bush_material = StandardMaterial3D.new()
		_bush_material.vertex_color_use_as_albedo = true  # MultiMesh-Instanzfarbe wird so zur Albedo
		_bush_material.roughness = 1.0
	return _bush_material

static func _get_grass_material() -> ShaderMaterial:
	if _grass_material == null:
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float sway_strength : hint_range(0.0, 2.0) = 1.0;

varying vec3 v_color;

float grass_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	// INSTANCE_CUSTOM.rgb = Spitzenfarbe, .a = Verhältnis Wurzel/Spitze (helle Spitze, dunkle Wurzel).
	float t = clamp(UV.y, 0.0, 1.0);
	v_color = INSTANCE_CUSTOM.rgb * mix(INSTANCE_CUSTOM.a, 1.0, t);
	// Phase über die Weltposition des Büschels -> kein synchrones Wedeln.
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = grass_hash(world_origin.xz) * 6.2831853;
	float wind = sin(TIME * 1.6 + phase) * 0.7 + sin(TIME * 3.1 + phase * 1.7) * 0.3;
	float bend = t * t;
	VERTEX.x += wind * bend * 0.14 * sway_strength;
	VERTEX.z += cos(TIME * 1.2 + phase) * bend * 0.09 * sway_strength;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
		_grass_material = ShaderMaterial.new()
		_grass_material.shader = shader
	return _grass_material

## Blume: dünner Stiel (ein Dreieck) + sechszackige Blüte, leicht geneigt (7 Dreiecke).
## UV.x kodiert das Teil für den Shader: 0..1 = Stiel, 2 = Blütenblatt, 3 = Blütenmitte.
## UV.y = Höhe 0..1 (Wind-Gewichtung).
static func _get_flower_mesh() -> ArrayMesh:
	if _flower_mesh != null:
		return _flower_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_h: float = 0.42
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(Vector3(-0.015, 0.0, 0.0))
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(Vector3(0.015, 0.0, 0.0))
	st.set_uv(Vector2(0.5, 1.0))
	st.add_vertex(Vector3(0.0, stem_h, 0.0))
	# Blüte: Fächer um die Mitte, um ~25° zur Seite gekippt, damit man sie auch von der Seite sieht.
	var center_p := Vector3(0.0, stem_h, 0.0)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(25.0))
	var petals: int = 6
	for i in range(petals):
		var a0: float = float(i) * TAU / float(petals)
		var a1: float = float(i + 1) * TAU / float(petals)
		var p0: Vector3 = center_p + tilt * Vector3(cos(a0) * 0.11, 0.0, sin(a0) * 0.11)
		var p1: Vector3 = center_p + tilt * Vector3(cos(a1) * 0.11, 0.0, sin(a1) * 0.11)
		st.set_uv(Vector2(3.0, 1.0))
		st.add_vertex(center_p)
		st.set_uv(Vector2(2.0, 1.0))
		st.add_vertex(p0)
		st.set_uv(Vector2(2.0, 1.0))
		st.add_vertex(p1)
	st.generate_normals()
	_flower_mesh = st.commit()
	return _flower_mesh

static func _get_flower_material() -> ShaderMaterial:
	if _flower_material == null:
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float sway_strength : hint_range(0.0, 2.0) = 1.0;

varying vec3 v_color;

float flower_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	float t = clamp(UV.y, 0.0, 1.0);
	// UV.x: 0..1 Stiel, 2 Blütenblatt (Instanzfarbe), 3 Blütenmitte (gelb).
	vec3 stem = vec3(0.16, 0.38, 0.10) * mix(0.7, 1.0, t);
	if (UV.x > 2.5) {
		v_color = vec3(0.95, 0.78, 0.15);
	} else if (UV.x > 1.5) {
		v_color = INSTANCE_CUSTOM.rgb;
	} else {
		v_color = stem;
	}
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = flower_hash(world_origin.xz) * 6.2831853;
	float wind = sin(TIME * 1.4 + phase) * 0.7 + sin(TIME * 2.7 + phase * 1.7) * 0.3;
	float bend = t * t;
	VERTEX.x += wind * bend * 0.08 * sway_strength;
	VERTEX.z += cos(TIME * 1.1 + phase) * bend * 0.05 * sway_strength;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
		_flower_material = ShaderMaterial.new()
		_flower_material.shader = shader
	return _flower_material
