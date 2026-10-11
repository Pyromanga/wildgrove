class_name AnimalVisualBuilder
extends RefCounted

## AnimalVisualBuilder — Baut die prozedurale Tier-Geometrie.
##
## Erweitert aus dem ursprünglichen "Kapsel-Körper + Kugelkopf + 4 Zylinder-Beine" für
## ALLE Tierarten identisch (siehe AnimalVisualProfile-Klassenkommentar für die Motivation).
## Stateless — keine Member-Variablen.
##
## Primitive-Erzeugung (Mesh/Material/MeshInstance3D) kommt aus ProcGenShapes — gemeinsame
## Basis mit CharacterPartBuilder/NPCVisualBuilder, damit hier keine eigene Kopie von
## "Kugel/Kapsel/Box/Zylinder + Material" mehr nötig ist (Wunsch "gemeinsame Basis finden,
## damit nicht alles neu erfunden werden muss"). Das Bausystem (BuildPieceDefinition) bleibt
## bewusst eine eigene, andere Technik (SurfaceTool-Dreiecksnetze für Wände/Dächer) — dafür
## taugen Godots Primitive-Meshes nicht, siehe ProcGenShapes-Klassenkommentar.
##
## KOORDINATEN: root-lokal, Füße bei y=0, +Z = "vorne" (Kopf/Schnauze-Richtung; AnimalBase
## dreht via look_at() in die tatsächliche Laufrichtung). Rumpf liegt entlang Z (liegende
## Kapsel), nicht wie ursprünglich stehend — siehe build()-Kommentar bei body_node.

## Anteil von body_size.y, an dem die Bein-MITTE sitzt bzw. an dem die Beinoberkante liegt
## (Bein-Zylinderhöhe = body_size.y * LEG_HEIGHT_RATIO, siehe _add_legs()) — beide Werte
## teilen sich dieselben Konstanten, damit Beinoberkante und Rumpfunterkante ohne Lücke
## aneinander anschließen.
const LEG_OFFSET_Y_RATIO: float = 0.27
const LEG_HEIGHT_RATIO: float = 0.55
const LEG_TOP_RATIO: float = LEG_OFFSET_Y_RATIO + LEG_HEIGHT_RATIO * 0.5

const BODY_RADIUS_RATIO: float = 0.42
## Staucht die Rumpfhöhe (vertikal) gegenüber der Breite/Tiefe — ein reiner Kreisquerschnitt
## (unskaliert) wirkt zu wurstförmig/aufgeblasen, siehe build().
const BODY_VERTICAL_SQUASH: float = 0.82
const HEAD_RADIUS_RATIO: float = 0.40

## Wunsch "neue Shapes/Formen/Gliedmaßen für Tiere — Variationen", siehe
## AnimalVisualProfile.BodyShape-Kommentar. Gibt (Radius-Multiplikator, Längen-Multiplikator)
## für den Rumpf zurück — NORMAL = (1,1), identisch zum bisherigen Verhalten.
static func _body_shape_mults(body_shape: int) -> Vector2:
	match body_shape:
		AnimalVisualProfile.BodyShape.SLENDER:
			return Vector2(0.80, 1.20)   # schmaler, aber länger (Wolf/Fuchs/Hirsch-Statur)
		AnimalVisualProfile.BodyShape.STOCKY:
			return Vector2(1.22, 0.86)   # breiter, gedrungener (Eber/Bison-Statur)
		AnimalVisualProfile.BodyShape.ROUND:
			return Vector2(1.38, 0.74)   # fast kugelig (Igel/Schaf-Statur)
		_:
			return Vector2(1.0, 1.0)

## Analog zu _body_shape_mults(), aber (Dicke-Multiplikator, Länge-Multiplikator) für die 4
## Beine (siehe _add_legs()). NORMAL = (1,1), identisch zum bisherigen Verhalten.
static func _leg_style_mults(leg_style: int) -> Vector2:
	match leg_style:
		AnimalVisualProfile.LegStyle.THIN:
			return Vector2(0.62, 1.05)   # dünne, leicht längere Beine (Reh/Vogel-Statur)
		AnimalVisualProfile.LegStyle.THICK:
			return Vector2(1.55, 0.92)   # massive, etwas kürzere Beine (Bär/Bison-Statur)
		AnimalVisualProfile.LegStyle.SHORT:
			return Vector2(1.08, 0.55)   # kurze, stämmige Beine (Dachs/Igel-Statur)
		AnimalVisualProfile.LegStyle.LONG:
			return Vector2(0.82, 1.5)    # lange, schlanke Beine (Elch/Pferd-Statur)
		_:
			return Vector2(1.0, 1.0)

## Baut die Geometrie für EIN Tier gemäß profile.body_plan. Gibt einen Node3D ("Visuals")
## zurück, der direkt per add_child() an das Tier gehängt werden kann.
##
## Wunsch "mehr Körper für Tiere einbauen — Insekten, Spinnen, Schlangen, Fische, aber auch
## große Säugetiere": QUADRUPED (unverändert, Default) deckt jetzt zusätzlich "große
## Säugetiere" über BackStyle (Schulterbuckel/Mähne) statt eines eigenen Bauplans ab — ein
## Bär/Elch ist anatomisch immer noch ein Vierbeiner, nur mit anderen Proportionen/
## Rückenmerkmal, braucht also keine neue Anatomie. INSECT/SPIDER/SNAKE/FISH sind dagegen
## strukturell etwas anderes (Segmentierung, Beinzahl, keine Beine) und bekommen je eine
## eigene _build_*()-Funktion, dispatched über body_plan.
static func build(profile: AnimalVisualProfile) -> Node3D:
	match profile.body_plan:
		AnimalVisualProfile.BodyPlan.INSECT:
			return _build_insect(profile)
		AnimalVisualProfile.BodyPlan.SPIDER:
			return _build_spider(profile)
		AnimalVisualProfile.BodyPlan.SNAKE:
			return _build_snake(profile)
		AnimalVisualProfile.BodyPlan.FISH:
			return _build_fish(profile)
		_:
			return _build_quadruped(profile)

## Baut Rumpf + Kopf (mit Augen/Schnauze/Ohren/Kopfschmuck je Profil) + 4 Beine + optionalem
## Schwanz/Rückenmerkmal. Der bisherige, unveränderte "Standardtier"-Bauplan.
static func _build_quadruped(profile: AnimalVisualProfile) -> Node3D:
	var root := Node3D.new()
	root.name = "Visuals"

	var bs: Vector3 = profile.body_size
	var color: Color = profile.color
	# Wunsch "Textur von Tieren": NUR der Rumpf bekommt bei gesetztem pattern_style die
	# prozedurale Musterfläche (siehe _build_body_material()) — Kopf bleibt bewusst einfarbig
	# (eigene, kleinere Fläche; ein Muster würde auf der Kopfkugel kaum lesbar und die
	# Naht Body/Head bei abweichender UV-Zuordnung sichtbar machen).
	var body_mat := _build_body_material(profile)
	var head_mat := ProcGenShapes.mat(color.lightened(0.1))
	var leg_mat := ProcGenShapes.mat(color.darkened(0.2))
	# Für Nase/Nasenspitze/Hufansatz — ein deutlich dunklerer Akzent, unabhängig von der
	# eigentlichen Fellfarbe des Tieres (reale Tiere haben fast immer eine dunkle Nase,
	# unabhängig vom Fellton).
	var accent_mat := ProcGenShapes.mat(color.darkened(0.55), 0.7)

	_add_legs(root, leg_mat, bs, profile.leg_style)

	# leg_mult.y (Längen-Multiplikator, siehe _leg_style_mults()) MUSS auch hier einfließen,
	# nicht nur in _add_legs(): sonst würde z.B. LegStyle.LONG zwar längere Beinmodelle
	# zeichnen, der Rumpf aber auf der alten (für normallange Beine berechneten) Höhe
	# hängen bleiben — entweder in der Luft schwebend (SHORT) oder von den Beinen
	# durchstoßen (LONG). _add_legs() skaliert den Bein-Ansatzpunkt (LEG_OFFSET_Y_RATIO)
	# um denselben Faktor, LEG_TOP_RATIO folgt deshalb hier identisch mit.
	var leg_top: float = bs.y * LEG_TOP_RATIO * _leg_style_mults(profile.leg_style).y
	var body_radius: float = bs.x * BODY_RADIUS_RATIO
	# Körperlänge (Nase-Schwanz-Richtung): body_size.z war bisher nur der Bein-Z-Versatz,
	# nie eine echte Rumpflänge (der alte Rumpf war eine STEHENDE Kapsel ohne Länge). Hier
	# wird z zusätzlich als Längenfaktor benutzt, ohne dass Unterklassen ihre body_size
	# ändern müssen — ein Vielfaches von z ergibt einen plausibel länglichen statt runden
	# Rumpf, größere Tiere (großes z) werden automatisch proportional länger.
	var body_length: float = maxf(bs.z * 2.2, body_radius * 2.0 + 0.1)

	# Wunsch "neue Shapes/Formen für Tiere — Variationen": NACH der obigen Grund-Berechnung
	# angewendet (nicht direkt auf bs), damit die Kollisionskapsel (AnimalBase._body_size)
	# komplett unberührt bleibt — rein kosmetisch, siehe BodyShape-Feldkommentar.
	var body_shape_mult := _body_shape_mults(profile.body_shape)
	body_radius *= body_shape_mult.x
	body_length *= body_shape_mult.y
	var body_center_y: float = leg_top + body_radius * BODY_VERTICAL_SQUASH * 0.85

	var body_node := ProcGenShapes.mi(
		ProcGenShapes.capsule(body_radius, body_length), body_mat, Vector3(0.0, body_center_y, 0.0), "Body"
	)
	# CapsuleMesh liegt standardmäßig AUFRECHT (Länge entlang lokal Y) — das war exakt das
	# Problem des alten Modells ("stehende Pille" statt Tierkörper). 90°-Drehung um X legt
	# die Länge auf die Z-Achse (vorne/hinten); scale.z (= die ehemalige Mesh-Y-Achse vor der
	# Drehung, landet nach der Drehung auf der vertikalen Weltachse) staucht danach die
	# Rumpfhöhe leicht — siehe BODY_VERTICAL_SQUASH.
	body_node.rotation.x = PI * 0.5
	body_node.scale = Vector3(1.0, 1.0, BODY_VERTICAL_SQUASH)
	root.add_child(body_node)

	var head_r: float = bs.x * HEAD_RADIUS_RATIO
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, body_center_y + head_r * 0.35, body_length * 0.5 - head_r * 0.2)
	root.add_child(head)
	head.add_child(ProcGenShapes.mi(ProcGenShapes.sphere(head_r), head_mat, Vector3.ZERO, "Skull"))

	_add_eyes(head, head_r)
	_add_snout(head, profile, head_r, head_mat, accent_mat)
	_add_ears(head, profile, head_r, head_mat)
	_add_headgear(head, profile, head_r)
	_add_tail(root, profile, leg_mat, body_center_y, body_length, body_radius)
	_add_back_feature(root, profile, body_center_y, body_length, body_radius)

	return root

# ─────────────────────────────────────────────
# Rumpf-Material / prozedurale Textur (Wunsch "Textur von Tieren")
# ─────────────────────────────────────────────

## Auflösung der generierten Musterfläche — klein gehalten (keine Foto-Textur, nur grobe
# Streifen/Flecken/Flächen auf stilisierter Low-Poly-Geometrie): billig genug, um sie pro
## gespawnter Instanz neu zu erzeugen (siehe Funktionskommentar unten), ohne spürbare Kosten
## beim Chunk-Laden, aber fein genug, dass Streifen/Flecken nicht blockig wirken.
const PATTERN_TEX_WIDTH  := 48
const PATTERN_TEX_HEIGHT := 24

## Baut das Rumpf-Material — bei PatternStyle.NONE schlicht einfarbig (ProcGenShapes.mat(),
## bisheriges Verhalten), sonst eine klein aufgelöste, PROZEDURAL ERZEUGTE Textur (Image +
## ImageTexture zur Laufzeit zusammengesetzt, KEINE externe Bilddatei/keine .png im Projekt
## nötig — passt damit zur restlichen Codebase, die Geometrie ebenfalls rein prozedural aus
## Godot-Primitiven baut statt aus importierten Meshes). Wird auf CapsuleMesh.albedo_texture
## gelegt; albedo_color bleibt bewusst WEISS, damit die im Bild bereits fest eingebackenen
## Grund-/Musterfarben unverfälscht durchkommen (sonst würde StandardMaterial3D albedo_color
## MIT der Textur multiplizieren und beide Farben gemeinsam verdunkeln/verfälschen).
## Kosten: eine neue Image/ImageTexture-Instanz PRO TIER MIT MUSTER (kein Caching über
## mehrere Instanzen derselben Art) — bei ~1150 Pixeln (48×24) und nur beim Spawnen (nicht
## pro Frame) vernachlässigbar; Caching wäre Optimierung ohne aktuell gemessenes Problem.
static func _build_body_material(profile: AnimalVisualProfile) -> StandardMaterial3D:
	if profile.pattern_style == AnimalVisualProfile.PatternStyle.NONE:
		return ProcGenShapes.mat(profile.color)

	var img := Image.create(PATTERN_TEX_WIDTH, PATTERN_TEX_HEIGHT, false, Image.FORMAT_RGB8)
	for y in PATTERN_TEX_HEIGHT:
		var v: float = float(y) / float(PATTERN_TEX_HEIGHT - 1)
		for x in PATTERN_TEX_WIDTH:
			var u: float = float(x) / float(PATTERN_TEX_WIDTH - 1)
			var use_pattern_color := _pattern_mask(u, v, profile.pattern_style)
			img.set_pixel(x, y, profile.pattern_color if use_pattern_color else profile.color)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.85
	return mat

## u = rund um den Rumpfumfang (CapsuleMesh-UV, 0..1), v = entlang der Rumpflänge (0..1).
## Rein deterministisch (kein echter Zufall) — dieselbe species_id erzeugt IMMER dieselbe
## Musterfläche, nur Farbe/Proportion variiert über profile.color/body_size wie gehabt.
static func _pattern_mask(u: float, v: float, pattern_style: int) -> bool:
	match pattern_style:
		AnimalVisualProfile.PatternStyle.STRIPES:
			# Schräge Streifen (leichter v-Versatz) statt rein senkrecht — wirkt organischer
			# als exakt vertikale Linien (die auf einer Kapsel schnell wie ein Barcode wirken).
			var stripe_count := 7.0
			return fposmod(u * stripe_count + v * 0.8, 1.0) < 0.4
		AnimalVisualProfile.PatternStyle.SPOTS:
			# Grob gerastertes Punktgitter, pro Zelle leicht (deterministisch) verschoben —
			# sieht weniger mechanisch aus als exakt zentrierte Kreise im Raster.
			var cell := 0.17
			var cx: float = floor(u / cell)
			var cy: float = floor(v / cell)
			var jx: float = _hash2(cx, cy)
			var jy: float = _hash2(cx + 11.0, cy + 29.0)
			var center_u: float = (cx + 0.3 + jx * 0.4) * cell
			var center_v: float = (cy + 0.3 + jy * 0.4) * cell
			return Vector2(u - center_u, v - center_v).length() < cell * 0.32
		AnimalVisualProfile.PatternStyle.PATCHES:
			# Großflächige, unregelmäßige Flecken (Kuh/Panda-artig) über überlagerte
			# Sinuswellen statt eines echten Noise-Moduls — für diese kleine Auflösung
			# optisch nicht von FastNoiseLite zu unterscheiden, aber ohne zusätzliche
			# Noise-Instanz pro Tier.
			var n: float = sin(u * 9.1 + 1.3) * cos(v * 6.4 + 0.5) + sin(u * 4.0 - v * 5.3 + 2.1) * 0.6
			return n > 0.35
		_:
			return false

## Klassischer GLSL-Style-Pseudozufalls-Hash, nach float gemappt — deterministisch (gleiche
## a/b -> immer derselbe Wert), reicht für die Zellen-Jitter oben völlig aus, keine echte
## Zufallsquelle (RandomNumberGenerator) nötig/gewünscht (siehe _pattern_mask()-Kommentar).
static func _hash2(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)

# ─────────────────────────────────────────────
# Beine
# ─────────────────────────────────────────────

static func _add_legs(root: Node3D, leg_mat: Material, bs: Vector3, leg_style: int = AnimalVisualProfile.LegStyle.NORMAL) -> void:
	# Wunsch "neue Gliedmaßen für Tiere — Variationen": leg_style skaliert nur die
	# MESH-Dicke/-Länge (siehe _leg_style_mults()) — die vier Ansatzpunkte (offsets) bleiben
	# bewusst UNVERÄNDERT an der rohen body_size (bs) ausgerichtet, sonst würde z.B. LONG
	# die Beine auch seitlich auseinanderschieben statt nur zu verlängern, was bei den
	# Standbreiten mancher Tiere unnatürlich breitbeinig wirken würde.
	var leg_mult := _leg_style_mults(leg_style)
	var leg_height: float = bs.y * LEG_HEIGHT_RATIO * leg_mult.y
	# Eine Mesh-Resource für alle vier Beine geteilt (identische Geometrie) — die vier
	# MeshInstance3D-Knoten unterscheiden sich nur in Position/Name, nicht in der Form.
	var mesh := ProcGenShapes.cylinder(bs.x * 0.085 * leg_mult.x, bs.x * 0.065 * leg_mult.x, leg_height)
	var offsets: Array[Vector3] = [
		Vector3(-bs.x * 0.3, 0.0, -bs.z * 0.22),
		Vector3( bs.x * 0.3, 0.0, -bs.z * 0.22),
		Vector3(-bs.x * 0.3, 0.0,  bs.z * 0.22),
		Vector3( bs.x * 0.3, 0.0,  bs.z * 0.22),
	]
	var names: Array[String] = ["LegFL", "LegFR", "LegBL", "LegBR"]
	# Der Y-Ansatzpunkt skaliert mit demselben leg_mult.y wie die Bein-Länge selbst (die
	# Füße bleiben so immer bei y=0 auf dem Boden, egal wie lang das Bein ist) — build()
	# spiegelt genau diese Skalierung bei der Berechnung von leg_top/body_center_y, siehe
	# dortiger Kommentar.
	var leg_offset_y: float = bs.y * LEG_OFFSET_Y_RATIO * leg_mult.y
	for i in offsets.size():
		var pos: Vector3 = offsets[i] + Vector3(0.0, leg_offset_y, 0.0)
		root.add_child(ProcGenShapes.mi(mesh, leg_mat, pos, names[i]))

# ─────────────────────────────────────────────
# Gesicht (Kind der "Head"-Gruppe, lokal relativ zu deren Ursprung = Kopfmitte)
# ─────────────────────────────────────────────

static func _add_eyes(head: Node3D, head_r: float) -> void:
	var eye_mat := ProcGenShapes.mat(Color(0.05, 0.05, 0.06), 0.25)
	var eye_mesh := ProcGenShapes.sphere(head_r * 0.13)
	for side in [1.0, -1.0]:
		var eye := ProcGenShapes.mi(eye_mesh, eye_mat, Vector3.ZERO, "EyeR" if side > 0.0 else "EyeL")
		ProcGenShapes.place_on_sphere(eye, head_r, side * head_r * 0.62, head_r * 0.10, head_r * 0.06, Vector3(1.0, 1.0, 0.6))
		head.add_child(eye)

static func _add_snout(head: Node3D, profile: AnimalVisualProfile, head_r: float, head_mat: Material, accent_mat: Material) -> void:
	match profile.snout_style:
		AnimalVisualProfile.SnoutStyle.SHORT:
			var nose := ProcGenShapes.mi(ProcGenShapes.sphere(head_r * 0.22), accent_mat, Vector3.ZERO, "Nose")
			ProcGenShapes.place_on_sphere(nose, head_r, 0.0, -head_r * 0.15, head_r * 0.30, Vector3(1.0, 0.8, 0.7))
			head.add_child(nose)
		AnimalVisualProfile.SnoutStyle.LONG:
			# Schnauze setzt bewusst weit INNERHALB der Schädelkugel an (anchor nahe am
			# Zentrum statt exakt auf der Oberfläche) — sonst entstünde eine sichtbare
			# Nahtlücke zwischen Kugel und Kapsel, da ProcGenShapes.spike() vom Ansatzpunkt
			# aus gerade nach `dir` weiterbaut statt sich der Kugelkrümmung anzuschmiegen.
			var muzzle_dir := Vector3(0.0, -0.12, 1.0).normalized()
			var muzzle_len := head_r * 0.85
			var anchor := Vector3(0.0, -head_r * 0.08, head_r * 0.35)
			head.add_child(ProcGenShapes.spike(
				ProcGenShapes.capsule(head_r * 0.26, muzzle_len), head_mat, anchor, muzzle_dir, muzzle_len, "Muzzle"
			))
			var nose := ProcGenShapes.mi(ProcGenShapes.sphere(head_r * 0.16), accent_mat, anchor + muzzle_dir * muzzle_len, "Nose")
			head.add_child(nose)
		_:
			pass

static func _add_ears(head: Node3D, profile: AnimalVisualProfile, head_r: float, head_mat: Material) -> void:
	match profile.ear_style:
		AnimalVisualProfile.EarStyle.ROUND:
			var mesh := ProcGenShapes.sphere(head_r * 0.30)
			for side in [1.0, -1.0]:
				var ear := ProcGenShapes.mi(mesh, head_mat, Vector3.ZERO, "EarR" if side > 0.0 else "EarL")
				ProcGenShapes.place_on_sphere(ear, head_r, side * head_r * 0.62, head_r * 0.58, head_r * 0.05, Vector3(0.65, 1.0, 0.5))
				head.add_child(ear)
		AnimalVisualProfile.EarStyle.POINTY:
			var mesh := ProcGenShapes.cone(head_r * 0.20, head_r * 0.6)
			for side in [1.0, -1.0]:
				var anchor := Vector3(side * head_r * 0.42, head_r * 0.45, -head_r * 0.05)
				var dir := Vector3(side * 0.45, 1.0, -0.15).normalized()
				head.add_child(ProcGenShapes.spike(mesh, head_mat, anchor, dir, head_r * 0.6, "EarR" if side > 0.0 else "EarL"))
		AnimalVisualProfile.EarStyle.LONG:
			var mesh := ProcGenShapes.capsule(head_r * 0.14, head_r * 1.7)
			for side in [1.0, -1.0]:
				var anchor := Vector3(side * head_r * 0.30, head_r * 0.45, -head_r * 0.05)
				var dir := Vector3(side * 0.16, 1.0, -0.05).normalized()
				head.add_child(ProcGenShapes.spike(mesh, head_mat, anchor, dir, head_r * 1.7, "EarR" if side > 0.0 else "EarL"))
		AnimalVisualProfile.EarStyle.FLOPPY:
			var mesh := ProcGenShapes.capsule(head_r * 0.17, head_r * 0.95)
			for side in [1.0, -1.0]:
				var anchor := Vector3(side * head_r * 0.68, head_r * 0.15, 0.0)
				var dir := Vector3(side * 0.35, -1.0, 0.1).normalized()
				head.add_child(ProcGenShapes.spike(mesh, head_mat, anchor, dir, head_r * 0.95, "EarR" if side > 0.0 else "EarL"))
		_:
			pass

## Geweih (Reh) bzw. Hauer (Wildschwein) — bewusst NICHT von der Fellfarbe abgeleitet
## (Knochen-/Elfenbeinfarbe ist unabhängig vom Fell), siehe jeweilige Konstante unten.
static func _add_headgear(head: Node3D, profile: AnimalVisualProfile, head_r: float) -> void:
	match profile.headgear_style:
		AnimalVisualProfile.HeadgearStyle.ANTLERS:
			var antler_mat := ProcGenShapes.mat(Color(0.55, 0.45, 0.33), 0.9)
			var beam_mesh := ProcGenShapes.cylinder(head_r * 0.045, head_r * 0.09, head_r * 1.3)
			var tine_mesh := ProcGenShapes.cone(head_r * 0.05, head_r * 0.45)
			for side in [1.0, -1.0]:
				var anchor := Vector3(side * head_r * 0.32, head_r * 0.5, -head_r * 0.1)
				var beam_dir := Vector3(side * 0.25, 1.0, -0.3).normalized()
				var beam_name := "AntlerR" if side > 0.0 else "AntlerL"
				head.add_child(ProcGenShapes.spike(beam_mesh, antler_mat, anchor, beam_dir, head_r * 1.3, beam_name))
				var tine_anchor: Vector3 = anchor + beam_dir * (head_r * 1.3 * 0.55)
				var tine_dir := (beam_dir + Vector3(side * 0.7, 0.25, -0.15)).normalized()
				head.add_child(ProcGenShapes.spike(tine_mesh, antler_mat, tine_anchor, tine_dir, head_r * 0.45, beam_name + "Tine"))
		AnimalVisualProfile.HeadgearStyle.TUSKS:
			var tusk_mat := ProcGenShapes.mat(Color(0.92, 0.90, 0.82), 0.4)
			var mesh := ProcGenShapes.cone(head_r * 0.09, head_r * 0.35)
			for side in [1.0, -1.0]:
				var anchor := Vector3(side * head_r * 0.30, -head_r * 0.25, head_r * 0.65)
				var dir := Vector3(side * 0.5, 0.7, 0.3).normalized()
				head.add_child(ProcGenShapes.spike(mesh, tusk_mat, anchor, dir, head_r * 0.35, "TuskR" if side > 0.0 else "TuskL"))
		AnimalVisualProfile.HeadgearStyle.HORNS:
			# BUGFIX ("die Tiere sehen alle gleich aus"): HORNS (Ziege/Steinbock/Gazelle/
			# Antilope) stand im Enum und in AnimalSpeciesDB, wurde hier aber nie gezeichnet —
			# diese Tiere hatten KEINEN Kopfschmuck. Zwei Segmente je Seite (Wurzel nach
			# oben/außen, Spitze nach hinten gebogen): ein einzelner gerader Kegel läse sich
			# wie ein Ohr oder eine Antenne, nicht wie ein Horn.
			var horn_mat := ProcGenShapes.mat(Color(0.80, 0.74, 0.60), 0.55)
			var root_len: float = head_r * 0.75
			var tip_len: float = head_r * 0.6
			var root_mesh := ProcGenShapes.cylinder(head_r * 0.07, head_r * 0.13, root_len)
			var tip_mesh := ProcGenShapes.cone(head_r * 0.07, tip_len)
			for side in [1.0, -1.0]:
				var anchor := Vector3(side * head_r * 0.30, head_r * 0.50, -head_r * 0.05)
				var root_dir := Vector3(side * 0.30, 1.0, -0.30).normalized()
				var horn_name := "HornR" if side > 0.0 else "HornL"
				head.add_child(ProcGenShapes.spike(root_mesh, horn_mat, anchor, root_dir, root_len, horn_name))
				var tip_anchor: Vector3 = anchor + root_dir * root_len
				var tip_dir := Vector3(side * 0.35, 0.35, -1.0).normalized()
				head.add_child(ProcGenShapes.spike(tip_mesh, horn_mat, tip_anchor, tip_dir, tip_len, horn_name + "Tip"))
		AnimalVisualProfile.HeadgearStyle.BROAD_ANTLERS:
			# Schaufelgeweih (Elch): fast waagerechter Stiel nach außen, daran eine große,
			# flache Schaufel mit drei Sprossen am Außenrand. Gleicher Knochenton wie ANTLERS.
			var antler_mat := ProcGenShapes.mat(Color(0.55, 0.45, 0.33), 0.9)
			var beam_len: float = head_r * 0.9
			var beam_mesh := ProcGenShapes.cylinder(head_r * 0.07, head_r * 0.11, beam_len)
			var palm_mesh := ProcGenShapes.sphere(head_r * 0.62)
			var tine_len: float = head_r * 0.5
			var tine_mesh := ProcGenShapes.cone(head_r * 0.07, tine_len)
			for side in [1.0, -1.0]:
				var anchor := Vector3(side * head_r * 0.30, head_r * 0.45, -head_r * 0.08)
				var beam_dir := Vector3(side * 1.0, 0.35, -0.1).normalized()
				var antler_name := "AntlerR" if side > 0.0 else "AntlerL"
				head.add_child(ProcGenShapes.spike(beam_mesh, antler_mat, anchor, beam_dir, beam_len, antler_name))
				var palm_pos: Vector3 = anchor + beam_dir * (beam_len + head_r * 0.30)
				var palm := ProcGenShapes.mi(palm_mesh, antler_mat, palm_pos, antler_name + "Palm")
				palm.scale = Vector3(1.0, 0.14, 0.85)
				head.add_child(palm)
				for k in 3:
					var spread: float = float(k) - 1.0
					var tine_anchor: Vector3 = palm_pos + Vector3(side * head_r * 0.40, 0.0, spread * head_r * 0.36)
					var tine_dir := Vector3(side * 0.35, 1.0, spread * 0.25).normalized()
					head.add_child(ProcGenShapes.spike(tine_mesh, antler_mat, tine_anchor, tine_dir, tine_len, "%sTine%d" % [antler_name, k]))
		_:
			pass

# ─────────────────────────────────────────────
# Rückenmerkmal (große Säugetiere: Schulterbuckel/Mähne) — Kind von root
# ─────────────────────────────────────────────

## HUMP (Bär/Elch/Bison: massiger Schulterbuckel, vorne über den Vorderbeinen) bzw. MANE
## (Wolf: niedriger Nackenkamm vom Kopfansatz bis Rumpfmitte) — rein additiv zum Rumpf,
## beeinflusst body_radius/body_length selbst nicht (dieselbe Trennung "Kosmetik ändert nie
## die tragende Geometrie" wie bei Kopfschmuck, siehe _add_headgear()-Kommentar).
static func _add_back_feature(
	root: Node3D, profile: AnimalVisualProfile,
	body_center_y: float, body_length: float, body_radius: float
) -> void:
	match profile.back_style:
		AnimalVisualProfile.BackStyle.HUMP:
			var hump_mat := ProcGenShapes.mat(profile.color.darkened(0.08))
			var hump_r := body_radius * 0.62
			var pos := Vector3(0.0, body_center_y + body_radius * 0.55, body_length * 0.18)
			root.add_child(ProcGenShapes.mi(ProcGenShapes.sphere(hump_r), hump_mat, pos, "BackHump"))
		AnimalVisualProfile.BackStyle.MANE:
			var mane_mat := ProcGenShapes.mat(profile.color.darkened(0.35), 0.95)
			var count := 5
			for i in count:
				var t: float = float(i) / float(count - 1)  # 0 = Kopfansatz, 1 = Rumpfmitte
				var z: float = body_length * 0.5 * (1.0 - t * 0.9)
				var mesh := ProcGenShapes.cone(body_radius * 0.16, body_radius * 0.5)
				var pos := Vector3(0.0, body_center_y + body_radius * 0.85, z)
				var node := ProcGenShapes.mi(mesh, mane_mat, pos, "Mane%d" % i)
				node.rotation.x = PI  # Spitze nach unten, Basis oben am Rücken
				root.add_child(node)
		_:
			pass

# ─────────────────────────────────────────────
# Schwanz (Kind von root, am Rumpf-Heck)
# ─────────────────────────────────────────────

static func _add_tail(
	root: Node3D, profile: AnimalVisualProfile, leg_mat: Material,
	body_center_y: float, body_length: float, body_radius: float
) -> void:
	var scale: float = profile.tail_scale
	# Ansatzpunkt liegt absichtlich etwas INNERHALB der hinteren Rumpfkuppe (0.7 statt 1.0),
	# damit Schwanz und Rumpf ohne sichtbare Naht ineinander übergehen — gleiches Prinzip
	# wie beim Schnauzenansatz in _add_snout().
	var anchor := Vector3(0.0, body_center_y, -body_length * 0.5 * 0.7)
	match profile.tail_style:
		AnimalVisualProfile.TailStyle.STUB:
			var length: float = body_radius * 0.6 * scale
			var mesh := ProcGenShapes.capsule(body_radius * 0.22 * scale, length)
			var dir := Vector3(0.0, 0.35, -1.0).normalized()
			root.add_child(ProcGenShapes.spike(mesh, leg_mat, anchor, dir, length, "Tail"))
		AnimalVisualProfile.TailStyle.BUSHY:
			var length: float = body_radius * 1.3 * scale
			var mesh := ProcGenShapes.cone(body_radius * 0.34 * scale, length)
			var dir := Vector3(0.0, 0.55, -1.0).normalized()
			root.add_child(ProcGenShapes.spike(mesh, leg_mat, anchor, dir, length, "Tail"))
		AnimalVisualProfile.TailStyle.FLUFFY:
			# Kein spike() nötig (Kugel ist richtungslos symmetrisch) — reine
			# "Puschelschwanz"-Optik, bewusst naturfarben statt fellfarbig (siehe
			# Klassenkommentar von _add_headgear() für dasselbe Prinzip bei Hörnern).
			var puff_mat := ProcGenShapes.mat(Color(0.95, 0.95, 0.92), 0.7)
			var pos: Vector3 = anchor + Vector3(0.0, body_radius * 0.15, -body_radius * 0.35) * scale
			root.add_child(ProcGenShapes.mi(ProcGenShapes.sphere(body_radius * 0.30 * scale), puff_mat, pos, "Tail"))
		AnimalVisualProfile.TailStyle.THIN:
			# Langer, dünner, nackter Schwanz (Maus/Ratte) — bewusst rosa statt fellfarbig:
			# genau das unterscheidet ihn auf den ersten Blick vom Stummel-/Puschelschwanz.
			var length: float = body_radius * 2.6 * scale
			var mesh := ProcGenShapes.capsule(body_radius * 0.07 * scale, length)
			var tail_mat := ProcGenShapes.mat(Color(0.80, 0.64, 0.60), 0.8)
			var dir := Vector3(0.0, 0.12, -1.0).normalized()
			root.add_child(ProcGenShapes.spike(mesh, tail_mat, anchor, dir, length, "Tail"))
		_:
			pass

# ─────────────────────────────────────────────
# Insekt (Biene/Käfer/Libelle) — Kopf + Brustabschnitt + Hinterleib, 6 dünne Beine,
# optionale Flügel/Fühler. Kein Bezug zu den Quadruped-Helfern oben (Ohren/Schnauze/
# Kopfschmuck/Schwanz ergeben für Insekten keinen Sinn, siehe BodyPlan-Kommentar).
# ─────────────────────────────────────────────

static func _build_insect(profile: AnimalVisualProfile) -> Node3D:
	var root := Node3D.new()
	root.name = "Visuals"

	var bs: Vector3 = profile.body_size
	var color: Color = profile.color
	var body_mat := ProcGenShapes.mat(color)
	var head_mat := ProcGenShapes.mat(color.darkened(0.15))
	var leg_mat := ProcGenShapes.mat(color.darkened(0.4), 0.6)

	var thorax_r: float = bs.x * 0.5
	var abdomen_r: float = bs.x * 0.62
	var ground_y: float = bs.y  # Insekten stehen auf sehr kurzen Beinen -> Rumpf sitzt nahe body_size.y

	# Hinterleib (hinten, meist der größte Teil) → Brustabschnitt (Mitte, trägt Beine/
	# Flügel) → Kopf (vorne). Alle drei entlang Z aneinandergereiht, kein Zwischenraum.
	# body_size.z wurde hier bisher ignoriert — eine Libelle (z = 0.26) sah deshalb aus wie
	# eine Wespe. Jetzt streckt ein z/x-Verhältnis über ~1.33 den Hinterleib in die Länge
	# (stretch = 1.0 bei allen kompakten Insekten, also unverändert für Käfer/Wespe/Ameise).
	var stretch: float = maxf(1.0, bs.z / bs.x * 0.75)
	var abdomen_pos := Vector3(0.0, ground_y, -abdomen_r * (0.3 + 0.6 * stretch))
	var abdomen := ProcGenShapes.mi(ProcGenShapes.sphere(abdomen_r), body_mat, abdomen_pos, "Abdomen")
	abdomen.scale = Vector3(1.0, 1.0, stretch)
	root.add_child(abdomen)

	var thorax_pos := Vector3(0.0, ground_y, abdomen_r * 0.15)
	root.add_child(ProcGenShapes.mi(ProcGenShapes.sphere(thorax_r), body_mat, thorax_pos, "Thorax"))

	var head_r: float = bs.x * 0.34
	var head_pos := Vector3(0.0, ground_y, thorax_r + head_r * 0.75)
	var head := ProcGenShapes.mi(ProcGenShapes.sphere(head_r), head_mat, head_pos, "Head")
	root.add_child(head)

	# Facettenaugen — größer/dunkler als die Punktaugen der Vierbeiner, seitlich am Kopf.
	var eye_mat := ProcGenShapes.mat(Color(0.05, 0.05, 0.08), 0.15)
	for side in [1.0, -1.0]:
		var eye := ProcGenShapes.mi(ProcGenShapes.sphere(head_r * 0.35), eye_mat, Vector3.ZERO, "EyeR" if side > 0.0 else "EyeL")
		ProcGenShapes.place_on_sphere(eye, head_r, side * head_r * 0.55, head_r * 0.15, head_r * 0.12, Vector3(0.8, 1.0, 0.8))
		head.add_child(eye)

	# Fühler — zwei dünne, leicht nach vorne/außen geknickte Spikes ab Kopfoberseite.
	var antenna_mesh := ProcGenShapes.cylinder(head_r * 0.02, head_r * 0.06, head_r * 1.4)
	for side in [1.0, -1.0]:
		var anchor := Vector3(side * head_r * 0.3, head_r * 0.55, thorax_r + head_r * 0.4)
		var dir := Vector3(side * 0.4, 0.7, 0.5).normalized()
		root.add_child(ProcGenShapes.spike(antenna_mesh, leg_mat, anchor, dir, head_r * 1.4, "AntennaR" if side > 0.0 else "AntennaL"))

	# 6 Beine: drei Paare, dünner und steiler als beim Vierbeiner, alle am Brustabschnitt.
	var leg_mesh := ProcGenShapes.cylinder(bs.x * 0.025, bs.x * 0.04, ground_y * 0.75)
	var leg_zs: Array[float] = [thorax_r * 0.6, 0.0, -thorax_r * 0.5]
	var leg_names: Array[String] = ["Front", "Mid", "Rear"]
	for i in leg_zs.size():
		for side in [1.0, -1.0]:
			var anchor := Vector3(side * thorax_r * 0.75, ground_y * 0.85, leg_zs[i])
			var dir := Vector3(side * 0.55, -1.0, 0.0).normalized()
			var node_name := "Leg%s%s" % [leg_names[i], "R" if side > 0.0 else "L"]
			root.add_child(ProcGenShapes.spike(leg_mesh, leg_mat, anchor, dir, ground_y * 0.75, node_name))

	_add_wings(root, profile, thorax_pos, thorax_r)
	_add_insect_accent(root, profile, thorax_pos, thorax_r, abdomen_pos, abdomen_r, stretch)

	return root

## Zeichnung auf Deckflügeln/Hinterleib (AccentStyle.SPOTS/STRIPES) — der Unterschied
## zwischen Käfer und Marienkäfer bzw. Wespe und Biene war bisher nur die Grundfarbe.
static func _add_insect_accent(
	root: Node3D, profile: AnimalVisualProfile, thorax_pos: Vector3, thorax_r: float,
	abdomen_pos: Vector3, abdomen_r: float, stretch: float
) -> void:
	match profile.accent_style:
		AnimalVisualProfile.AccentStyle.SPOTS:
			# Punkte sitzen auf den Deckflügeln (siehe _add_wings(), SHELL) — ohne die
			# gäbe es nichts, worauf sie sitzen könnten.
			if profile.wing_style != AnimalVisualProfile.WingStyle.SHELL:
				return
			var spot_mat := ProcGenShapes.mat(Color(0.06, 0.05, 0.05), 0.5)
			var spot_mesh := ProcGenShapes.sphere(thorax_r * 0.13)
			var zs: Array[float] = [-0.55, -0.30, -0.05]
			for i in zs.size():
				for side in [1.0, -1.0]:
					var pos: Vector3 = thorax_pos + Vector3(side * thorax_r * 0.40, thorax_r * 0.66, zs[i] * thorax_r)
					root.add_child(ProcGenShapes.mi(spot_mesh, spot_mat, pos, "Spot%d%s" % [i, "R" if side > 0.0 else "L"]))
		AnimalVisualProfile.AccentStyle.STRIPES:
			# Dunkle Ringe um den Hinterleib: flache Scheiben, deren Radius dem Querschnitt
			# des (ggf. gestreckten) Ellipsoids an der jeweiligen Stelle +4 % entspricht —
			# so ragt nur der Rand als Band heraus, statt eine überstehende Platte zu bilden.
			var band_mat := ProcGenShapes.mat(Color(0.08, 0.07, 0.05), 0.6)
			var offsets: Array[float] = [-0.45, 0.0, 0.45]
			for i in offsets.size():
				var e: float = offsets[i]
				var ring_r: float = abdomen_r * sqrt(maxf(1.0 - e * e, 0.01)) * 1.04
				var pos: Vector3 = abdomen_pos + Vector3(0.0, 0.0, e * abdomen_r * stretch)
				var band := ProcGenShapes.mi(ProcGenShapes.sphere(ring_r), band_mat, pos, "Band%d" % i)
				band.scale = Vector3(1.0, 1.0, 0.22)
				root.add_child(band)
		_:
			pass

## Flügelpaar für BodyPlan.INSECT — am Brustabschnitt angesetzt, flach nach hinten/außen
## ausgerichtet. TRANSLUCENT (Biene/Libelle: schmal, halbdurchsichtig), SHELL (Käfer: kurze,
## feste Deckflügel), BROAD (Schmetterling: große, auffällige Flügel).
static func _add_wings(root: Node3D, profile: AnimalVisualProfile, thorax_pos: Vector3, thorax_r: float) -> void:
	match profile.wing_style:
		AnimalVisualProfile.WingStyle.TRANSLUCENT:
			var wing_mat := ProcGenShapes.mat(Color(0.9, 0.95, 1.0, 0.35), 0.2)
			# ProcGenShapes.mat() setzt nur albedo_color/roughness — ohne transparency-Modus
			# ignoriert StandardMaterial3D den Alpha-Kanal und rendert trotzdem deckend.
			wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var mesh := ProcGenShapes.sphere(thorax_r * 0.9)
			for side in [1.0, -1.0]:
				var wing := ProcGenShapes.mi(mesh, wing_mat, thorax_pos + Vector3(side * thorax_r * 0.9, thorax_r * 0.6, 0.0), "WingR" if side > 0.0 else "WingL")
				wing.scale = Vector3(1.4, 0.12, 0.7)
				root.add_child(wing)
		AnimalVisualProfile.WingStyle.SHELL:
			var wing_mat := ProcGenShapes.mat(profile.color.darkened(0.3), 0.35)
			var mesh := ProcGenShapes.capsule(thorax_r * 0.45, thorax_r * 1.6)
			for side in [1.0, -1.0]:
				var wing := ProcGenShapes.mi(mesh, wing_mat, thorax_pos + Vector3(side * thorax_r * 0.4, thorax_r * 0.35, -thorax_r * 0.3), "ShellR" if side > 0.0 else "ShellL")
				wing.rotation.x = PI * 0.5
				wing.scale = Vector3(0.5, 1.0, 0.8)
				root.add_child(wing)
		AnimalVisualProfile.WingStyle.BROAD:
			var wing_mat := ProcGenShapes.mat(profile.color.lightened(0.2), 0.4)
			var mesh := ProcGenShapes.sphere(thorax_r * 1.5)
			for side in [1.0, -1.0]:
				var wing := ProcGenShapes.mi(mesh, wing_mat, thorax_pos + Vector3(side * thorax_r * 1.3, thorax_r * 0.7, 0.0), "WingR" if side > 0.0 else "WingL")
				wing.scale = Vector3(1.6, 0.08, 1.0)
				root.add_child(wing)
		_:
			pass

# ─────────────────────────────────────────────
# Spinne — Kopf/Brust (Cephalothorax) + großer Hinterleib, 8 Beine (vier Paare, weit
# ausgestellt, geknickt statt gerade). Bewusst KEIN Kopf-Node getrennt vom Cephalothorax:
# bei echten Spinnen sind Kopf und Brust ein einziges, nicht abgesetztes Segment.
# ─────────────────────────────────────────────

static func _build_spider(profile: AnimalVisualProfile) -> Node3D:
	var root := Node3D.new()
	root.name = "Visuals"

	var bs: Vector3 = profile.body_size
	var color: Color = profile.color
	var body_mat := ProcGenShapes.mat(color)
	var leg_mat := ProcGenShapes.mat(color.darkened(0.45), 0.55)
	var eye_mat := ProcGenShapes.mat(Color(0.05, 0.05, 0.06), 0.2)

	var cephalo_r: float = bs.x * 0.42
	var abdomen_r: float = bs.x * 0.62
	var ground_y: float = bs.y

	var cephalo_pos := Vector3(0.0, ground_y, cephalo_r * 0.8)
	root.add_child(ProcGenShapes.mi(ProcGenShapes.sphere(cephalo_r), body_mat, cephalo_pos, "Cephalothorax"))

	var abdomen_pos := Vector3(0.0, ground_y * 0.95, -abdomen_r * 0.95)
	var abdomen := ProcGenShapes.mi(ProcGenShapes.sphere(abdomen_r), body_mat, abdomen_pos, "Abdomen")
	abdomen.scale = Vector3(1.0, 0.9, 1.15)
	root.add_child(abdomen)

	# Augenreihe (vereinfacht: ein kleines Cluster statt der acht echten Spinnenaugen) —
	# genug, um den Kopf-vorne eindeutig erkennbar zu machen. Direkt in Root-Raum
	# positioniert (kein eigener "Head"-Kindknoten wie beim Vierbeiner nötig, siehe
	# _build_spider()-Klassenkommentar), deshalb keine place_on_sphere()-Elternrelativität
	# hier, sondern eine simple Vorne-oben-Position relativ zu cephalo_pos.
	var eye_r: float = cephalo_r * 0.14
	for side in [1.0, -1.0]:
		var eye_pos: Vector3 = cephalo_pos + Vector3(side * cephalo_r * 0.4, cephalo_r * 0.35, cephalo_r * 0.85)
		root.add_child(ProcGenShapes.mi(ProcGenShapes.sphere(eye_r), eye_mat, eye_pos, "EyeR" if side > 0.0 else "EyeL"))

	var accent: int = profile.accent_style
	# BIG_EYES (Springspinne): zwei große Frontaugen zusätzlich zu den kleinen.
	if accent == AnimalVisualProfile.AccentStyle.BIG_EYES:
		var big_mesh := ProcGenShapes.sphere(cephalo_r * 0.26)
		for side in [1.0, -1.0]:
			var big_pos: Vector3 = cephalo_pos + Vector3(side * cephalo_r * 0.28, cephalo_r * 0.22, cephalo_r * 0.90)
			root.add_child(ProcGenShapes.mi(big_mesh, eye_mat, big_pos, "BigEyeR" if side > 0.0 else "BigEyeL"))
	# ABDOMEN_MARK (Kreuzspinne): helles Kreuz auf dem Hinterleib (Längs- + Querbalken).
	if accent == AnimalVisualProfile.AccentStyle.ABDOMEN_MARK:
		var mark_mat := ProcGenShapes.mat(Color(0.96, 0.93, 0.80), 0.6)
		var mark_y: float = abdomen_pos.y + abdomen_r * 0.84
		var mark_long := ProcGenShapes.mi(ProcGenShapes.sphere(abdomen_r * 0.5), mark_mat, Vector3(0.0, mark_y, abdomen_pos.z), "AbdomenMarkLong")
		mark_long.scale = Vector3(0.35, 0.18, 1.0)
		root.add_child(mark_long)
		var mark_cross := ProcGenShapes.mi(ProcGenShapes.sphere(abdomen_r * 0.5), mark_mat, Vector3(0.0, mark_y, abdomen_pos.z + abdomen_r * 0.1), "AbdomenMarkCross")
		mark_cross.scale = Vector3(0.9, 0.18, 0.3)
		root.add_child(mark_cross)

	# 8 Beine: vier Paare, weit seitlich ausgestellt (deutlich flacher/breiter als beim
	# Insekt), Ansatz am Cephalothorax-Rand.
	# STOUT (Vogelspinne): deutlich dickere Beine bei gleicher Länge.
	var leg_thick: float = 1.9 if profile.accent_style == AnimalVisualProfile.AccentStyle.STOUT else 1.0
	var leg_mesh := ProcGenShapes.cylinder(bs.x * 0.03 * leg_thick, bs.x * 0.05 * leg_thick, bs.x * 1.1)
	var leg_zs: Array[float] = [cephalo_r * 0.7, cephalo_r * 0.15, -cephalo_r * 0.4, -cephalo_r * 0.9]
	for i in leg_zs.size():
		for side in [1.0, -1.0]:
			var anchor: Vector3 = cephalo_pos + Vector3(side * cephalo_r * 0.85, -cephalo_r * 0.1, leg_zs[i])
			var dir := Vector3(side * 0.9, -0.35, 0.1 * (i - 1.5)).normalized()
			var node_name := "Leg%d%s" % [i, "R" if side > 0.0 else "L"]
			root.add_child(ProcGenShapes.spike(leg_mesh, leg_mat, anchor, dir, bs.x * 1.1, node_name))

	return root

# ─────────────────────────────────────────────
# Schlange — Kette abnehmender Kapseln entlang einer sanften S-Kurve, keine Beine.
# body_size.z ist hier die GESAMTLÄNGE, body_size.x die Dicke (siehe AnimalVisualProfile-
# Feldkommentar).
# ─────────────────────────────────────────────

static func _build_snake(profile: AnimalVisualProfile) -> Node3D:
	var root := Node3D.new()
	root.name = "Visuals"

	var bs: Vector3 = profile.body_size
	var color: Color = profile.color
	var body_mat := ProcGenShapes.mat(color)
	var belly_mat := ProcGenShapes.mat(color.lightened(0.35), 0.9)
	var head_mat := ProcGenShapes.mat(color.darkened(0.1))

	var total_len: float = bs.z
	var thickness: float = bs.x * 0.5
	var ground_y: float = thickness  # liegt flach auf dem Boden, Mittelpunkt = Radius über y=0
	var segment_count := 6
	var seg_len: float = total_len / float(segment_count)

	# S-Kurve in der XZ-Ebene: Sinus-Auslenkung quer zur Laufrichtung (+Z), Amplitude
	# proportional zur Dicke (dünnere Schlangen schlängeln enger, wirkt sonst wie ein Rohr).
	var amplitude: float = thickness * 1.8
	for i in segment_count:
		var t0: float = float(i) / float(segment_count)
		var t1: float = float(i + 1) / float(segment_count)
		var z0: float = -total_len * 0.5 + t0 * total_len
		var z1: float = -total_len * 0.5 + t1 * total_len
		var x0: float = sin(t0 * TAU * 0.9) * amplitude
		var x1: float = sin(t1 * TAU * 0.9) * amplitude
		var mid := Vector3((x0 + x1) * 0.5, ground_y, (z0 + z1) * 0.5)
		# Segmente werden zum Schwanz hin dünner (Kopf = dickstes Segment, letztes = fast spitz).
		var seg_r: float = thickness * (1.0 - float(i) / float(segment_count) * 0.65)
		var seg_mesh := ProcGenShapes.capsule(seg_r, seg_len * 1.15)
		var seg := ProcGenShapes.mi(seg_mesh, body_mat, mid, "Segment%d" % i)
		var dir := (Vector3(x1, 0.0, z1) - Vector3(x0, 0.0, z0)).normalized()
		seg.basis = Basis(Quaternion(Vector3.UP, dir))
		root.add_child(seg)
		# Heller Bauchstreifen (dünne, flache Box unter jedem Segment) — rein kosmetisch,
		# macht die Unterseite erkennbar und bricht die sonst einfarbige Silhouette auf.
		var belly := ProcGenShapes.mi(ProcGenShapes.box(Vector3(seg_r * 1.1, seg_r * 0.25, seg_len * 1.05)), belly_mat, mid + Vector3(0.0, -seg_r * 0.75, 0.0), "Belly%d" % i)
		belly.basis = seg.basis
		root.add_child(belly)

	# Kopf: eigene, etwas breitere Kapsel/Kugel am vorderen Ende (i = 0 liegt bei -total_len*0.5).
	var head_r: float = thickness * 1.15
	var head_x: float = sin(0.0) * amplitude
	var head_pos := Vector3(head_x, ground_y, -total_len * 0.5 - head_r * 0.4)
	var head := ProcGenShapes.mi(ProcGenShapes.sphere(head_r), head_mat, head_pos, "Head")
	root.add_child(head)

	var accent: int = profile.accent_style
	# TRIANGLE_HEAD/RATTLE (Viper, Klapperschlange): breiter, flacher Dreieckskopf.
	if accent == AnimalVisualProfile.AccentStyle.TRIANGLE_HEAD or accent == AnimalVisualProfile.AccentStyle.RATTLE:
		head.scale = Vector3(1.45, 0.72, 1.2)
	# HOOD (Kobra): flacher, breiter Nackenschild direkt hinter dem Kopf.
	if accent == AnimalVisualProfile.AccentStyle.HOOD:
		var hood := ProcGenShapes.mi(ProcGenShapes.sphere(head_r * 1.35), body_mat, head_pos + Vector3(0.0, head_r * 0.45, head_r * 1.1), "Hood")
		hood.scale = Vector3(1.25, 0.95, 0.3)
		root.add_child(hood)
	# RATTLE: drei kleiner werdende, hornfarbene Rasselglieder hinter dem letzten Segment.
	if accent == AnimalVisualProfile.AccentStyle.RATTLE:
		var rattle_mat := ProcGenShapes.mat(Color(0.85, 0.78, 0.55), 0.5)
		var tail_x: float = sin(TAU * 0.9) * amplitude
		for k in 3:
			var bead_r: float = thickness * (0.38 - 0.06 * float(k))
			var bead_pos := Vector3(tail_x, ground_y, total_len * 0.5 + thickness * (0.3 + 0.8 * float(k)))
			root.add_child(ProcGenShapes.mi(ProcGenShapes.sphere(bead_r), rattle_mat, bead_pos, "Rattle%d" % k))

	var eye_mat := ProcGenShapes.mat(Color(0.9, 0.75, 0.1), 0.3)
	for side in [1.0, -1.0]:
		var eye := ProcGenShapes.mi(ProcGenShapes.sphere(head_r * 0.16), eye_mat, Vector3.ZERO, "EyeR" if side > 0.0 else "EyeL")
		ProcGenShapes.place_on_sphere(eye, head_r, side * head_r * 0.6, head_r * 0.2, head_r * 0.08, Vector3.ONE)
		head.add_child(eye)

	# Gespaltene Zunge — zwei sehr dünne Spikes, leicht auseinandergespreizt.
	var tongue_mat := ProcGenShapes.mat(Color(0.75, 0.1, 0.15), 0.4)
	var tongue_mesh := ProcGenShapes.cylinder(0.0, head_r * 0.03, head_r * 0.5)
	for side in [1.0, -1.0]:
		var anchor: Vector3 = head_pos + Vector3(0.0, 0.0, -head_r * 0.9)
		var dir := Vector3(side * 0.3, 0.0, -1.0).normalized()
		root.add_child(ProcGenShapes.spike(tongue_mesh, tongue_mat, anchor, dir, head_r * 0.5, "TongueR" if side > 0.0 else "TongueL"))

	# BUGFIX ("Schlange läuft rückwärts"): der Kopf sitzt oben im Code bei -Z, ALLE anderen
	# Bauplänen (und die Bewegungslogik, siehe AnimalBase._move_toward) haben vorne = +Z. Die
	# Schlange kroch deshalb mit dem Schwanz voraus und blickte im Zoo-Schaukasten von den
	# Besuchern weg. Statt jede z-Koordinate oben umzudrehen (Kopf, Hood, Rattle, Augen,
	# Zunge …) wird das fertige Modell um 180° gedreht — Geometrie/Tests bleiben unberührt.
	root.rotation.y = PI
	return root

# ─────────────────────────────────────────────
# Fisch — abgeflachter, spindelförmiger Rumpf ohne Beine, Schwanzflosse + Rücken-/
# Brustflossen. body_size.z = Länge, body_size.x = Breite, body_size.y = Höhe (siehe
# AnimalVisualProfile-Feldkommentar).
# ─────────────────────────────────────────────

static func _build_fish(profile: AnimalVisualProfile) -> Node3D:
	var root := Node3D.new()
	root.name = "Visuals"

	var bs: Vector3 = profile.body_size
	var color: Color = profile.color
	var body_mat := ProcGenShapes.mat(color, 0.3)
	var fin_mat := ProcGenShapes.mat(color.darkened(0.25), 0.4)
	var belly_mat := ProcGenShapes.mat(color.lightened(0.4), 0.25)

	var body_radius: float = bs.y * 0.5
	var body_length: float = maxf(bs.z, body_radius * 2.2)
	# Fische werden hier ohne Boden-/Beinbezug zentriert (schwebt auf halber body_size.y) —
	# AnimalBase behandelt sie physikalisch wie jedes andere Tier (siehe Fish.gd-Kommentar
	# für die bewusst vereinfachte Wasser-KI); rein visuell ist "Mitte auf halber Höhe"
	# richtig für ein Tier ohne Beine.
	var center_y: float = bs.y * 0.5

	var body_node := ProcGenShapes.mi(ProcGenShapes.capsule(body_radius, body_length), body_mat, Vector3(0.0, center_y, 0.0), "Body")
	body_node.rotation.x = PI * 0.5
	# Seitlich abgeflacht (typische Fischform: schmaler als hoch) statt der runden
	# Vierbeiner-Stauchung (die staucht vertikal, hier wird horizontal gestaucht).
	body_node.scale = Vector3(bs.x / bs.y, 1.0, 1.0)
	root.add_child(body_node)

	# Heller Bauch — flache, gestauchte Kugel an der Unterseite, analog zum Schlangen-Bauchstreifen.
	var belly_pos := Vector3(0.0, center_y - body_radius * 0.6, 0.0)
	var belly := ProcGenShapes.mi(ProcGenShapes.sphere(body_radius * 0.9), belly_mat, belly_pos, "Belly")
	belly.scale = Vector3(bs.x / bs.y * 0.95, 0.35, 0.9)
	root.add_child(belly)

	var eye_mat := ProcGenShapes.mat(Color(0.05, 0.05, 0.06), 0.2)
	var eye_r: float = body_radius * 0.22
	for side in [1.0, -1.0]:
		var eye := ProcGenShapes.mi(ProcGenShapes.sphere(eye_r), eye_mat, Vector3(side * bs.x * 0.42, center_y + body_radius * 0.15, body_length * 0.5 - eye_r * 1.3), "EyeR" if side > 0.0 else "EyeL")
		root.add_child(eye)

	var accent: int = profile.accent_style
	if accent == AnimalVisualProfile.AccentStyle.RIBBON:
		# RIBBON (Aal): keine V-förmige Schwanzflosse und keine Rückenflosse, sondern ein
		# durchgehender, niedriger Flossensaum und ein spitz auslaufendes Schwanzende.
		var ridge_len: float = body_length * 0.75
		var ridge_mesh := ProcGenShapes.box(Vector3(bs.x * 0.25, body_radius * 0.45, ridge_len))
		root.add_child(ProcGenShapes.mi(ridge_mesh, fin_mat, Vector3(0.0, center_y + body_radius * 0.95, -body_length * 0.1), "RibbonFin"))
		var taper_len: float = body_radius * 3.0
		var taper_mesh := ProcGenShapes.cone(body_radius * 0.9, taper_len)
		root.add_child(ProcGenShapes.spike(taper_mesh, body_mat, Vector3(0.0, center_y, -body_length * 0.5 + body_radius * 0.5), Vector3(0.0, 0.0, -1.0), taper_len, "TailTip"))
	else:
		# Schwanzflosse: zwei flache, spitz zulaufende Kegel am Heck, V-förmig auseinander.
		var tail_mesh := ProcGenShapes.cone(body_radius * 0.05, body_radius * 1.3)
		for side in [1.0, -1.0]:
			var anchor := Vector3(0.0, center_y, -body_length * 0.5)
			var dir := Vector3(0.0, side * 0.35, -1.0).normalized()
			var fin := ProcGenShapes.spike(tail_mesh, fin_mat, anchor, dir, body_radius * 1.3, "TailFinR" if side > 0.0 else "TailFinL")
			fin.scale = Vector3(2.6, 1.0, 1.0)
			root.add_child(fin)

		# Rückenflosse: ein einzelner, dünner Kegel oben mittig — beim Hecht (LONG_JAW) weit
		# hinten, wie bei echten Lauerjägern.
		var dorsal_z: float = -body_length * 0.28 if accent == AnimalVisualProfile.AccentStyle.LONG_JAW else body_length * 0.05
		var dorsal_mesh := ProcGenShapes.cone(body_radius * 0.04, body_radius * 0.9)
		var dorsal_anchor := Vector3(0.0, center_y + body_radius * 0.85, dorsal_z)
		var dorsal := ProcGenShapes.spike(dorsal_mesh, fin_mat, dorsal_anchor, Vector3.UP, body_radius * 0.9, "DorsalFin")
		dorsal.scale = Vector3(2.2, 1.0, 1.0)
		root.add_child(dorsal)

	# LONG_JAW (Hecht): flacher, breiter Entenschnabel-Kiefer nach vorn.
	if accent == AnimalVisualProfile.AccentStyle.LONG_JAW:
		var jaw_len: float = body_radius * 1.4
		var jaw_mesh := ProcGenShapes.capsule(body_radius * 0.28, jaw_len)
		var jaw_anchor := Vector3(0.0, center_y - body_radius * 0.12, body_length * 0.5 - body_radius * 0.2)
		var jaw := ProcGenShapes.spike(jaw_mesh, body_mat, jaw_anchor, Vector3(0.0, -0.04, 1.0), jaw_len, "Jaw")
		jaw.scale = Vector3(1.5, 1.0, 0.6)
		root.add_child(jaw)

	# BARBELS (Wels): zwei Paar dünne Barteln am Maul.
	if accent == AnimalVisualProfile.AccentStyle.BARBELS:
		var barbel_len: float = body_radius * 0.9
		var barbel_mesh := ProcGenShapes.cylinder(body_radius * 0.015, body_radius * 0.04, barbel_len)
		for side in [1.0, -1.0]:
			for k in 2:
				var kf: float = float(k)
				var barbel_anchor := Vector3(side * bs.x * 0.28, center_y - body_radius * (0.15 + 0.2 * kf), body_length * 0.5 - body_radius * 0.1)
				var barbel_dir := Vector3(side * (0.7 + 0.4 * kf), -0.3 - 0.25 * kf, 0.6).normalized()
				root.add_child(ProcGenShapes.spike(barbel_mesh, fin_mat, barbel_anchor, barbel_dir, barbel_len, "Barbel%d%s" % [k, "R" if side > 0.0 else "L"]))

	# Brustflossen: ein Paar kleiner, seitlich abstehender Kegel nahe dem Kopf.
	var pect_mesh := ProcGenShapes.cone(body_radius * 0.03, body_radius * 0.5)
	for side in [1.0, -1.0]:
		var anchor := Vector3(side * bs.x * 0.3, center_y - body_radius * 0.1, body_length * 0.28)
		var dir := Vector3(side * 0.85, -0.3, -0.1).normalized()
		root.add_child(ProcGenShapes.spike(pect_mesh, fin_mat, anchor, dir, body_radius * 0.5, "PectFinR" if side > 0.0 else "PectFinL"))

	return root
