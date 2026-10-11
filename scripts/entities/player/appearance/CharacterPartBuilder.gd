class_name CharacterPartBuilder
extends RefCounted

## CharacterPartBuilder — baut aus einem CharacterLook den sichtbaren Körper
## (Rumpf, Becken, Hals, Kopf mit Gesicht + Haaren, Arme, Beine) aus
## Godot-Primitiven. Kein Asset, keine Textur — alles prozedural, damit sich
## jedes Teil per Code ändern lässt.
##
## Rein statisch, kein Zustand. PlayerVisuals ruft `build()` bei jeder
## Look-Änderung auf und hängt das Ergebnis unter das Skeleton.
##
## KOORDINATEN (Skeleton-/Körperraum, Einheit = Meter, Füße bei y = 0):
##   +Y oben, +Z = Blickrichtung des Charakters (PlayerVisuals.handle_rotation
##   dreht die +Z-Achse in Laufrichtung).
##   +X-Seite = "_r"-Seite: das ist die Legacy-Konvention der Bones (hand_r
##   sitzt bei +X, dort hängt die Waffe). Anatomisch ist das bei +Z-Blick die
##   linke Körperseite — bewusst NICHT geändert, sonst wandern alle
##   Waffen-Attachments auf die andere Hand.
##
## PROPORTIONEN (Normal-Statur, Höhe "medium"): Gesamthöhe ~1,85 m mit Frisur,
## Kopf leicht überproportional. Die Kollisionskapsel (PlayerSetup) ist
## 1,8 m hoch.

const HEAD_R: float = 0.19
const HEAD_CENTER_Y: float = 1.65
const TORSO_R: float = 0.19
const TORSO_H: float = 0.64
const TORSO_CENTER_Y: float = 1.10
## Rumpf ist eine in X gedehnte, in Z abgeflachte Kapsel.
const TORSO_X_BASE: float = 1.25
const TORSO_Z: float = 0.85
const SHOULDER_Y: float = 1.34
const HIP_Y: float = 0.80
## Schulter -> Handmitte.
const ARM_LEN: float = 0.56
const HAND_R: float = 0.062
const LEG_X_BASE: float = 0.115
## Farbe der Unterwäsche (Unterhose; bei Frauen zusätzlich ein Brustband), wenn kein Oberteil/keine Hose getragen wird.
const UNDERWEAR_COLOR: Color = Color(0.82, 0.80, 0.76)
## Ruhezustand eines Augenlids (praktisch zu, aber nie exakt 0 → keine singuläre Matrix).
const LID_OPEN: float = 0.001
## Sommersprossen-Positionen (x, y) pro Wange, in Gesichtskoordinaten.
const FRECKLE_SPOTS: Array = [
	Vector2(0.050, -0.048), Vector2(0.078, -0.056), Vector2(0.062, -0.064),
	Vector2(0.094, -0.046), Vector2(0.046, -0.062),
]

# ─────────────────────────────────────────────
# Öffentliche Geometrie-Abfragen (für PlayerVisuals: Hand-Bones, Slots)
# ─────────────────────────────────────────────

## X-Abstand des Schultergelenks (und damit der Hand) von der Körpermitte.
static func shoulder_x(look: Dictionary) -> float:
	var tw := CharacterLook.torso_width(String(look.get("build", "normal"))) * CharacterLook.sex_param(CharacterLook.sex_of(look), "shoulder_w")
	return TORSO_R * TORSO_X_BASE * tw + 0.045

## Dickenfaktor der Gliedmaßen: Statur × Geschlecht.
static func limb_factor(look: Dictionary) -> float:
	return CharacterLook.limb_scale(String(look.get("build", "normal"))) * CharacterLook.sex_param(CharacterLook.sex_of(look), "limb_mul")

## Handmitte im Körperraum für die Seite (+1 = "_r"/+X, -1 = "_l"/-X).
static func hand_position(look: Dictionary, side: float) -> Vector3:
	return Vector3(side * shoulder_x(look), SHOULDER_Y - ARM_LEN, 0.0)

## Schulterpunkt (Drehpunkt des Arms) im Körperraum.
static func shoulder_position(look: Dictionary, side: float) -> Vector3:
	return Vector3(side * shoulder_x(look), SHOULDER_Y, 0.0)

# ─────────────────────────────────────────────
# Aufbau
# ─────────────────────────────────────────────

## Baut den gesamten Körper. Rückgabe (alles Referenzen in den neuen Baum):
##   root      Node3D   — Wurzel "Parts", vom Aufrufer einzuhängen
##   torso     MeshInstance3D — Rumpf (trägt das Hemd-Material, ohne Oberteil das Hautmaterial)
##   shirt_mat StandardMaterial3D — Oberteil-Material, geteilt von Rumpf + Ärmeln (auch ohne Oberteil vorhanden, dann ungenutzt)
##   head      Node3D   — Kopf-Gruppe (Skull, Ohren, Face, Hair, Hat)
##   face      Node3D
##   hair      Node3D
##   hat       Node3D oder null (null = keine Kopfbedeckung)
##   eye_r / eye_l  Node3D — je Auge; Kind "Gaze" (Iris/Pupille, verschiebbar → Blickrichtung)
##             und Kind "Lid" (Augenlid, skalierbar → Blinzeln). Meta: gaze_max, lid_base.
##             CharacterGaze steuert beides.
##   arm_r / arm_l / leg_r / leg_l  Node3D — Drehpunkte (Schulter/Hüfte),
##             rotation.x schwingt die Gliedmaße
##
## `overrides` (optional, NUR für lokal erzeugte Figuren wie NPCs — nie aus Save/Netzwerk):
##   skin_color / hair_color / shirt_color / pants_color / hat_color : Color
## ersetzt die Katalogfarbe. Der Look selbst bleibt reine ID-Daten.
static func build(look: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var l := CharacterLook.sanitize(look)
	var sex := String(l["sex"])
	var skin_col := _ov(overrides, "skin_color", CharacterLook.color_of("skin", l["skin"]))
	var hair_col := _ov(overrides, "hair_color", CharacterLook.color_of("hair_color", l["hair_color"]))
	var shirt_col := _ov(overrides, "shirt_color", CharacterLook.color_of("shirt", l["shirt"]))
	var pants_col := _ov(overrides, "pants_color", CharacterLook.color_of("pants", l["pants"]))
	var shirt_on := String(l["shirt"]) != "none"
	var pants_on := String(l["pants"]) != "none"
	var sw := CharacterLook.sex_param(sex, "shoulder_w")
	var hw := CharacterLook.sex_param(sex, "hip_w")
	var bust := CharacterLook.sex_param(sex, "bust")
	var tw := CharacterLook.torso_width(l["build"])
	var limb := limb_factor(l)
	var shirt_style := String(l["shirt_style"])

	var skin_mat := _skin_mat(skin_col)
	var shirt_mat := _mat(shirt_col)
	var pants_mat := _mat(pants_col)
	var under_mat := _mat(UNDERWEAR_COLOR, 0.9)
	var shoe_mat := _mat(CharacterLook.color_of("shoes", l["shoes"]), 0.8)
	var hair_mat := _mat(hair_col, 0.7)
	hair_mat.metallic_specular = 0.6
	# Ohne Oberteil ist der Rumpf nackte Haut, ohne Hose das Becken Unterwäsche.
	var torso_mat: StandardMaterial3D = shirt_mat if shirt_on else skin_mat
	var pelvis_mat: StandardMaterial3D = pants_mat if pants_on else under_mat

	var root := Node3D.new()
	root.name = "Parts"

	# Rumpf (Frauen: schmalere Schultern/Brust)
	var torso_x := TORSO_X_BASE * tw * sw
	var torso := _mi(_capsule(TORSO_R, TORSO_H), torso_mat, Vector3(0.0, TORSO_CENTER_Y, 0.0), "Torso")
	torso.scale = Vector3(torso_x, 1.0, TORSO_Z)
	root.add_child(torso)

	# Brust (nur Frauen): zwei flache Kugeln vorn am Rumpf, im Material des Rumpfes.
	if bust > 0.0:
		for side in [1.0, -1.0]:
			var b := _mi(_sphere(0.075 * bust, false, 12, 6), torso_mat, Vector3(side * 0.082 * tw, 1.26, 0.125), "BustR" if side > 0.0 else "BustL")
			b.scale = Vector3(1.0, 0.95, 0.85)
			root.add_child(b)
		# Ohne Oberteil: schlichtes Brustband in Unterwäsche-Farbe.
		if not shirt_on:
			var band := _mi(_cylinder(0.2, 0.2, 0.11, 18), under_mat, Vector3(0.0, 1.27, 0.0), "UnderTop")
			band.scale = Vector3(torso_x * 0.96, 1.0, TORSO_Z * 1.22)
			root.add_child(band)

	# Becken (Hosenfarbe, ohne Hose Unterwäsche) — schließt die Lücke zwischen Rumpf und Beinen.
	# Frauen: breiteres Becken.
	var pelvis := _mi(_capsule(0.115, 0.44 * tw * hw + 0.06), pelvis_mat, Vector3(0.0, HIP_Y + 0.02, 0.0), "Pelvis")
	pelvis.rotation.z = PI * 0.5
	root.add_child(pelvis)

	# Tunika: Saum über Becken/Oberschenkeln (leicht ausgestellt).
	if shirt_on and shirt_style == "tunic":
		var skirt := _mi(_cylinder(0.21, 0.285, 0.30, 16), shirt_mat, Vector3(0.0, 0.79, 0.0), "TunicSkirt")
		skirt.scale = Vector3(tw * hw, 1.0, 0.75)
		root.add_child(skirt)

	# Gürtel (Ring um den Rumpf + Schnalle).
	var belt_id := String(l["belt"])
	if belt_id != "none":
		var belt_mat := _mat(CharacterLook.color_of("belt", belt_id), 0.6)
		var belt := _mi(_torus(0.183, 0.203), belt_mat, Vector3(0.0, 0.95, 0.0), "Belt")
		belt.scale = Vector3(torso_x, 1.0, TORSO_Z)
		root.add_child(belt)
		var buckle_mat := _mat(Color(0.80, 0.66, 0.25), 0.35)
		root.add_child(_mi(_box(Vector3(0.05, 0.045, 0.012)), buckle_mat, Vector3(0.0, 0.95, (0.193 + 0.01) * TORSO_Z), "BeltBuckle"))

	# Hals + Kragen (Kragen nur bei Oberteilen mit Halsausschnitt).
	var neck_r := 0.055 * CharacterLook.sex_param(sex, "neck_mul")
	root.add_child(_mi(_cylinder(neck_r, neck_r, 0.12), skin_mat, Vector3(0.0, 1.47, 0.0), "Neck"))
	if shirt_on and shirt_style != "vest":
		root.add_child(_mi(_torus(0.048, 0.075), shirt_mat, Vector3(0.0, 1.425, 0.0), "Collar"))

	# Kopf
	var head := _build_head(l, skin_mat, hair_mat, skin_col, hair_col, overrides)
	root.add_child(head)

	# Arme / Beine (Drehpunkte, damit sie später animiert werden können)
	var arm_r := _build_arm(l, 1.0, limb, skin_mat, shirt_mat, "ArmR")
	var arm_l := _build_arm(l, -1.0, limb, skin_mat, shirt_mat, "ArmL")
	var leg_r := _build_leg(l, 1.0, tw * hw, limb, pants_mat, skin_mat, shoe_mat, "LegR")
	var leg_l := _build_leg(l, -1.0, tw * hw, limb, pants_mat, skin_mat, shoe_mat, "LegL")
	root.add_child(arm_r)
	root.add_child(arm_l)
	root.add_child(leg_r)
	root.add_child(leg_l)

	var face := head.get_node("Face")
	var parts := {
		"root": root,
		"torso": torso,
		"shirt_mat": shirt_mat,
		"head": head,
		"face": face,
		"hair": head.get_node("Hair"),
		"hat": head.get_node_or_null("Hat"),
		"eye_r": face.get_node_or_null("EyeR"),
		"eye_l": face.get_node_or_null("EyeL"),
		"arm_r": arm_r,
		"arm_l": arm_l,
		"leg_r": leg_r,
		"leg_l": leg_l,
	}

	# Schal, Rucksack/Umhang, Beutel, Schulterplatten und Rüstung (über der Kleidung).
	WornGearBuilder.apply(parts, l, {
		"sx": shoulder_x(l), "tw": tw, "sw": sw, "hw": hw, "bust": bust, "limb": limb,
		"hip_y": HIP_Y, "torso_y": TORSO_CENTER_Y, "torso_x": torso_x, "torso_z": TORSO_Z,
	})
	return parts

# ─────────────────────────────────────────────
# Kopf / Gesicht / Haare
# ─────────────────────────────────────────────

static func _build_head(l: Dictionary, skin_mat: StandardMaterial3D, hair_mat: StandardMaterial3D, skin_col: Color, hair_col: Color, overrides: Dictionary) -> Node3D:
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, HEAD_CENTER_Y, 0.0)

	head.add_child(_mi(_sphere(HEAD_R, false, 24, 12), skin_mat, Vector3.ZERO, "Skull"))
	for side in [1.0, -1.0]:
		head.add_child(_build_ear(String(l["ears"]), skin_mat, side))

	var face := Node3D.new()
	face.name = "Face"
	head.add_child(face)
	_build_face(face, l, skin_col, hair_col, skin_mat)

	var hair := Node3D.new()
	hair.name = "Hair"
	head.add_child(hair)
	_build_hair(hair, String(l["hair_style"]), hair_mat)

	var hat_id := String(l["hat"])
	if hat_id != "none":
		var hat_col := _ov(overrides, "hat_color", CharacterLook.color_of("hat_color", l["hat_color"]))
		head.add_child(_build_hat(hat_id, hat_col))

	return head

static func _build_ear(style: String, skin_mat: StandardMaterial3D, side: float) -> MeshInstance3D:
	var node_name := "EarR" if side > 0.0 else "EarL"
	if style == "pointed":
		# Elfenohr: flacher Kegel, schräg nach außen/oben. Rotation um Z: -side*θ
		# lässt die Spitze (+Y) auf die Außenseite kippen.
		var tilt := 1.0
		var length := 0.13
		var dir := Vector2(side * sin(tilt), cos(tilt))
		var base := Vector2(side * (HEAD_R - 0.01), -0.01)
		var center := base + dir * (length * 0.5)
		var ear := _mi(ProcGenShapes.cone(0.032, length, 8), skin_mat, Vector3(center.x, center.y, 0.0), node_name)
		ear.rotation.z = -side * tilt
		ear.scale = Vector3(1.0, 1.0, 0.45)
		return ear
	var radius := 0.026 if style == "small" else 0.035
	var ear2 := _mi(_sphere(radius), skin_mat, Vector3(side * (HEAD_R - 0.002), -0.005, 0.0), node_name)
	ear2.scale = Vector3(0.55, 1.0, 0.8)
	return ear2

static func _build_face(face: Node3D, l: Dictionary, skin_col: Color, hair_col: Color, skin_mat: StandardMaterial3D) -> void:
	var iris_col := CharacterLook.color_of("eye_color", l["eye_color"])
	var eye_style := String(l["eyes"])

	# Augen
	for side in [1.0, -1.0]:
		var eye := _build_eye(eye_style, iris_col, skin_mat, side)
		var y_scale := 0.55 if eye_style == "narrow" else 1.0
		_place(eye, side * 0.07, 0.0, 0.0, Vector3(1.0, y_scale, 1.0))
		eye.name = "EyeR" if side > 0.0 else "EyeL"
		face.add_child(eye)

	# Brauen (Hinweis Roll-Vorzeichen: +roll hebt bei x>0 das äußere Ende an,
	# der innere Rand sinkt = strenger Blick; siehe Klassen-Doku Koordinaten.)
	var brow_style := String(l["brows"])
	if brow_style != "none":
		var brow_mat := _mat(hair_col.darkened(0.15), 0.8)
		var size := Vector3(0.075, 0.014, 0.012)
		var roll := 0.0
		var brow_y := 0.057
		match brow_style:
			"soft":
				roll = -0.12
			"angled":
				roll = 0.30
			"thick":
				size = Vector3(0.085, 0.026, 0.014)
				roll = 0.08
			"arched":
				size = Vector3(0.072, 0.012, 0.012)
				roll = -0.24
				brow_y = 0.064
		for side in [1.0, -1.0]:
			var brow := _mi(_box(size), brow_mat, Vector3.ZERO, "BrowR" if side > 0.0 else "BrowL")
			_place(brow, side * 0.07, brow_y, 0.004, Vector3.ONE, side * roll)
			face.add_child(brow)

	# Nase
	var nose_style := String(l["nose"])
	if nose_style != "none":
		var nose_r := 0.022
		var nose_scale := Vector3.ONE
		match nose_style:
			"round":
				nose_r = 0.032
			"long":
				nose_r = 0.024
				nose_scale = Vector3(0.85, 1.7, 1.0)
			"wide":
				nose_r = 0.028
				nose_scale = Vector3(1.6, 0.85, 1.0)
		var nose := _mi(_sphere(nose_r), _mat(skin_col.darkened(0.06), 0.9), Vector3.ZERO, "Nose")
		_place(nose, 0.0, -0.04, 0.008, nose_scale)
		face.add_child(nose)

	# Mund (Lippenfarbe aus dem Hautton abgeleitet — wirkt auf hellen UND dunklen Tönen stimmig)
	var lip_col := skin_col.lerp(Color(0.62, 0.22, 0.26), 0.55)
	var beard_style := String(l["beard"])
	_build_mouth(face, String(l["mouth"]), lip_col, _mouth_lift(beard_style))

	# Bart (liegt vor/um den Mund; der Mund wird dafür per Lift nach vorn geholt)
	_build_beard(face, beard_style, hair_col.darkened(0.06), skin_col)

	# Gesichtsdetails + Brille
	_build_face_detail(face, String(l["face_detail"]), skin_col)
	if String(l["glasses"]) != "none":
		_build_glasses(face, String(l["glasses"]))

## Auge = Gruppe aus festem Augapfel (Sclera), beweglichem "Gaze" (Iris + Pupille +
## Glanzpunkt — wird von CharacterGaze seitlich verschoben) und "Lid" (Augenlid für
## Blinzeln/Müdigkeit). Metadaten für CharacterGaze: gaze_max (max. Verschiebung in m),
## lid_base (Grund-Lidschluss 0..1), eye_side (+1/-1).
static func _build_eye(style: String, iris_col: Color, skin_mat: StandardMaterial3D, side: float) -> Node3D:
	var eye := Node3D.new()
	eye.set_meta("eye_side", side)
	var dark := _mat(Color(0.05, 0.05, 0.07), 0.3)
	var gaze := Node3D.new()
	gaze.name = "Gaze"
	eye.add_child(gaze)

	if style == "dot":
		var bead := _mi(_sphere(0.024), dark, Vector3.ZERO, "Bead")
		bead.scale = Vector3(1.0, 1.15, 0.5)
		gaze.add_child(bead)
		eye.set_meta("gaze_max", 0.006)
		eye.set_meta("lid_base", 0.0)
		return eye

	var big := style == "big"
	var sclera_r := 0.044 if big else 0.034
	var iris_r := 0.028 if big else 0.021
	var pupil_r := 0.014 if big else 0.011
	var depth := 0.45  # Abflachung in Z (Anteil des Radius)

	var sclera := _mi(_sphere(sclera_r), _mat(Color(0.97, 0.97, 0.95), 0.4), Vector3.ZERO, "Sclera")
	sclera.scale = Vector3(1.0, 1.0, depth)
	eye.add_child(sclera)

	var iris := _mi(_sphere(iris_r), _mat(iris_col, 0.3), Vector3(0.0, 0.0, sclera_r * depth * 0.45), "Iris")
	iris.scale = Vector3(1.0, 1.0, depth)
	gaze.add_child(iris)

	var pupil := _mi(_sphere(pupil_r), dark, Vector3(0.0, 0.0, sclera_r * depth * 1.0), "Pupil")
	pupil.scale = Vector3(1.0, 1.0, depth)
	gaze.add_child(pupil)

	# Glanzpunkt: macht den Blick lebendig (unbeleuchtet, damit er nie "absäuft").
	var shine_mat := StandardMaterial3D.new()
	shine_mat.albedo_color = Color(1.0, 1.0, 1.0)
	shine_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shine := _mi(_sphere(iris_r * 0.26, false, 8, 4), shine_mat, Vector3(iris_r * 0.38, iris_r * 0.42, sclera_r * depth + 0.004), "Shine")
	shine.scale = Vector3(1.0, 1.0, 0.6)
	gaze.add_child(shine)

	# Wimpern: oberer Strich + kleiner Schwung am äußeren Augenwinkel.
	if style == "lashes":
		var lash_mat := _mat(Color(0.06, 0.05, 0.06), 0.8)
		var lash_z := sclera_r * depth * 0.95
		var upper := _mi(_box(Vector3(sclera_r * 2.3, 0.005, 0.006)), lash_mat, Vector3(0.0, sclera_r * 0.98, lash_z), "Lashes")
		eye.add_child(upper)
		var flick := _mi(_box(Vector3(0.016, 0.004, 0.005)), lash_mat, Vector3(side * sclera_r * 1.1, sclera_r * 1.04, lash_z), "LashFlick")
		flick.rotation.z = side * 0.5
		eye.add_child(flick)

	# Augenlid: Pivot am oberen Augenrand, skaliert in Y → wächst nach unten.
	var top := sclera_r * 1.12
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0.0, top, 0.0)
	var lid_mesh := _mi(_sphere(top), skin_mat, Vector3(0.0, -top, 0.0), "LidMesh")
	lid_mesh.scale = Vector3(1.0, 1.0, 0.62)
	lid.add_child(lid_mesh)
	var base_cover := 0.38 if style == "sleepy" else 0.0
	lid.scale = Vector3(1.0, maxf(base_cover, LID_OPEN), 1.0)
	lid.visible = base_cover > 0.02
	eye.add_child(lid)

	eye.set_meta("gaze_max", (sclera_r - iris_r) * 0.85)
	eye.set_meta("lid_base", base_cover)
	return eye

## `lift`: zusätzlicher Abstand nach vorn (Bart schiebt die Lippen aus dem Kinn heraus).
static func _build_mouth(face: Node3D, style: String, lip_col: Color, lift: float = 0.0) -> void:
	var lip_mat := _mat(lip_col, 0.6)
	var y := -0.085
	match style:
		"neutral":
			var m := _mi(_box(Vector3(0.06, 0.010, 0.010)), lip_mat, Vector3.ZERO, "Mouth")
			_place(m, 0.0, y, 0.003 + lift)
			face.add_child(m)
		"open":
			var m := _mi(_sphere(0.022), _mat(Color(0.30, 0.08, 0.10), 0.5), Vector3.ZERO, "Mouth")
			_place(m, 0.0, y - 0.004, 0.002 + lift, Vector3(1.3, 0.9, 0.4))
			face.add_child(m)
		"smirk":
			var m := _mi(_box(Vector3(0.05, 0.010, 0.010)), lip_mat, Vector3.ZERO, "Mouth")
			_place(m, 0.012, y, 0.003 + lift, Vector3.ONE, 0.22)
			face.add_child(m)
		"grin":
			# Breites Lächeln mit Zähnen.
			var teeth := _mi(_box(Vector3(0.056, 0.014, 0.006)), _mat(Color(0.96, 0.95, 0.90), 0.4), Vector3.ZERO, "Teeth")
			_place(teeth, 0.0, y - 0.002, 0.002 + lift)
			face.add_child(teeth)
			for side in [1.0, -1.0]:
				var seg := _mi(_box(Vector3(0.036, 0.010, 0.010)), lip_mat, Vector3.ZERO, "MouthR" if side > 0.0 else "MouthL")
				_place(seg, side * 0.027, y + 0.006, 0.004 + lift, Vector3.ONE, side * 0.50)
				face.add_child(seg)
		"frown":
			for side in [1.0, -1.0]:
				var seg := _mi(_box(Vector3(0.034, 0.010, 0.010)), lip_mat, Vector3.ZERO, "MouthR" if side > 0.0 else "MouthL")
				_place(seg, side * 0.019, y - 0.002, 0.003 + lift, Vector3.ONE, side * -0.34)
				face.add_child(seg)
		_:
			# "smile": zwei Segmente, äußere Enden angehoben (Roll-Vorzeichen
			# wie bei den Brauen: +roll hebt bei x>0 das äußere Ende).
			for side in [1.0, -1.0]:
				var seg := _mi(_box(Vector3(0.036, 0.010, 0.010)), lip_mat, Vector3.ZERO, "MouthR" if side > 0.0 else "MouthL")
				_place(seg, side * 0.021, y + 0.004, 0.003 + lift, Vector3.ONE, side * 0.38)
				face.add_child(seg)

static func _mouth_lift(beard_style: String) -> float:
	match beard_style:
		"stubble":
			return 0.004
		"full":
			return 0.024
		_:
			return 0.0

static func _build_face_detail(face: Node3D, style: String, skin_col: Color) -> void:
	match style:
		"freckles":
			var mat := _mat(skin_col.darkened(0.25).lerp(Color(0.50, 0.25, 0.15), 0.30), 0.9)
			for side in [1.0, -1.0]:
				var i := 0
				for spot in FRECKLE_SPOTS:
					var dot := _mi(_sphere(0.0055, false, 8, 4), mat, Vector3.ZERO, "Freckle%s%d" % ["R" if side > 0.0 else "L", i])
					_place(dot, side * (spot as Vector2).x, (spot as Vector2).y, 0.0, Vector3(1.0, 1.0, 0.5))
					face.add_child(dot)
					i += 1
		"blush":
			var mat := _mat(skin_col.lerp(Color(0.92, 0.45, 0.45), 0.45), 0.9)
			for side in [1.0, -1.0]:
				var cheek := _mi(_sphere(0.028, false, 12, 6), mat, Vector3.ZERO, "BlushR" if side > 0.0 else "BlushL")
				_place(cheek, side * 0.09, -0.052, 0.001, Vector3(1.0, 0.65, 0.3))
				face.add_child(cheek)
		"scar":
			var mat := _mat(skin_col.lightened(0.12).lerp(Color(0.75, 0.32, 0.32), 0.45), 0.8)
			var scar := _mi(_box(Vector3(0.006, 0.07, 0.004)), mat, Vector3.ZERO, "Scar")
			_place(scar, -0.095, 0.02, 0.002, Vector3.ONE, 0.45)
			face.add_child(scar)

## Brille. Alle Maße in Gesichtskoordinaten (Kopfmitte = Ursprung). Linsen sitzen auf
## der Kopfkugel vor den Augen (lift 0.024 > Augapfel-Vorwölbung ≈ 0.015 → kein Clipping).
static func _build_glasses(face: Node3D, style: String) -> void:
	var frame_mat := _mat(Color(0.10, 0.09, 0.09), 0.4)
	var glass_mat := _glass_mat(Color(0.75, 0.88, 1.0, 0.22))
	if style == "shades":
		glass_mat = _glass_mat(Color(0.04, 0.04, 0.05, 0.93))

	for side in [1.0, -1.0]:
		var holder := Node3D.new()
		holder.name = "GlassesR" if side > 0.0 else "GlassesL"
		_place(holder, side * 0.07, 0.0, 0.024)
		match style:
			"round":
				var rim := _mi(_torus(0.036, 0.0435), frame_mat, Vector3.ZERO, "Rim")
				rim.rotation.x = PI * 0.5
				holder.add_child(rim)
				var lens := _mi(_cylinder(0.037, 0.037, 0.003), glass_mat, Vector3.ZERO, "Lens")
				lens.rotation.x = PI * 0.5
				holder.add_child(lens)
			"square":
				var w := 0.088
				var h := 0.062
				var t := 0.006
				holder.add_child(_mi(_box(Vector3(w, t, t)), frame_mat, Vector3(0.0, h * 0.5, 0.0), "FrameTop"))
				holder.add_child(_mi(_box(Vector3(w, t, t)), frame_mat, Vector3(0.0, -h * 0.5, 0.0), "FrameBottom"))
				holder.add_child(_mi(_box(Vector3(t, h, t)), frame_mat, Vector3(-w * 0.5, 0.0, 0.0), "FrameLeft"))
				holder.add_child(_mi(_box(Vector3(t, h, t)), frame_mat, Vector3(w * 0.5, 0.0, 0.0), "FrameRight"))
				holder.add_child(_mi(_box(Vector3(w - t, h - t, 0.003)), glass_mat, Vector3.ZERO, "Lens"))
			_:
				# "shades": dunkle, leicht abgerundet wirkende Gläser mit dickem Rahmen.
				holder.add_child(_mi(_box(Vector3(0.094, 0.060, 0.012)), frame_mat, Vector3.ZERO, "Frame"))
				holder.add_child(_mi(_box(Vector3(0.084, 0.050, 0.014)), glass_mat, Vector3.ZERO, "Lens"))
		face.add_child(holder)

		# Bügel: zwei Segmente, die der Kopfrundung folgen (mit Abstand ≥ Kopfradius).
		var p0 := Vector3(side * 0.128, 0.0, 0.186)
		var p1 := Vector3(side * 0.188, 0.0, 0.075)
		var p2 := Vector3(side * 0.200, 0.002, -0.010)
		face.add_child(_bar(p0, p1, 0.005, frame_mat, "TempleFrontR" if side > 0.0 else "TempleFrontL"))
		face.add_child(_bar(p1, p2, 0.005, frame_mat, "TempleBackR" if side > 0.0 else "TempleBackL"))

	# Nasensteg
	var bridge := _mi(_box(Vector3(0.034, 0.008, 0.008)), frame_mat, Vector3.ZERO, "Bridge")
	_place(bridge, 0.0, 0.008, 0.026)
	face.add_child(bridge)

## Bart. `beard_col` = Haarfarbe (etwas dunkler); Stoppeln mischen sie mit dem Hautton.
static func _build_beard(face: Node3D, style: String, beard_col: Color, skin_col: Color) -> void:
	match style:
		"stubble":
			var stub_mat := _mat(skin_col.lerp(beard_col, 0.42), 0.9)
			face.add_child(_jaw_blob(stub_mat, -0.10, 0.118, 0.095, 0.006, "Stubble"))
		"mustache":
			_add_mustache(face, _mat(beard_col, 0.8), 1.0, 0.008)
		"goatee":
			var mat := _mat(beard_col, 0.8)
			_add_mustache(face, mat, 0.8, 0.008)
			var chin := _mi(_sphere(0.04), mat, Vector3.ZERO, "Goatee")
			_place(chin, 0.0, -0.128, 0.006, Vector3(1.0, 1.4, 0.8))
			face.add_child(chin)
		"full":
			var mat := _mat(beard_col, 0.8)
			face.add_child(_jaw_blob(mat, -0.10, 0.125, 0.10, 0.024, "BeardJaw"))
			_add_mustache(face, mat, 1.0, 0.014)
			for side in [1.0, -1.0]:
				face.add_child(_mi(_box(Vector3(0.034, 0.12, 0.10)), mat, Vector3(side * 0.165, -0.055, 0.055), "SideburnR" if side > 0.0 else "SideburnL"))

## Ellipsoid, das vorn `protrude` Meter aus der Kopfkugel ragt (Unterkiefer-Bart).
static func _jaw_blob(mat: StandardMaterial3D, y_c: float, rx: float, ry: float, protrude: float, node_name: String) -> MeshInstance3D:
	var rz := 0.075
	var z_front := sqrt(maxf(HEAD_R * HEAD_R - y_c * y_c, 0.0001)) + protrude
	var blob := _mi(_sphere(1.0, false, 16, 8), mat, Vector3(0.0, y_c, z_front - rz), node_name)
	blob.scale = Vector3(rx, ry, rz)
	return blob

static func _add_mustache(face: Node3D, mat: StandardMaterial3D, size_factor: float, lift: float) -> void:
	for side in [1.0, -1.0]:
		var m := _mi(_sphere(0.022), mat, Vector3.ZERO, "MustacheR" if side > 0.0 else "MustacheL")
		_place(m, side * 0.022, -0.062, lift, Vector3(1.5, 0.6, 0.8) * size_factor, side * 0.25)
		face.add_child(m)

static func _build_hair(hair: Node3D, style: String, mat: StandardMaterial3D) -> void:
	match style:
		"bald":
			pass
		"buzz":
			hair.add_child(_cap(0.198, mat))
		"bob":
			hair.add_child(_cap(0.212, mat))
			hair.add_child(_mi(_box(Vector3(0.40, 0.24, 0.11)), mat, Vector3(0.0, -0.06, -0.115), "BobBack"))
			for side in [1.0, -1.0]:
				hair.add_child(_mi(_box(Vector3(0.055, 0.22, 0.20)), mat, Vector3(side * 0.185, -0.05, -0.03), "BobSideR" if side > 0.0 else "BobSideL"))
		"long":
			hair.add_child(_cap(0.212, mat))
			hair.add_child(_mi(_sphere(0.17), mat, Vector3(0.0, 0.0, -0.05), "Volume"))
			hair.add_child(_mi(_box(Vector3(0.40, 0.55, 0.08)), mat, Vector3(0.0, -0.21, -0.14), "LongBack"))
			for side in [1.0, -1.0]:
				hair.add_child(_mi(_box(Vector3(0.05, 0.36, 0.09)), mat, Vector3(side * 0.19, -0.13, -0.03), "LockR" if side > 0.0 else "LockL"))
		"ponytail":
			hair.add_child(_cap(0.208, mat))
			hair.add_child(_mi(_sphere(0.17), mat, Vector3(0.0, 0.0, -0.05), "Volume"))
			var tail := _mi(_capsule(0.045, 0.34), mat, Vector3(0.0, -0.09, -0.235), "Tail")
			tail.rotation.x = 0.35
			hair.add_child(tail)
			hair.add_child(_mi(_sphere(0.05), _mat(Color(0.75, 0.20, 0.20), 0.7), Vector3(0.0, 0.02, -0.20), "Tie"))
		"bun":
			hair.add_child(_cap(0.208, mat))
			hair.add_child(_mi(_sphere(0.17), mat, Vector3(0.0, 0.0, -0.05), "Volume"))
			hair.add_child(_mi(_sphere(0.085), mat, Vector3(0.0, 0.215, -0.07), "Bun"))
		"spiky":
			hair.add_child(_cap(0.200, mat))
			hair.add_child(_spike(mat, Vector3(0.0, 0.17, -0.02), Vector3(0.0, 1.0, -0.15), "SpikeTop"))
			var count := 5
			for i in count:
				var a := TAU * float(i) / float(count) + 0.3
				var dir := Vector3(sin(a) * 0.55, 1.0, cos(a) * 0.55 - 0.1)
				var base := Vector3(sin(a) * 0.115, 0.13, cos(a) * 0.115 - 0.02)
				hair.add_child(_spike(mat, base, dir, "Spike%d" % i))
		"curly":
			hair.add_child(_cap(0.208, mat))
			hair.add_child(_mi(_sphere(0.17), mat, Vector3(0.0, 0.0, -0.05), "Volume"))
			# Locken-Kranz: Stirnbereich kleiner und höher (Stirn bleibt frei).
			var n := 11
			for i in n:
				var a := TAU * float(i) / float(n)
				var y := 0.075 + 0.02 * sin(float(i) * 2.3)
				var ball_r := 0.062
				if cos(a) > 0.45:
					y = 0.125
					ball_r = 0.05
				var pos := Vector3(sin(a) * 0.168, y, cos(a) * 0.168 - 0.045)
				hair.add_child(_mi(_sphere(ball_r, false, 8, 4), mat, pos, "Curl%d" % i))
			var tops := [Vector3(0.0, 0.195, -0.02), Vector3(0.07, 0.18, -0.06), Vector3(-0.07, 0.18, -0.06), Vector3(0.0, 0.17, -0.10)]
			for j in tops.size():
				hair.add_child(_mi(_sphere(0.06, false, 8, 4), mat, tops[j], "CurlTop%d" % j))
		"mohawk":
			hair.add_child(_cap(0.196, mat))
			var count_m := 7
			for i in count_m:
				var z := lerpf(0.11, -0.13, float(i) / float(count_m - 1))
				var y := sqrt(maxf(HEAD_R * HEAD_R - z * z, 0.0001))
				var length := 0.17 - absf(float(i) - 3.0) * 0.012
				var base := Vector3(0.0, y - 0.015, z)
				var dir := Vector3(0.0, y, z * 0.8)
				hair.add_child(ProcGenShapes.spike(ProcGenShapes.cone(0.04, length, 8), mat, base, dir, length, "Crest%d" % i))
		"pigtails":
			hair.add_child(_cap(0.208, mat))
			hair.add_child(_mi(_sphere(0.17), mat, Vector3(0.0, 0.0, -0.05), "Volume"))
			var tie_mat := _mat(Color(0.75, 0.20, 0.20), 0.7)
			for side in [1.0, -1.0]:
				var tail_node := _mi(_capsule(0.04, 0.28), mat, Vector3(side * 0.215, -0.11, -0.05), "TailR" if side > 0.0 else "TailL")
				tail_node.rotation.z = side * 0.40
				hair.add_child(tail_node)
				hair.add_child(_mi(_sphere(0.032), tie_mat, Vector3(side * 0.168, 0.0, -0.05), "TieR" if side > 0.0 else "TieL"))
		"messy":
			hair.add_child(_cap(0.208, mat))
			hair.add_child(_mi(_sphere(0.17), mat, Vector3(0.0, 0.0, -0.05), "Volume"))
			var count_x := 8
			for i in count_x:
				var a := TAU * float(i) / float(count_x) + 0.2
				var tilt := 0.5 + 0.3 * sin(float(i) * 1.7)
				var dir := Vector3(sin(a) * tilt, 1.0, cos(a) * tilt - 0.1)
				var base := Vector3(sin(a) * 0.12, 0.12 + 0.02 * sin(float(i) * 3.1), cos(a) * 0.12 - 0.03)
				hair.add_child(ProcGenShapes.spike(ProcGenShapes.cone(0.045, 0.11, 8), mat, base, dir, 0.11, "Tuft%d" % i))
		_:
			# "short" + unbekannte Werte (sanitize() lässt hier nur bekannte durch)
			hair.add_child(_cap(0.208, mat))
			hair.add_child(_mi(_sphere(0.17), mat, Vector3(0.0, 0.0, -0.05), "Volume"))

## Kopfbedeckung (Kind von "Head" → dreht mit, wenn CharacterGaze den Kopf bewegt).
## Alle Hüte sind größer als die größte Frisur (Radius ≈ 0.212), damit nichts durchsticht.
static func _build_hat(style: String, hat_col: Color) -> Node3D:
	# Schutzhelm und Zylinder haben feste Farben (hat_color wird ignoriert).
	if style == "hardhat":
		return WornGearBuilder.make_hardhat()
	if style == "tophat":
		return WornGearBuilder.make_tophat()
	var hat := Node3D.new()
	hat.name = "Hat"
	var mat := _mat(hat_col, 0.75)
	var dark := _mat(hat_col.darkened(0.25), 0.7)
	match style:
		"cap":
			var dome := _mi(_sphere(0.224, true, 20, 8), mat, Vector3(0.0, 0.035, -0.01), "Dome")
			dome.rotation.x = -0.30
			hat.add_child(dome)
			var visor := _mi(_box(Vector3(0.20, 0.012, 0.14)), dark, Vector3(0.0, 0.10, 0.215), "Visor")
			visor.rotation.x = 0.16
			hat.add_child(visor)
			hat.add_child(_mi(_sphere(0.018, false, 8, 4), dark, Vector3(0.0, 0.255, -0.06), "Button"))
		"beanie":
			var tilt := Node3D.new()
			tilt.name = "Tilt"
			tilt.position = Vector3(0.0, 0.075, -0.01)
			tilt.rotation.x = -0.20
			var dome := _mi(_sphere(0.226, true, 20, 8), mat, Vector3.ZERO, "Dome")
			dome.scale = Vector3(1.0, 1.05, 1.0)
			tilt.add_child(dome)
			tilt.add_child(_mi(_cylinder(0.232, 0.232, 0.06, 20), dark, Vector3.ZERO, "Band"))
			tilt.add_child(_mi(_sphere(0.045, false, 10, 5), dark, Vector3(0.0, 0.235, 0.0), "Pompom"))
			hat.add_child(tilt)
		"straw":
			hat.add_child(_mi(_cylinder(0.36, 0.36, 0.014, 28), mat, Vector3(0.0, 0.075, 0.0), "Brim"))
			hat.add_child(_mi(_cylinder(0.20, 0.225, 0.14, 20), mat, Vector3(0.0, 0.145, 0.0), "Crown"))
			hat.add_child(_mi(_cylinder(0.228, 0.228, 0.035, 20), dark, Vector3(0.0, 0.10, 0.0), "Ribbon"))
		"wizard":
			hat.add_child(_mi(_cylinder(0.31, 0.31, 0.014, 28), mat, Vector3(0.0, 0.075, 0.0), "Brim"))
			var cone := _mi(ProcGenShapes.cone(0.23, 0.44, 12), mat, Vector3(0.0, 0.295, -0.01), "Cone")
			cone.rotation.x = -0.18
			hat.add_child(cone)
			hat.add_child(_mi(_cylinder(0.232, 0.232, 0.03, 20), dark, Vector3(0.0, 0.09, 0.0), "Band"))
	return hat

## Haarkappe: nach hinten gekippte Halbkugel — vorn hoher Haaransatz (Stirn
## frei), hinten tief. Halbkugel-Mesh: Kuppel nach +Y, flache Basis bei y=0.
static func _cap(radius: float, mat: StandardMaterial3D, back_tilt: float = -0.4) -> MeshInstance3D:
	var cap := _mi(_sphere(radius, true, 20, 8), mat, Vector3(0.0, 0.02, -0.01), "Cap")
	cap.rotation.x = back_tilt
	return cap

## Kegel-Stachel: Spitze zeigt entlang `dir`.
static func _spike(mat: StandardMaterial3D, base: Vector3, dir: Vector3, node_name: String) -> MeshInstance3D:
	var d := dir.normalized()
	var spike := _mi(_cylinder(0.0, 0.05, 0.15), mat, base + d * 0.06, node_name)
	spike.basis = Basis(Quaternion(Vector3.UP, d))
	return spike

# ─────────────────────────────────────────────
# Arme / Beine
# ─────────────────────────────────────────────

static func _build_arm(l: Dictionary, side: float, limb: float, skin_mat: StandardMaterial3D, shirt_mat: StandardMaterial3D, node_name: String) -> Node3D:
	var style := String(l["shirt_style"])
	var shirt_on := String(l["shirt"]) != "none"
	# vest = ärmellos (Oberarm Hautfarbe); longsleeve/tunic = Unterarm im Stoff; ohne Oberteil: nackte Arme.
	var upper_mat := skin_mat if (style == "vest" or not shirt_on) else shirt_mat
	var lower_mat := shirt_mat if (shirt_on and (style == "longsleeve" or style == "tunic")) else skin_mat
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = shoulder_position(l, side)
	pivot.add_child(_mi(_capsule(0.072 * limb, 0.32), upper_mat, Vector3(0.0, -0.14, 0.0), "Sleeve"))
	pivot.add_child(_mi(_capsule(0.058 * limb, 0.34), lower_mat, Vector3(0.0, -0.40, 0.0), "Forearm"))
	pivot.add_child(_mi(_sphere(HAND_R * limb), skin_mat, Vector3(0.0, -ARM_LEN, 0.0), "Hand"))
	return pivot

static func _build_leg(l: Dictionary, side: float, tw: float, limb: float, pants_mat: StandardMaterial3D, skin_mat: StandardMaterial3D, shoe_mat: StandardMaterial3D, node_name: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = Vector3(side * LEG_X_BASE * tw, HIP_Y, 0.0)
	var pants_on := String(l["pants"]) != "none"
	if not pants_on:
		# Keine Hose: blankes Bein (die Unterhose ist das Becken).
		pivot.add_child(_mi(_capsule(0.10 * limb, HIP_Y), skin_mat, Vector3(0.0, -HIP_Y * 0.5, 0.0), "Leg"))
	elif String(l["pants_style"]) == "shorts":
		pivot.add_child(_mi(_capsule(0.10 * limb, 0.36), pants_mat, Vector3(0.0, -0.17, 0.0), "Leg"))
		pivot.add_child(_mi(_capsule(0.082 * limb, 0.50), skin_mat, Vector3(0.0, -0.54, 0.0), "LowerLeg"))
	else:
		pivot.add_child(_mi(_capsule(0.10 * limb, HIP_Y), pants_mat, Vector3(0.0, -HIP_Y * 0.5, 0.0), "Leg"))
	if String(l["shoes"]) == "none":
		# Barfuß: flacher Fuß in Hautfarbe, ohne Sohle.
		pivot.add_child(_mi(_box(Vector3(0.14 * limb, 0.07, 0.25)), skin_mat, Vector3(0.0, -HIP_Y + 0.035, 0.05), "Foot"))
	else:
		pivot.add_child(_mi(_box(Vector3(0.16 * limb, 0.09, 0.28)), shoe_mat, Vector3(0.0, -HIP_Y + 0.045, 0.05), "Shoe"))
		# Sohle: dunkler, hauchdünner Streifen — gibt dem Schuh Kontur.
		pivot.add_child(_mi(_box(Vector3(0.164 * limb, 0.018, 0.288)), _mat(Color(0.10, 0.09, 0.09), 0.9), Vector3(0.0, -HIP_Y + 0.009, 0.05), "Sole"))
	return pivot

# ─────────────────────────────────────────────
# Primitive-Helfer
# ─────────────────────────────────────────────

## Primitive-Erzeugung/-Platzierung ist nach ProcGenShapes ausgelagert (gemeinsame Basis mit
## AnimalVisualBuilder/NPCVisualBuilder — siehe dortigen Klassenkommentar). Diese Wrapper
## bleiben als kurze, an dieser Datei gewohnte Namen erhalten, damit die ~80 Aufrufstellen
## unten unverändert bleiben; die eigentliche Geometrie-Erzeugung lebt nur noch an einer Stelle.
static func _mat(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	return ProcGenShapes.mat(color, roughness)

static func _mi(mesh: Mesh, mat: Material, pos: Vector3, node_name: String) -> MeshInstance3D:
	return ProcGenShapes.mi(mesh, mat, pos, node_name)

static func _sphere(radius: float, hemisphere: bool = false, segments: int = 16, rings: int = 8) -> SphereMesh:
	return ProcGenShapes.sphere(radius, hemisphere, segments, rings)

static func _capsule(radius: float, height: float) -> CapsuleMesh:
	return ProcGenShapes.capsule(radius, height)

static func _box(size: Vector3) -> BoxMesh:
	return ProcGenShapes.box(size)

static func _cylinder(top_r: float, bottom_r: float, height: float, segments: int = 12) -> CylinderMesh:
	return ProcGenShapes.cylinder(top_r, bottom_r, height, segments)

static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 8
	return t

## Dünner Balken von `a` nach `b` (Brillenbügel o. Ä.).
static func _bar(a: Vector3, b: Vector3, thickness: float, mat: Material, node_name: String) -> MeshInstance3D:
	var d := b - a
	var bar := _mi(_box(Vector3(thickness, thickness, d.length())), mat, (a + b) * 0.5, node_name)
	bar.basis = Basis.looking_at(d.normalized(), Vector3.UP)
	return bar

## Hautmaterial: etwas weniger Glanz als Standard, damit Haut nicht plastikartig spiegelt.
static func _skin_mat(color: Color) -> StandardMaterial3D:
	var m := _mat(color, 0.9)
	m.metallic_specular = 0.3
	return m

## Halbtransparentes Material (Brillengläser).
static func _glass_mat(color: Color) -> StandardMaterial3D:
	var m := _mat(color, 0.1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

## Farb-Override aus `overrides` (nur lokale Figuren, siehe build()) oder Katalogfarbe.
static func _ov(overrides: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = overrides.get(key, null)
	return v as Color if v is Color else fallback

## Setzt `node` auf die Kopfoberfläche (Kopfmitte = Ursprung der Gesichts-
## Gruppe): (x, y) = Position auf der Stirn-/Wangenebene, die Tiefe (z) ergibt
## sich aus der Kugelform. `lift` schiebt entlang der Oberflächennormale nach
## außen; +Z des Nodes zeigt aus dem Kopf heraus. `roll` dreht in der
## Tangentialebene, `node_scale` skaliert in lokalen Achsen.
static func _place(node: Node3D, x: float, y: float, lift: float, node_scale: Vector3 = Vector3.ONE, roll: float = 0.0) -> void:
	ProcGenShapes.place_on_sphere(node, HEAD_R, x, y, lift, node_scale, roll)
