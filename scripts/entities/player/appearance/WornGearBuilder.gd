class_name WornGearBuilder
extends RefCounted

## WornGearBuilder — zeichnet das, was ÜBER dem nackten/bekleideten Grundkörper getragen wird:
## Schal, Rucksack/Umhang, Beutel, Schulterplatten und die vier Rüstungsteile (Helm, Brustpanzer,
## Beinschutz, Stiefel). Die Grundkleidung (Oberteil, Hose, Schuhe, Hut, Brille, Gürtel) baut
## CharacterPartBuilder selbst, weil sie mit dem Körper verwachsen ist (Ärmel, Hosenbeine).
##
## Gleiche Teile für Spieler UND NPCs: CharacterPartBuilder.build() ruft apply() am Ende auf,
## NPCProps (Legacy-"extras") nutzt dieselben Fabriken. Rein statisch, nur ProcGenShapes + Look.
##
## `shape` kommt von CharacterPartBuilder (so hängt diese Klasse nicht zurück an ihm — GDScript
## mag keine zyklischen Klassen-Abhängigkeiten): { sx, tw, sw, bust, limb, hw, hip_y,
## torso_y, torso_x, torso_z }.

const STEEL := Color(0.62, 0.65, 0.70)
const DARK_STEEL := Color(0.30, 0.32, 0.36)
const LEATHER := Color(0.36, 0.22, 0.12)

## Rüstungs-Material je Tier (CharacterLook.CATALOG[armor_*].tier).
const TIER_COLORS: Dictionary = {
	"copper": Color(0.72, 0.44, 0.28),
	"iron":   Color(0.50, 0.52, 0.56),
	"steel":  Color(0.74, 0.78, 0.84),
}
const TIER_METALLIC: Dictionary = {"copper": 0.55, "iron": 0.60, "steel": 0.72}

## Zubehör + Rüstung an `parts` (Rückgabe von CharacterPartBuilder.build()) anbringen.
static func apply(parts: Dictionary, l: Dictionary, shape: Dictionary) -> void:
	var root := parts["root"] as Node3D
	var head := parts["head"] as Node3D

	# ── Kleidungs-Zubehör ──
	var scarf_id := String(l.get("scarf", "none"))
	if scarf_id != "none":
		make_scarf(root, CharacterLook.color_of("scarf", scarf_id))
	var back_id := String(l.get("back", "none"))
	if back_id == "backpack":
		root.add_child(make_backpack())
	elif back_id.begins_with("cape_"):
		root.add_child(make_cape(CharacterLook.color_of("back", back_id), float(shape["tw"])))
	if String(l.get("pouch", "none")) != "none":
		root.add_child(make_pouch())
	if String(l.get("shoulders", "none")) != "none":
		make_pauldrons(root, float(shape["sx"]))

	# ── Rüstung (über der Kleidung) ──
	var helmet_id := String(l.get("armor_helmet", "none"))
	if helmet_id != "none":
		head.add_child(make_helmet(_tier("armor_helmet", helmet_id)))
		# Unter einem Helm sind Haare und Hut unsichtbar (sonst stechen sie durch).
		var hair := parts.get("hair", null) as Node3D
		if is_instance_valid(hair):
			hair.visible = false
		var hat := parts.get("hat", null) as Node3D
		if is_instance_valid(hat):
			hat.visible = false

	var chest_id := String(l.get("armor_chest", "none"))
	if chest_id != "none":
		root.add_child(make_chest(_tier("armor_chest", chest_id), shape))

	var legs_id := String(l.get("armor_legs", "none"))
	if legs_id != "none":
		var legs_tier := _tier("armor_legs", legs_id)
		root.add_child(make_faulds(legs_tier, shape))
		_add_leg_armor(parts.get("leg_r", null), legs_tier, shape)
		_add_leg_armor(parts.get("leg_l", null), legs_tier, shape)

	var boots_id := String(l.get("armor_boots", "none"))
	if boots_id != "none":
		var boots_tier := _tier("armor_boots", boots_id)
		_add_boots(parts.get("leg_r", null), boots_tier, shape)
		_add_boots(parts.get("leg_l", null), boots_tier, shape)

# ─────────────────────────────────────────────
# Rüstung
# ─────────────────────────────────────────────

static func armor_mat(tier: String, darker: bool = false) -> StandardMaterial3D:
	var col: Color = TIER_COLORS.get(tier, TIER_COLORS["iron"])
	var m := _m(col.darkened(0.30) if darker else col, 0.38)
	m.metallic = float(TIER_METALLIC.get(tier, 0.6))
	return m

static func make_helmet(tier: String) -> Node3D:
	var n := Node3D.new()
	n.name = "ArmorHelmet"
	var mat := armor_mat(tier)
	var dark := armor_mat(tier, true)
	var dome := _add(n, ProcGenShapes.sphere(0.234, true, 20, 8), mat, Vector3(0.0, 0.03, -0.01), "Dome")
	dome.rotation.x = -0.22
	var rim := _add(n, ProcGenShapes.cylinder(0.236, 0.236, 0.035, 20), dark, Vector3(0.0, 0.045, -0.005), "Rim")
	rim.rotation.x = -0.22
	_add(n, ProcGenShapes.box(Vector3(0.035, 0.14, 0.02)), dark, Vector3(0.0, 0.07, 0.215), "NoseGuard")
	if tier == "steel":
		_add(n, ProcGenShapes.box(Vector3(0.03, 0.04, 0.34)), _m(Color(0.70, 0.18, 0.16), 0.8), Vector3(0.0, 0.27, -0.02), "Crest")
	return n

static func make_chest(tier: String, shape: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = "ArmorChest"
	var mat := armor_mat(tier)
	var dark := armor_mat(tier, true)
	var torso_y := float(shape["torso_y"])
	var plate := _add(n, ProcGenShapes.capsule(0.2, 0.60), mat, Vector3(0.0, torso_y, 0.0), "Plate")
	# Tiefer als der Rumpf, bei Brust (bust) noch etwas mehr — sonst sticht sie durch.
	plate.scale = Vector3(float(shape["torso_x"]), 1.0, float(shape["torso_z"]) * (1.0 + 0.30 * float(shape["bust"])))
	_add(n, ProcGenShapes.box(Vector3(0.03, 0.40, 0.02)), dark, Vector3(0.0, torso_y + 0.02, float(shape["torso_z"]) * 0.2 * (1.0 + 0.30 * float(shape["bust"])) + 0.012), "Ridge")
	_add(n, _torus(0.05, 0.09), dark, Vector3(0.0, 1.43, 0.0), "Gorget")
	return n

## Beckenschutz — gehört zum Beinschutz-Slot und schließt die Lücke zwischen Brustpanzer und Beinen.
static func make_faulds(tier: String, shape: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = "ArmorFaulds"
	var f := _add(n, ProcGenShapes.capsule(0.124, 0.44 * float(shape["tw"]) * float(shape["hw"]) + 0.08), armor_mat(tier), Vector3(0.0, float(shape["hip_y"]) + 0.02, 0.0), "Faulds")
	f.rotation.z = PI * 0.5
	return n

static func _add_leg_armor(leg: Variant, tier: String, shape: Dictionary) -> void:
	if not (leg is Node3D):
		return
	var limb := float(shape["limb"])
	var hip_y := float(shape["hip_y"])
	var span := hip_y - 0.18
	var mat := armor_mat(tier)
	(leg as Node3D).add_child(ProcGenShapes.mi(ProcGenShapes.capsule(0.108 * limb, span), mat, Vector3(0.0, -span * 0.5, 0.0), "ArmorLeg"))
	var knee := ProcGenShapes.mi(ProcGenShapes.sphere(0.07 * limb, false, 10, 6), armor_mat(tier, true), Vector3(0.0, -0.42, 0.075 * limb), "ArmorKnee")
	knee.scale = Vector3(1.0, 1.0, 0.7)
	(leg as Node3D).add_child(knee)

static func _add_boots(leg: Variant, tier: String, shape: Dictionary) -> void:
	if not (leg is Node3D):
		return
	var limb := float(shape["limb"])
	var hip_y := float(shape["hip_y"])
	var mat := armor_mat(tier)
	var pivot := leg as Node3D
	pivot.add_child(ProcGenShapes.mi(ProcGenShapes.box(Vector3(0.18 * limb, 0.16, 0.31)), mat, Vector3(0.0, -hip_y + 0.08, 0.05), "ArmorBoot"))
	pivot.add_child(ProcGenShapes.mi(ProcGenShapes.cylinder(0.098 * limb, 0.098 * limb, 0.10), mat, Vector3(0.0, -hip_y + 0.21, 0.0), "ArmorCuff"))
	pivot.add_child(ProcGenShapes.mi(ProcGenShapes.box(Vector3(0.184 * limb, 0.02, 0.318)), armor_mat(tier, true), Vector3(0.0, -hip_y + 0.01, 0.05), "ArmorSole"))

static func _tier(field: String, id: String) -> String:
	return String(CharacterLook.get_entry(field, id).get("tier", "iron"))

# ─────────────────────────────────────────────
# Kleidungs-Zubehör (auch von NPCProps genutzt)
# ─────────────────────────────────────────────

static func make_hardhat() -> Node3D:
	var n := Node3D.new()
	n.name = "Hat"
	var yellow := _m(Color(0.92, 0.72, 0.15), 0.5)
	var dome := _add(n, ProcGenShapes.sphere(0.226, true, 20, 8), yellow, Vector3(0.0, 0.04, -0.01), "Dome")
	dome.rotation.x = -0.25
	_add(n, ProcGenShapes.box(Vector3(0.05, 0.02, 0.36)), _m(Color(0.92, 0.72, 0.15), 0.5), Vector3(0.0, 0.245, -0.01), "Ridge")
	var brim := _add(n, ProcGenShapes.box(Vector3(0.40, 0.012, 0.12)), yellow, Vector3(0.0, 0.07, 0.21), "Brim")
	brim.rotation.x = 0.14
	_add(n, ProcGenShapes.cylinder(0.04, 0.04, 0.04, 12), _m(DARK_STEEL, 0.4), Vector3(0.0, 0.14, 0.235), "LampHousing").rotation.x = PI * 0.5
	_add(n, ProcGenShapes.sphere(0.03, false, 10, 6), _glow_mat(Color(1.0, 0.95, 0.65), 2.5), Vector3(0.0, 0.14, 0.26), "Lamp")
	return n

static func make_tophat() -> Node3D:
	var n := Node3D.new()
	n.name = "Hat"
	var black := _m(Color(0.09, 0.09, 0.11), 0.6)
	_add(n, ProcGenShapes.cylinder(0.27, 0.27, 0.016, 24), black, Vector3(0.0, 0.17, 0.0), "Brim")
	_add(n, ProcGenShapes.cylinder(0.155, 0.17, 0.27, 20), black, Vector3(0.0, 0.305, 0.0), "Crown")
	_add(n, ProcGenShapes.cylinder(0.172, 0.172, 0.045, 20), _m(Color(0.80, 0.66, 0.25), 0.4), Vector3(0.0, 0.215, 0.0), "Band")
	return n

static func make_scarf(root: Node3D, color: Color) -> void:
	var mat := _m(color, 0.95)
	_add(root, _torus(0.058, 0.118), mat, Vector3(0.0, 1.415, 0.0), "Scarf")
	var tail := _add(root, ProcGenShapes.box(Vector3(0.075, 0.30, 0.03)), mat, Vector3(0.085, 1.27, 0.15), "ScarfTail")
	tail.rotation.z = -0.08

static func make_backpack() -> Node3D:
	var n := Node3D.new()
	n.name = "Backpack"
	_add(n, ProcGenShapes.box(Vector3(0.34, 0.42, 0.17)), _m(LEATHER, 0.9), Vector3(0.0, 1.08, -0.26), "Pack")
	_add(n, ProcGenShapes.box(Vector3(0.30, 0.10, 0.04)), _m(Color(0.30, 0.18, 0.10), 0.9), Vector3(0.0, 1.20, -0.355), "Flap")
	var roll := _add(n, ProcGenShapes.cylinder(0.075, 0.075, 0.42, 12), _m(Color(0.76, 0.66, 0.46), 0.95), Vector3(0.0, 1.36, -0.27), "Bedroll")
	roll.rotation.z = PI * 0.5
	var pot := _add(n, ProcGenShapes.cylinder(0.06, 0.06, 0.09, 12), _m(DARK_STEEL, 0.5), Vector3(0.14, 0.92, -0.37), "Pot")
	pot.rotation.x = PI * 0.5
	return n

static func make_pouch() -> Node3D:
	var n := Node3D.new()
	n.name = "Pouch"
	_add(n, ProcGenShapes.sphere(0.055, false, 10, 6), _m(LEATHER, 0.9), Vector3(-0.20, 0.92, 0.07), "Bag")
	_add(n, ProcGenShapes.cylinder(0.022, 0.022, 0.008, 10), _m(Color(0.88, 0.72, 0.22), 0.3), Vector3(-0.215, 0.99, 0.085), "Coin").rotation.z = PI * 0.5
	return n

static func make_cape(color: Color, torso_w: float) -> Node3D:
	var n := Node3D.new()
	n.name = "Cape"
	var mat := _m(color, 0.9)
	var width := 0.40 * torso_w + 0.10
	var panel := _add(n, ProcGenShapes.box(Vector3(width, 0.95, 0.03)), mat, Vector3(0.0, 0.98, -0.20), "Panel")
	panel.rotation.x = 0.07
	_add(n, ProcGenShapes.box(Vector3(width + 0.06, 0.07, 0.07)), _m(color.darkened(0.25), 0.9), Vector3(0.0, 1.44, -0.17), "Collar")
	return n

## Schulterplatten; `shoulder_x` = X-Abstand des Schultergelenks (CharacterPartBuilder.shoulder_x).
static func make_pauldrons(root: Node3D, shoulder_x: float) -> void:
	for side in [1.0, -1.0]:
		var p := _add(root, ProcGenShapes.sphere(0.105, false, 12, 6), _m(STEEL, 0.35), Vector3(side * (shoulder_x + 0.01), 1.38, 0.0), "PauldronR" if side > 0.0 else "PauldronL")
		p.scale = Vector3(1.0, 0.62, 1.05)
		_add(root, ProcGenShapes.cylinder(0.075, 0.075, 0.02, 12), _m(Color(0.80, 0.66, 0.25), 0.4), Vector3(side * (shoulder_x + 0.01), 1.33, 0.0), "TrimR" if side > 0.0 else "TrimL")

# ─────────────────────────────────────────────
# Helfer
# ─────────────────────────────────────────────

static func _m(color: Color, rough: float = 0.8) -> StandardMaterial3D:
	return ProcGenShapes.mat(color, rough)

static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, node_name: String) -> MeshInstance3D:
	var mi := ProcGenShapes.mi(mesh, mat, pos, node_name)
	parent.add_child(mi)
	return mi

static func _glow_mat(color: Color, energy: float = 1.6) -> StandardMaterial3D:
	var m := _m(color, 0.3)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 8
	return t
