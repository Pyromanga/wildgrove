# res://scripts/session/MeshCache.gd
class_name MeshCache extends RefCounted

## MeshCache — Baut alle prozeduralen Meshes einmalig beim Session-Boot.
##
## Kein Service im Container — lebt als Feld in Factory3D.
## Factory3D.build_cache() muss VOR dem ersten Spawn aufgerufen werden.
## ServiceOrchestrator ruft dies in Phase S8.8 auf (nach populate_session,
## vor world_gen und Entity-Spawning).
##
## Caching-Strategie:
##   ArrayMesh-Objekte: direkt geteilt (GPU-Ressource ist immutable nach build())
##   Multi-Node-Objekte (Baum, Kaktus, Pilz, Farn): PackedScene built from code, geklont via instantiate()
##   Randomisierte Objekte (Fels, gefällter Baumstamm): Einheits-Mesh + per-Instanz
##     non-uniform Node-Skalierung, statt neuer PrimitiveMesh-Objekte zur Laufzeit
##
## Factory3D erzeugt ausschließlich über diesen Cache. Factory3D.cache
## muss gesetzt und gebaut sein, bevor die erste create_*()-Methode
## aufgerufen wird.
##
## Performance-Ziel: 0 CylinderMesh.new() / SphereMesh.new() zur Laufzeit.
## Alle GPU-Uploads passieren einmalig in build().

const LOG_CAT := "MeshCache"

## Nah/Fern-Sichtweite für Baumkronen (Wunsch "entferntes/nahes Rendern"): innerhalb
## LOD_NEAR_DISTANCE zeigen sich die Laub-Büschel-Karten und Zweige (_assemble_tree()), jenseits
## davon wenige grobe Kronenkugeln (kein Geometrie-Detail nötig, auf die Entfernung ohnehin nicht
## unterscheidbar) — beide sitzen die ganze Zeit im Baum, Godots
## GeometryInstance3D.visibility_range_* blendet rein über Entfernung zur Kamera um, kein
## eigener Tick/Code nötig. LOD_FADE_MARGIN ist die Übergangszone (visibility_range_*_margin),
## in der beide weich über- statt hart umgeblendet werden (VISIBILITY_RANGE_FADE_SELF).
## 2026-10-07: 55 statt 14 m — Bäume sind jetzt echte 7-14 m hohe Objekte (siehe TreeSkeleton),
## die Laub-Büschel müssen bis weit hinein sichtbar bleiben, erst dahinter übernehmen die Kronenkugeln.
const LOD_NEAR_DISTANCE: float = 55.0
const LOD_FADE_MARGIN: float = 6.0

## Wachstumsstadien (Wunsch "Bäume in verschiedenen Stadien darstellen"): EIN Bauplan pro Art
## (siehe _build_deciduous_tree()/_build_scene_pine()), `stage` skaliert ihn nur — kein
## separat gepflegtes "Sapling-Modell" pro Baumart, sondern derselbe Verzweigungs-Bauplan
## (TreeSkeleton) mit weniger/kürzeren Ästen und kleinerem Stamm. TREE_STAGE_SCALE skaliert Stamm/Äste/Kronen
## gleichmäßig, TREE_STAGE_MAX_LEVEL/-DENSITY kürzen die Verzweigung, PINE_STAGE_WHORLS die
## Astkränze der Tanne.
## Auswahl WELCHES Stadium ein konkreter Baum bekommt: siehe TreeGrowthStage.gd (deterministisch
## aus der Weltposition, nicht zufällig — Determinismus über alle Peers, wie überall sonst in
## diesem Cache).
enum TreeStage { SAPLING, YOUNG, MATURE }
## Skalierung gegenüber dem ausgewachsenen Baum. Ein Sapling ist ~1,8 m (Spielergröße), ein
## Jungbaum ~5 m (Eiche) — vorher 0.42/0.7 eines nur 3 m hohen Baums.
const TREE_STAGE_SCALE: Dictionary = {
	TreeStage.SAPLING: 0.16,
	TreeStage.YOUNG:   0.5,
	TreeStage.MATURE:  1.0,
}
## Wie tief die Verzweigung geht (1 = nur Hauptäste, 3 = bis zu den Zweigen), Anteil der Äste je
## Ebene und Kartenzahl-Faktor (kleine Bäume brauchen pro Anker mehr Karten, um nicht kahl zu wirken).
const TREE_STAGE_MAX_LEVEL: Dictionary = {TreeStage.SAPLING: 1, TreeStage.YOUNG: 2, TreeStage.MATURE: 3}
const TREE_STAGE_DENSITY: Dictionary   = {TreeStage.SAPLING: 0.6, TreeStage.YOUNG: 0.8, TreeStage.MATURE: 1.0}
const TREE_STAGE_CARDS: Dictionary     = {TreeStage.SAPLING: 2.0, TreeStage.YOUNG: 1.4, TreeStage.MATURE: 1.0}
## Astkränze (Wirtel) der Tanne je Stadium.
const PINE_STAGE_WHORLS: Dictionary    = {TreeStage.SAPLING: 4, TreeStage.YOUNG: 7, TreeStage.MATURE: 11}

## Einfache Meshes — direkt als ArrayMesh geteilt
var meshes: Dictionary = {}     # { "key": ArrayMesh }

## Komplexe Multi-Node-Objekte — als PackedScene geklont
var scenes: Dictionary = {}     # { "key": PackedScene }

## Material-Cache — StandardMaterial3D ist teuer zu erstellen
var materials: Dictionary = {}  # { color_key: StandardMaterial3D }

var _built: bool = false

func build() -> void:
	if _built:
		return
	var t := Time.get_ticks_msec()

	_build_materials()
	_build_simple_meshes()
	_build_tree_scenes()
	_build_mushroom_scenes()
	_build_animal_meshes()
	_build_bar_mesh()

	_built = true
	AppLogger.log_info(
		"MeshCache: %d meshes, %d scenes, %d materials in %d ms" % [
			meshes.size(), scenes.size(), materials.size(),
			Time.get_ticks_msec() - t
		],
		LOG_CAT
	)

func is_built() -> bool:
	return _built

## Gibt ein gecachtes oder neu erstelltes Material zurück.
## resource_local_to_scene = false → GPU-seitig geteilt, kein erneutes Upload.
func get_material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), str(unshaded)]
	if not materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if unshaded:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.resource_local_to_scene = false  # GPU-seitig teilen
		materials[key] = mat
	return materials[key]

## Wie get_material(), aber mit prozeduraler Detail-Textur (ProceduralTextureFactory)
## statt reiner Flächenfarbe — "Natur ist auch nur Mathematik": Stein/Holz/Rinde/
## Moos/Gras/Sand/Kies/Erde bekommen Grain-Variation statt komplett flacher Fläche,
## ohne eine einzige Bilddatei. `color` tönt die Textur (StandardMaterial3D
## multipliziert albedo_color * albedo_texture), uv1_scale kachelt sie mehrfach
## über das Mesh. Unbekannte category fällt auf get_material() zurück (kein harter
## Fehler).
func get_textured_material(color: Color, category: String, unshaded: bool = false) -> StandardMaterial3D:
	var key := "tex_%s_%s_%s" % [category, color.to_html(), str(unshaded)]
	if not materials.has(key):
		var tex: ImageTexture
		match category:
			"stone":  tex = ProceduralTextureFactory.stone()
			"wood":   tex = ProceduralTextureFactory.wood()
			"grass":  tex = ProceduralTextureFactory.grass()
			"sand":   tex = ProceduralTextureFactory.sand()
			"gravel": tex = ProceduralTextureFactory.gravel()
			"dirt":   tex = ProceduralTextureFactory.dirt()
			"bark":   tex = ProceduralTextureFactory.bark()
			"moss":   tex = ProceduralTextureFactory.moss()
			"ore_iron":   tex = ProceduralTextureFactory.ore_iron()
			"ore_copper": tex = ProceduralTextureFactory.ore_copper()
			"ice":        tex = ProceduralTextureFactory.ice()
			"sulfur":     tex = ProceduralTextureFactory.sulfur()
			"wax":        tex = ProceduralTextureFactory.wax()
			"glass":      tex = ProceduralTextureFactory.glass()
			"charcoal":   tex = ProceduralTextureFactory.charcoal()
			_:
				AppLogger.log_warn(
					"MeshCache: unbekannte Textur-Kategorie '%s' — falle auf Flächenfarbe zurück." % category,
					LOG_CAT
				)
				return get_material(color, unshaded)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
		mat.roughness = 0.9
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if unshaded:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.resource_local_to_scene = false  # GPU-seitig teilen
		materials[key] = mat
	return materials[key]

## Einmal gebauter, geteilter Shader für get_swaying_material() — Shader.new()
## ist teuer, das Kompilat aber pro Prozess identisch, also genau wie
## MeshCache.meshes/materials nur EINMAL bauen, danach an alle ShaderMaterial-
## Instanzen weiterreichen (jede ShaderMaterial trägt nur ihre eigenen
## Uniform-Werte, der kompilierte Shader-Code wird geteilt).
static var _sway_shader: Shader = null

## Wind-Sway für Baumkronen/Farn (docs/procedural-textures-and-weather-vfx.md,
## "Bekannte Grenzen" → "naheliegender nächster Schritt"): Vertex-Shader statt
## StandardMaterial3D, verschiebt Vertices mit positivem lokalem Y (siehe
## Shader-Kommentar) im Takt zweier überlagerter Sinuskurven aus TIME — exakt
## dasselbe Zwei-Sinus-Prinzip wie WindField (GDScript), hier aber eigenständig
## in GLSL, weil ein Shader keine GDScript-Klassen aufrufen kann (siehe bereits
## TerrainMeshBuilder-Kommentar zu grain_hash()). Ein Hash auf die Weltposition
## der jeweiligen MeshInstance3D gibt jedem Baum/Farn eine eigene Phasenlage,
## damit nicht der komplette Wald im Gleichtakt wedelt.
##
## category: wie bei get_textured_material() — leer lässt die Fläche ungetönt
## einfarbig (für Baumkronen, die bisher get_material() nutzten).
## sway_strength: skaliert die Auslenkung (kleines Farnblatt braucht weniger
## als eine große Baumkrone), reiner Uniform-Wert, kein neuer Shader nötig.
func get_swaying_material(color: Color, category: String = "", sway_strength: float = 1.0) -> ShaderMaterial:
	var key := "sway_%s_%s_%s" % [category, color.to_html(), str(sway_strength)]
	if not materials.has(key):
		if _sway_shader == null:
			_sway_shader = _build_sway_shader()
		var tex: Texture2D = null
		if category != "":
			match category:
				"stone":  tex = ProceduralTextureFactory.stone()
				"wood":   tex = ProceduralTextureFactory.wood()
				"grass":  tex = ProceduralTextureFactory.grass()
				"sand":   tex = ProceduralTextureFactory.sand()
				"gravel": tex = ProceduralTextureFactory.gravel()
				"dirt":   tex = ProceduralTextureFactory.dirt()
				"bark":   tex = ProceduralTextureFactory.bark()
				"moss":   tex = ProceduralTextureFactory.moss()
				_:
					AppLogger.log_warn(
						"MeshCache: unbekannte Textur-Kategorie '%s' in get_swaying_material() — bleibt ungetönt." % category,
						LOG_CAT
					)
		var mat := ShaderMaterial.new()
		mat.shader = _sway_shader
		mat.set_shader_parameter("albedo_color", color)
		mat.set_shader_parameter("use_texture", tex != null)
		if tex != null:
			mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("sway_strength", sway_strength)
		mat.resource_local_to_scene = false  # GPU-seitig teilen, wie alle anderen Materials hier
		materials[key] = mat
	return materials[key]

## Nah-LOD (siehe LOD_NEAR_DISTANCE-Kommentar): sichtbar bis LOD_NEAR_DISTANCE, blendet danach
## weich zur Fern-Variante über.
func _apply_near_lod(inst: GeometryInstance3D) -> void:
	inst.visibility_range_end = LOD_NEAR_DISTANCE
	inst.visibility_range_end_margin = LOD_FADE_MARGIN
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

## Fern-LOD: unsichtbar bis LOD_NEAR_DISTANCE, blendet davor weich von der Nah-Variante über.
func _apply_far_lod(inst: GeometryInstance3D) -> void:
	inst.visibility_range_begin = LOD_NEAR_DISTANCE
	inst.visibility_range_begin_margin = LOD_FADE_MARGIN
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

## Basis für einen Astabschnitt entlang `dir` (Länge = Vektorlänge, Radius = Basisradius): Y-Achse =
## Astrichtung, X/Z orthogonal dazu — codiert Rotation UND Skalierung in einem Schritt. Das Mesh
## "branch_seg" liegt entlang lokal Y von -0.5..0.5, an der Mittelpunkt-Position plaziert ergibt das
## genau den Zylinder von `start` bis `start + dir`.
func _branch_basis(dir: Vector3, radius: float) -> Basis:
	var yn: Vector3 = dir.normalized()
	var refv: Vector3 = Vector3.FORWARD if absf(yn.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var xn: Vector3 = refv.cross(yn).normalized()
	var zn: Vector3 = xn.cross(yn).normalized()
	return Basis(xn * radius, dir, zn * radius)

## Ein MultiMeshInstance3D aus vielen Instanzen EINES Meshes: ein Draw-Call statt hunderter Nodes.
func _make_multimesh(
	node_name: String, mesh: Mesh, tfs: Array, mat: Material, cast_shadows: bool
) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = tfs.size()
	for i in range(tfs.size()):
		mm.set_instance_transform(i, tfs[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst

## Laub-Material mit Büschel-Karte (viele Blätter pro Karte, siehe ProceduralTextureFactory.foliage_card).
## `flutter` lässt die ganze Karte leicht im Wind zittern (nicht nur die Spitze wie bei Farn/Kugeln).
func get_foliage_material(
	color: Color, shape: int, hue_seed: int, sway_strength: float = 1.0,
	leaf_count: int = 14, aspect: float = 0.55
) -> ShaderMaterial:
	var key := "foliage_%s_%d_%d_%s_%d_%s" % [color.to_html(), shape, hue_seed, str(sway_strength), leaf_count, str(aspect)]
	if not materials.has(key):
		if _sway_shader == null:
			_sway_shader = _build_sway_shader()
		var mat := ShaderMaterial.new()
		mat.shader = _sway_shader
		mat.set_shader_parameter("albedo_color", color)
		mat.set_shader_parameter("use_texture", true)
		mat.set_shader_parameter("albedo_tex", ProceduralTextureFactory.foliage_card(128, hue_seed, shape, leaf_count, aspect))
		mat.set_shader_parameter("sway_strength", sway_strength)
		mat.set_shader_parameter("flutter", 0.7)
		mat.resource_local_to_scene = false
		materials[key] = mat
	return materials[key]

## Setzt einen Baum aus TreeSkeleton-Daten zusammen. Nodes (statt ~40 früher): "Branches"
## (Stamm + Hauptäste, immer sichtbar), "Twigs" (Seitenäste/Zweige, nur nah), "Leaves0..2" (drei
## Farbvarianten Laubkarten, nur nah), "CrownFar" (grobe Kugeln, nur fern), bei Schnee "Snow".
## look: bark_color, colors[3], shape, hue_seed, leaf_count, aspect, sway, cards_per_tip,
## clump_radius, card_size, far_cell, far_color, optional flat/drop/stretch/far_squash/snow.
func _assemble_tree(tree_name: String, skel: Dictionary, look: Dictionary, stage_scale: float, cards_mult: float) -> PackedScene:
	var root := Node3D.new()
	root.name = tree_name

	var bark := get_textured_material(look["bark_color"], "bark")
	var main_tf: Array[Transform3D] = []
	var fine_tf: Array[Transform3D] = []
	for seg: Dictionary in skel["segments"]:
		var a: Vector3 = seg["a"]
		var b: Vector3 = seg["b"]
		var tf := Transform3D(_branch_basis(b - a, float(seg["r"])), (a + b) * 0.5)
		if int(seg["level"]) <= 1:
			main_tf.append(tf)
		else:
			fine_tf.append(tf)
	root.add_child(_make_multimesh("Branches", meshes["branch_seg"], main_tf, bark, true))
	if not fine_tf.is_empty():
		var twigs := _make_multimesh("Twigs", meshes["branch_seg"], fine_tf, bark, false)
		_apply_near_lod(twigs)
		root.add_child(twigs)

	# Laub: Kartengröße/Büschelradius wachsen mit dem Baum, aber langsamer als der Stamm.
	var size_k: float = pow(stage_scale, 0.45)
	var cards_n: int = maxi(1, roundi(float(look["cards_per_tip"]) * cards_mult))
	var groups: Array = [[], [], []]
	var salt: int = 0
	for tip: Dictionary in skel["tips"]:
		var cards: Array[Transform3D] = TreeSkeleton.cards_for_tip(
			tip["pos"], cards_n, float(look["clump_radius"]) * size_k, float(look["card_size"]) * size_k, salt,
			float(look.get("flat", 1.0)), float(look.get("drop", 0.0)) * size_k, look.get("stretch", Vector2.ONE))
		for i in range(cards.size()):
			groups[(i + salt) % 3].append(cards[i])
		salt += 1
	var colors: Array = look["colors"]
	for g in range(3):
		if groups[g].is_empty():
			continue
		var mat := get_foliage_material(
			colors[g], int(look["shape"]), int(look["hue_seed"]) + g * 7, float(look["sway"]),
			int(look.get("leaf_count", 14)), float(look.get("aspect", 0.55)))
		var leaves := _make_multimesh("Leaves%d" % g, meshes["foliage_quad"], groups[g], mat, false)
		_apply_near_lod(leaves)
		root.add_child(leaves)

	# Fern-LOD: wenige grobe Kronenkugeln statt hunderter Karten.
	var squash: float = float(look.get("far_squash", 0.8))
	var blob_tf: Array[Transform3D] = []
	for blob: Dictionary in TreeSkeleton.crown_blobs(skel["tips"], float(look["far_cell"]) * size_k, float(look.get("far_spread", 1.7))):
		var r: float = float(blob["r"])
		blob_tf.append(Transform3D(Basis.from_scale(Vector3(r, r * squash, r)), blob["pos"]))
	var far := _make_multimesh("CrownFar", meshes["crown_lowpoly"], blob_tf,
		get_swaying_material(look["far_color"], "", float(look["sway"]) * 0.6), false)
	_apply_far_lod(far)
	root.add_child(far)

	if bool(look.get("snow", false)):
		# Schneehauben: flache weiße Kissen auf den Astenden (nah) — Kinderzahl wächst um 1 Node.
		var snow_tf: Array[Transform3D] = []
		for tip: Dictionary in skel["tips"]:
			snow_tf.append(Transform3D(Basis.from_scale(Vector3(0.7, 0.13, 0.7) * size_k * 1.3), (tip["pos"] as Vector3) + Vector3(0.0, 0.18 * size_k, 0.0)))
		var snow := _make_multimesh("Snow", meshes["crown_lowpoly"], snow_tf, get_material(Color(0.97, 0.98, 1.0)), false)
		_apply_near_lod(snow)
		root.add_child(snow)

	return _pack_scene(root)

## Laubbaum aus cfg/look für das Stadium `stage` (siehe TREE_STAGE_*). `salt` trennt die RNG-Ströme der Arten.
func _build_deciduous_tree(tree_name: String, cfg: Dictionary, look: Dictionary, stage: int, salt: int) -> PackedScene:
	var s: float = TREE_STAGE_SCALE[stage]
	var skel: Dictionary = TreeSkeleton.deciduous(
		cfg, s, int(TREE_STAGE_MAX_LEVEL[stage]), float(TREE_STAGE_DENSITY[stage]), 1000 + salt * 97 + int(stage))
	return _assemble_tree(tree_name, skel, look, s, float(TREE_STAGE_CARDS[stage]))

static func _build_sway_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : hint_default_white;
uniform bool use_texture = false;
uniform float sway_strength : hint_range(0.0, 2.0) = 1.0;
// Ganze Karte zittert (Laub-Büschel); 0 = nur die Spitze schwingt (Farn, Kugeln).
uniform float flutter : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.9;

// Gleiche Hash-Familie wie ProceduralTextureFactory._hash2() / TerrainMeshBuilder.grain_hash()
// -- eigenständig hier, weil ein Shader keine GDScript-Klassen aufrufen kann.
float sway_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	// Weltposition des Objekt-Pivots (nicht pro Vertex) -> stabile Phase je
	// MeshInstance3D, unterschiedlich je Baum/Farn statt synchronem Wedeln.
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = sway_hash(world_origin.xz) * 6.2831853;
	float t = TIME;
	float wind = sin(t * 0.9 + phase) * 0.7 + sin(t * 2.3 + phase * 1.7) * 0.3;
	float sway = cos(t * 0.7 + phase);
	// Nur der obere, von der Basis wegzeigende Teil des Meshes schwingt
	// spürbar (Ast/Blattspitze) -- die Basis (VERTEX.y <= 0) bleibt ruhig.
	float lift = max(VERTEX.y, 0.0);
	VERTEX.x += wind * lift * 0.10 * sway_strength;
	VERTEX.z += sway * lift * 0.08 * sway_strength;
	VERTEX.x += wind * flutter * 0.05;
	VERTEX.y += sway * flutter * 0.03;
}

void fragment() {
	// BUGFIX (Wunsch "Blätter sehen hässlich aus" — Screenshots zeigten schwarze/dunkle
	// Bretter statt Blattformen): zwei Fehler gleichzeitig.
	// 1) "UV * 2.0" kachelte die Blattkarten-Textur 2x2 pro Karte (gedacht evtl. für eine
	//    andere, tatsächlich tilende category-Textur, aber pauschal auf ALLE Nutzer dieses
	//    einen geteilten Shaders angewendet) -- ein Blatt-Karten-Mesh war damals als
	//    GENAU EIN Blatt pro Karte ausgelegt, nicht als Kachel (heute: foliage_quad mit Büschel-Textur).
	// 2) ALPHA wurde nie gesetzt -- ohne das rendert eine Spatial-Shader-Material IMMER
	//    opak, der Alpha-Kanal der Blattkarten-Textur (der eigentliche Blattform-Ausschnitt,
	//    siehe ProceduralTextureFactory._build_leaf()) wurde komplett ignoriert. Jede Karte
	//    zeigte dadurch ihr volles rechteckiges Mesh in der (meist dunklen) ALBEDO-Farbe
	//    der TRANSPARENTEN Pixel -- daher die hässlichen dunklen "Bretter" statt Blattformen.
	// ALPHA_SCISSOR_THRESHOLD (Hard-Cutout, kein Blend) statt echter Transparenz: vermeidet
	// Sortierungs-Artefakte zwischen den vielen sich überlappenden Karten pro Krone.
	vec4 tex_color = use_texture ? texture(albedo_tex, UV) : vec4(1.0);
	ALBEDO = clamp((albedo_color * tex_color).rgb, 0.0, 1.0);
	ALPHA = tex_color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
}
"""
	return shader

func get_mesh(key: String) -> ArrayMesh:
	return meshes.get(key)

## Instanziiert eine komplexe Szene (Baum, Kaktus, Farn etc.).
## Gibt Node3D.new() zurück wenn der Key nicht existiert — nie null.
func instantiate_scene(key: String) -> Node3D:
	var scene: PackedScene = scenes.get(key)
	if scene == null:
		AppLogger.log_error("MeshCache: Szene '%s' nicht gefunden." % key, LOG_CAT)
		return Node3D.new()
	return scene.instantiate() as Node3D

# ─────────────────────────────────────────────────────────────────────────────
# Build-Methoden (einmalig beim Session-Boot)
# ─────────────────────────────────────────────────────────────────────────────

func _build_materials() -> void:
	# Alle Biom-/Objekt-Farben vorab bauen
	var presets := {
		"trunk_oak":      Color(0.4,  0.25, 0.10),
		"trunk_pine":     Color(0.35, 0.20, 0.08),
		"leaves_oak":     Color(0.15, 0.50, 0.10),
		"leaves_pine":    Color(0.10, 0.40, 0.08),
		"leaves_snow":    Color(0.95, 0.97, 1.00),
		"rock_forest":    Color(0.45, 0.40, 0.35),
		"rock_desert":    Color(0.75, 0.60, 0.35),
		"cactus":         Color(0.20, 0.55, 0.15),
		"fern":           Color(0.20, 0.60, 0.15),
		"mushroom_red":   Color(0.85, 0.10, 0.10),
		"mushroom_brown": Color(0.50, 0.30, 0.10),
		"bar_hp":         Color(0.10, 0.85, 0.10),
		"bar_bg":         Color(0.15, 0.15, 0.15, 0.80),
		"fallen_log":     Color(0.35, 0.22, 0.09),
		"animal_body":    Color(0.60, 0.50, 0.35),
		"animal_head":    Color(0.55, 0.45, 0.30),
	}
	for key in presets:
		get_material(presets[key])

func _build_simple_meshes() -> void:
	# Zylinder-Varianten für Baumstämme
	for r_pair in [["trunk_sm", 0.12, 0.18], ["trunk_md", 0.15, 0.22], ["trunk_lg", 0.18, 0.28]]:
		var m := CylinderMesh.new()
		m.top_radius    = r_pair[1]
		m.bottom_radius = r_pair[2]
		m.height        = 2.0
		meshes[r_pair[0]] = _to_array_mesh(m)

	# Segment für das verzweigte Astwerk (TreeSkeleton): top/bottom = TreeSkeleton.TAPER (0.75),
	# damit aufeinanderfolgende Abschnitte (Radius * 0.75^i) nahtlos aneinander anschließen.
	var branch_seg := CylinderMesh.new()
	branch_seg.top_radius       = TreeSkeleton.TAPER
	branch_seg.bottom_radius    = 1.0
	branch_seg.height           = 1.0
	branch_seg.radial_segments  = 6
	branch_seg.rings            = 1
	branch_seg.cap_top          = false
	branch_seg.cap_bottom       = false
	meshes["branch_seg"] = _to_array_mesh(branch_seg)

	# Laub-Büschel-Karte (1 m Kante, Größe kommt über die Instanz-Basis) + grobe Kugel fürs Fern-LOD
	# und Schneekissen. 8 × 5 Segmente statt der 64 × 32 der Standard-SphereMesh: hunderte Instanzen.
	var foliage_quad := QuadMesh.new()
	foliage_quad.size = Vector2(1.0, 1.0)
	meshes["foliage_quad"] = _to_array_mesh(foliage_quad)
	var crown_low := SphereMesh.new()
	crown_low.radius = 1.0
	crown_low.height = 2.0
	crown_low.radial_segments = 8
	crown_low.rings = 5
	meshes["crown_lowpoly"] = _to_array_mesh(crown_low)

	# Kaktus-Stamm und -Arme
	var kaktus_stamm := CylinderMesh.new()
	kaktus_stamm.top_radius    = 0.18
	kaktus_stamm.bottom_radius = 0.20
	kaktus_stamm.height        = 1.6
	meshes["cactus_trunk"] = _to_array_mesh(kaktus_stamm)

	var kaktus_arm := CylinderMesh.new()
	kaktus_arm.top_radius    = 0.10
	kaktus_arm.bottom_radius = 0.12
	kaktus_arm.height        = 0.6
	meshes["cactus_arm"] = _to_array_mesh(kaktus_arm)

	# Farn-Blatt (abgeflachte Kugel)
	var fern_leaf := SphereMesh.new()
	fern_leaf.radius = 0.4
	fern_leaf.height = 0.15
	meshes["fern_leaf"] = _to_array_mesh(fern_leaf)

	# Gefällter Baumstamm (liegender Zylinder — Rotation beim Instanziieren)
	var log := CylinderMesh.new()
	log.top_radius    = 0.22
	log.bottom_radius = 0.25
	log.height        = 2.4
	meshes["fallen_log"] = _to_array_mesh(log)

	# Felsblock-Basis — Einheitskugel, pro Instanz non-uniform skaliert
	var boulder := SphereMesh.new()
	boulder.radius = 1.0
	boulder.height = 2.0
	meshes["rock_unit"] = _to_array_mesh(boulder)

	# Pilz-Teile — geteilt über alle Pilz-Typen, nur Material variiert
	var shroom_stem := CylinderMesh.new()
	shroom_stem.top_radius    = 0.04
	shroom_stem.bottom_radius = 0.06
	shroom_stem.height        = 0.18
	meshes["mushroom_stem"] = _to_array_mesh(shroom_stem)

	var shroom_cap := SphereMesh.new()
	shroom_cap.radius = 0.14
	shroom_cap.height = 0.14 * 0.55  # abgeflacht
	meshes["mushroom_cap"] = _to_array_mesh(shroom_cap)

	var shroom_dot := SphereMesh.new()
	shroom_dot.radius = 0.025
	shroom_dot.height = 0.05
	meshes["mushroom_dot"] = _to_array_mesh(shroom_dot)


func _build_tree_scenes() -> void:
	# Wunsch "Bäume in verschiedenen Stadien darstellen": jede Art registriert zusätzlich zur
	# unveränderten "tree_<art>"-Schlüssel (= MATURE, rückwärtskompatibel — Factory3D/bestehende
	# Aufrufer ohne Stadium-Wissen bekommen weiterhin den ausgewachsenen Baum) zwei weitere
	# Schlüssel "_young"/"_sapling". Auswahl WELCHES Stadium ein Baum bekommt: TreeGrowthStage.gd
	# (deterministisch aus der Weltposition), aufgerufen von OakTree/WillowTree/MapleTree/
	# PineTree._build_visuals() — hier wird nur die volle Palette gebaut/gecacht.
	scenes["tree_oak"]            = _build_scene_oak(TreeStage.MATURE)
	scenes["tree_oak_young"]      = _build_scene_oak(TreeStage.YOUNG)
	scenes["tree_oak_sapling"]    = _build_scene_oak(TreeStage.SAPLING)
	# BUGFIX (2026-09-20, "keine Farbunterschiede bei Baumarten"): tree_willow/
	# tree_maple fehlten komplett im Cache — Factory3D.create_simple_tree()
	# fiel für ALLE drei Laubbaumtypen (Oak/Willow/Maple) auf "tree_oak"
	# zurück, sichtbar identisch trotz unterschiedlicher Baumart.
	scenes["tree_willow"]         = _build_scene_willow(TreeStage.MATURE)
	scenes["tree_willow_young"]   = _build_scene_willow(TreeStage.YOUNG)
	scenes["tree_willow_sapling"] = _build_scene_willow(TreeStage.SAPLING)
	scenes["tree_maple"]          = _build_scene_maple(TreeStage.MATURE)
	scenes["tree_maple_young"]    = _build_scene_maple(TreeStage.YOUNG)
	scenes["tree_maple_sapling"]  = _build_scene_maple(TreeStage.SAPLING)
	scenes["tree_pine"]                = _build_scene_pine(false, TreeStage.MATURE)
	scenes["tree_pine_young"]          = _build_scene_pine(false, TreeStage.YOUNG)
	scenes["tree_pine_sapling"]        = _build_scene_pine(false, TreeStage.SAPLING)
	scenes["tree_pine_snow"]           = _build_scene_pine(true, TreeStage.MATURE)
	scenes["tree_pine_snow_young"]     = _build_scene_pine(true, TreeStage.YOUNG)
	scenes["tree_pine_snow_sapling"]   = _build_scene_pine(true, TreeStage.SAPLING)
	scenes["tree_fallen_forest"] = _build_scene_fallen("forest")
	scenes["tree_fallen_desert"] = _build_scene_fallen("desert")
	scenes["cactus"]            = _build_scene_cactus()
	scenes["fern"]              = _build_scene_fern()

func _build_mushroom_scenes() -> void:
	scenes["mushroom_red"]    = _build_scene_mushroom("red")
	scenes["mushroom_brown"]  = _build_scene_mushroom("brown")
	scenes["mushroom_orange"] = _build_scene_mushroom("orange")

func _build_scene_mushroom(mushroom_type: String) -> PackedScene:
	var root := Node3D.new()
	root.name = "Mushroom_%s" % mushroom_type.capitalize()

	var stem := MeshInstance3D.new()
	stem.mesh = meshes["mushroom_stem"]
	stem.set_surface_override_material(0, get_material(Color(0.85, 0.80, 0.72)))
	stem.position.y = 0.09
	root.add_child(stem)

	var cap_color: Color
	match mushroom_type:
		"red":    cap_color = Color(0.85, 0.15, 0.10)
		"orange": cap_color = Color(0.90, 0.55, 0.10)
		_:        cap_color = Color(0.55, 0.35, 0.18)

	var cap := MeshInstance3D.new()
	cap.mesh = meshes["mushroom_cap"]
	cap.set_surface_override_material(0, get_material(cap_color))
	cap.position.y = 0.22
	root.add_child(cap)

	if mushroom_type == "red":
		var dot_material := get_material(Color(1.0, 1.0, 1.0))
		for i in range(3):
			var dot := MeshInstance3D.new()
			dot.mesh = meshes["mushroom_dot"]
			dot.set_surface_override_material(0, dot_material)
			var angle := (TAU / 3.0) * i
			dot.position = Vector3(cos(angle) * 0.07, 0.24, sin(angle) * 0.07)
			root.add_child(dot)

	return _pack_scene(root)

func _build_animal_meshes() -> void:
	for a in [["animal_body_sm", Vector3(0.3, 0.5, 0.3)],
			  ["animal_body_md", Vector3(0.5, 0.7, 0.5)],
			  ["animal_body_lg", Vector3(0.6, 0.8, 0.6)]]:
		var m := BoxMesh.new()
		m.size = a[1]
		meshes[a[0]] = _to_array_mesh(m)

	# Tier-Kopf (kleinere Box)
	var head := BoxMesh.new()
	head.size = Vector3(0.28, 0.28, 0.28)
	meshes["animal_head"] = _to_array_mesh(head)

func _build_bar_mesh() -> void:
	# HP-Bar Hintergrund + Füllung (zwei schmale Quads)
	var bg := QuadMesh.new()
	bg.size = Vector2(1.2, 0.20)
	meshes["bar_bg"] = _to_array_mesh(bg)
	var fg := QuadMesh.new()
	fg.size = Vector2(1.1, 0.15)
	meshes["bar_fg"] = _to_array_mesh(fg)

# ─────────────────────────────────────────────────────────────────────────────
# Szenen-Builder (erstellen Node-Hierarchie, verpacken als PackedScene)
# ─────────────────────────────────────────────────────────────────────────────

## Eiche — kräftiger, kurzer Stamm (≈ 4 m bis zur Krone, Gesamthöhe ≈ 10 m bei 1,8 m Spielergröße),
## sieben ausladende Hauptäste (unten flach bis 66°, oben steiler), je vier Seitenäste mit je zwei
## Zweigen — an den Enden sitzen dichte, gelappte (LOBED) Laubbüschel.
func _build_scene_oak(stage: int = TreeStage.MATURE) -> PackedScene:
	var cfg := {
		"trunk_height": 4.2, "trunk_radius": 0.40, "trunk_segments": 4, "trunk_bend": 0.10, "leaf_min_level": 2,
		"levels": [
			{"count": 7, "t_min": 0.48, "t_max": 0.95, "ang_min": 38.0, "ang_max": 66.0, "len_min": 0.85, "len_max": 1.25,
			 "rad_frac": 0.5, "segments": 3, "droop": 0.04, "bend": 0.16, "up_bias": 0.12},
			{"count": 4, "t_min": 0.30, "t_max": 0.95, "ang_min": 30.0, "ang_max": 62.0, "len_min": 0.45, "len_max": 0.65,
			 "rad_frac": 0.55, "segments": 2, "droop": 0.05, "bend": 0.20, "up_bias": 0.10},
			{"count": 2, "t_min": 0.40, "t_max": 0.90, "ang_min": 25.0, "ang_max": 55.0, "len_min": 0.45, "len_max": 0.60,
			 "rad_frac": 0.60, "segments": 2, "droop": 0.04, "bend": 0.20, "up_bias": 0.10},
		],
	}
	var look := {
		"bark_color": Color(0.4, 0.25, 0.10),
		"colors": [Color(0.15, 0.50, 0.10), Color(0.12, 0.45, 0.08), Color(0.20, 0.55, 0.12)],
		"shape": ProceduralTextureFactory.LeafShape.LOBED, "hue_seed": 0, "leaf_count": 14, "aspect": 0.55,
		"sway": 1.0, "cards_per_tip": 4, "clump_radius": 0.9, "card_size": 1.5,
		"far_cell": 2.4, "far_color": Color(0.14, 0.47, 0.09),
	}
	return _build_deciduous_tree("Tree_Oak", cfg, look, stage, 1)

## Weide — schlanker Stamm, flach abgewinkelte Hauptäste, daran LANGE, stark hängende Seitenäste
## und Zweige (droop): die Blätter hängen als schmale lanzettliche Vorhänge (ELLIPSE, aspect 0.22,
## y-gestreckt, `drop`) bis auf ca. 1,5 m über den Boden.
func _build_scene_willow(stage: int = TreeStage.MATURE) -> PackedScene:
	var cfg := {
		"trunk_height": 3.0, "trunk_radius": 0.30, "trunk_segments": 4, "trunk_bend": 0.14, "leaf_min_level": 3,
		"min_y": 1.4,   # hängende Zweige enden mindestens hier (Simulation: sonst bis 0,7 m unter dem Boden)
		"levels": [
			{"count": 6, "t_min": 0.55, "t_max": 0.95, "ang_min": 28.0, "ang_max": 52.0, "len_min": 0.9, "len_max": 1.3,
			 "rad_frac": 0.5, "segments": 3, "droop": 0.08, "bend": 0.14, "up_bias": 0.1},
			{"count": 5, "t_min": 0.25, "t_max": 0.95, "ang_min": 55.0, "ang_max": 110.0, "len_min": 0.8, "len_max": 1.1,
			 "rad_frac": 0.55, "segments": 3, "droop": 0.22, "bend": 0.12, "up_bias": 0.0},
			{"count": 3, "t_min": 0.30, "t_max": 0.95, "ang_min": 15.0, "ang_max": 40.0, "len_min": 0.5, "len_max": 0.7,
			 "rad_frac": 0.6, "segments": 2, "droop": 0.32, "bend": 0.10, "up_bias": 0.0},
		],
	}
	var look := {
		"bark_color": Color(0.45, 0.38, 0.22),
		"colors": [Color(0.55, 0.62, 0.22), Color(0.50, 0.58, 0.20), Color(0.58, 0.66, 0.26)],
		"shape": ProceduralTextureFactory.LeafShape.ELLIPSE, "hue_seed": 20, "leaf_count": 20, "aspect": 0.22,
		"sway": 1.3, "cards_per_tip": 3, "clump_radius": 0.45, "card_size": 1.2,
		"flat": 0.6, "drop": 0.6, "stretch": Vector2(0.8, 1.9),
		"far_cell": 2.2, "far_color": Color(0.52, 0.60, 0.21), "far_squash": 1.1,
	}
	return _build_deciduous_tree("Tree_Willow", cfg, look, stage, 2)

## Ahorn — dickster Stamm, steilere, kompaktere Krone (Ei statt Schirm), große handförmig gelappte
## (PALMATE) Blätter in kräftigen Herbstfarben. ≈ 8–9 m hoch.
func _build_scene_maple(stage: int = TreeStage.MATURE) -> PackedScene:
	var cfg := {
		"trunk_height": 3.4, "trunk_radius": 0.36, "trunk_segments": 4, "trunk_bend": 0.08, "leaf_min_level": 2,
		"levels": [
			{"count": 6, "t_min": 0.45, "t_max": 0.95, "ang_min": 24.0, "ang_max": 50.0, "len_min": 0.9, "len_max": 1.3,
			 "rad_frac": 0.5, "segments": 3, "droop": 0.03, "bend": 0.14, "up_bias": 0.15},
			{"count": 4, "t_min": 0.30, "t_max": 0.95, "ang_min": 28.0, "ang_max": 55.0, "len_min": 0.45, "len_max": 0.62,
			 "rad_frac": 0.55, "segments": 2, "droop": 0.03, "bend": 0.18, "up_bias": 0.12},
			{"count": 2, "t_min": 0.40, "t_max": 0.90, "ang_min": 22.0, "ang_max": 50.0, "len_min": 0.45, "len_max": 0.6,
			 "rad_frac": 0.6, "segments": 2, "droop": 0.03, "bend": 0.18, "up_bias": 0.1},
		],
	}
	var look := {
		"bark_color": Color(0.32, 0.18, 0.08),
		"colors": [Color(0.75, 0.30, 0.08), Color(0.80, 0.45, 0.05), Color(0.65, 0.22, 0.06)],
		"shape": ProceduralTextureFactory.LeafShape.PALMATE, "hue_seed": 40, "leaf_count": 11, "aspect": 0.55,
		"sway": 1.0, "cards_per_tip": 4, "clump_radius": 0.8, "card_size": 1.6,
		"far_cell": 2.2, "far_color": Color(0.74, 0.34, 0.08),
	}
	return _build_deciduous_tree("Tree_Maple", cfg, look, stage, 3)

## Tanne — echter Nadelbaum: gerader, ≈ 13 m hoher Leittrieb mit elf Astkränzen (je 5 Äste, nach oben
## kürzer, unten leicht hängend), an jedem Ast zwei Zweige; Nadelzweig-Karten (NEEDLE) an den Enden.
## Mit snow=true zusätzlich Schneekissen auf den Astenden.
func _build_scene_pine(snow: bool, stage: int = TreeStage.MATURE) -> PackedScene:
	var cfg := {
		"trunk_height": 13.0, "trunk_radius": 0.30, "trunk_segments": 5, "trunk_bend": 0.05, "leaf_min_level": 1,
		"whorl_t_min": 0.16, "whorl_t_max": 0.97, "per_whorl": 5, "len_base": 3.4, "len_top": 0.5,
		"levels": [
			{"count": 1, "t_min": 0.0, "t_max": 1.0, "ang_min": 74.0, "ang_max": 104.0, "len_min": 1.0, "len_max": 1.0,
			 "rad_frac": 0.3, "segments": 2, "droop": 0.10, "bend": 0.08, "up_bias": 0.0},
			{"count": 2, "t_min": 0.35, "t_max": 0.95, "ang_min": 50.0, "ang_max": 70.0, "len_min": 0.30, "len_max": 0.45,
			 "rad_frac": 0.5, "segments": 2, "droop": 0.05, "bend": 0.10, "up_bias": 0.0},
		],
	}
	var look := {
		"bark_color": Color(0.35, 0.20, 0.08),
		"colors": [Color(0.08, 0.28, 0.12), Color(0.06, 0.24, 0.10), Color(0.10, 0.32, 0.14)],
		"shape": ProceduralTextureFactory.LeafShape.NEEDLE, "hue_seed": 60, "leaf_count": 12, "aspect": 0.55,
		"sway": 0.6, "cards_per_tip": 3, "clump_radius": 0.45, "card_size": 1.5, "flat": 0.45,
		"far_cell": 2.6, "far_color": Color(0.95, 0.97, 1.0) if snow else Color(0.10, 0.36, 0.12), "far_squash": 0.9,
		"snow": snow,
	}
	var s: float = TREE_STAGE_SCALE[stage]
	var skel: Dictionary = TreeSkeleton.conifer(
		cfg, s, int(PINE_STAGE_WHORLS[stage]), mini(int(TREE_STAGE_MAX_LEVEL[stage]), 2), 4000 + int(stage))
	return _assemble_tree("Tree_Pine" + ("_Snow" if snow else ""), skel, look, s, float(TREE_STAGE_CARDS[stage]))


func _build_scene_fallen(biome: String) -> PackedScene:
	var root := Node3D.new()
	root.name = "Tree_Fallen_%s" % biome.capitalize()

	var log := MeshInstance3D.new()
	log.mesh = meshes["fallen_log"]
	# Waldboden-Stämme moosen an (feucht, im Schatten liegend), Wüsten-Totholz
	# bleibt trocken/borkig — gleiche Mesh, unterschiedliche Oberfläche je Biom.
	var log_category: String = "moss" if biome == "forest" else "bark"
	log.set_surface_override_material(0, get_textured_material(Color(0.35, 0.22, 0.09), log_category))
	# Liegend: 90° um Z-Achse kippen
	log.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	root.add_child(log)

	return _pack_scene(root)

func _build_scene_cactus() -> PackedScene:
	var root := Node3D.new()
	root.name = "Cactus"

	var mat := get_material(Color(0.20, 0.55, 0.15))

	var trunk := MeshInstance3D.new()
	trunk.mesh = meshes["cactus_trunk"]
	trunk.set_surface_override_material(0, mat)
	trunk.position = Vector3(0.0, 0.8, 0.0)
	root.add_child(trunk)

	# Linker Arm
	var arm_l := MeshInstance3D.new()
	arm_l.mesh = meshes["cactus_arm"]
	arm_l.set_surface_override_material(0, mat)
	arm_l.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	arm_l.position = Vector3(-0.38, 1.0, 0.0)
	root.add_child(arm_l)

	# Rechter Arm
	var arm_r := MeshInstance3D.new()
	arm_r.mesh = meshes["cactus_arm"]
	arm_r.set_surface_override_material(0, mat)
	arm_r.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	arm_r.position = Vector3(0.38, 0.85, 0.0)
	root.add_child(arm_r)

	return _pack_scene(root)

func _build_scene_fern() -> PackedScene:
	var root := Node3D.new()
	root.name = "Fern"

	# Farn schwingt stärker als Baumkronen (leichtes Blattwerk, kein Holzkern) —
	# höherer sway_strength als der Krone-Default.
	var mat := get_swaying_material(Color(0.20, 0.60, 0.15), "grass", 1.6)

	# 4 Blätter radial angeordnet
	var leaf_positions: Array = [
		[Vector3( 0.3, 0.1,  0.0), Vector3(-30.0, 0.0, 0.0)],
		[Vector3(-0.3, 0.1,  0.0), Vector3(-30.0, 180.0, 0.0)],
		[Vector3( 0.0, 0.1,  0.3), Vector3(-30.0, 90.0, 0.0)],
		[Vector3( 0.0, 0.1, -0.3), Vector3(-30.0, -90.0, 0.0)],
	]
	for lp in leaf_positions:
		var leaf := MeshInstance3D.new()
		leaf.mesh = meshes["fern_leaf"]
		leaf.set_surface_override_material(0, mat)
		leaf.position = lp[0]
		leaf.rotation_degrees = lp[1]
		root.add_child(leaf)

	return _pack_scene(root)

# ─────────────────────────────────────────────────────────────────────────────
# Hilfsmethoden
# ─────────────────────────────────────────────────────────────────────────────

## Konvertiert PrimitiveMesh → ArrayMesh (unveränderlich, GPU-seitig cachbar).
static func _to_array_mesh(primitive: PrimitiveMesh) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, primitive.get_mesh_arrays())
	return am

## Verpackt eine Node-Hierarchie als PackedScene.
## Die root-Node muss bereits alle Kinder haben.
##
## BUGFIX (2026-09-18, "Bäume unsichtbar"): PackedScene.pack() nimmt nur Nodes
## auf, deren `owner` auf die root-Node zeigt — alle programmatisch per
## add_child() angehängten Kinder (trunk, crown, cone, ...) hatten owner=null,
## wurden also beim pack() stillschweigend verworfen. instantiate_scene() lieferte
## dadurch nur eine leere Node3D-Hülle: Entity spawnt/despawnt korrekt (die
## InteractableComponent hängt direkt an der Entity, nicht an dieser Szene),
## aber es gab nie eine sichtbare Mesh. _set_owner_recursive() setzt owner auf
## allen Nachfahren, damit pack() sie tatsächlich mit einschließt.
static func _pack_scene(root: Node) -> PackedScene:
	_set_owner_recursive(root, root)
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()  # Temp-Node freigeben — PackedScene hat den State geklont
	return scene

## Setzt `owner` rekursiv auf allen Nachfahren von `node` (node selbst ausgenommen),
## damit PackedScene.pack() die komplette Hierarchie mit einpackt.
static func _set_owner_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_set_owner_recursive(child, root)
