class_name NPCProps
extends RefCounted

## NPCProps — Handrequisiten, Kopfbedeckungen und Zubehör für NPCs ("Drip").
##
## Alles wird aus Primitiven gebaut (wie der Rest der Figur) und an die Körperteile aus
## CharacterPartBuilder.build() gehängt. Rein kosmetisch, lokal, nie gespeichert.
## Welcher NPC was trägt, steht in NPCLook.PRESETS (Felder "prop", "extras", "cape",
## "ghost").
##
## Koordinaten: Hand-Requisiten leben in einem "Holder" an der Handmitte (Ursprung =
## Hand, +Y = Griffrichtung nach oben). Der Arm wird dafür leicht angehoben
## (negative rotation.x = nach vorn, siehe CharacterGaze/CharacterPartBuilder); der Holder
## dreht gegen, damit das Ding in der Welt aufrecht bleibt.
##
##   prop    : axe · pickaxe · staff · cane · orb_staff · spear · basket · sapling ·
##             ledger · megaphone · scroll
##             Berufs-Requisiten (siehe ProfessionCatalog): hammer · pot · quill · paddle · net ·
##             blowpipe · shuttle · sack · scraper · cloth · rake · wheel
##   extras  : hardhat · helm · tophat · pauldrons · scarf · backpack · pouch
##   cape    : Color — Umhang hinten
##   ghost   : bool — halbtransparent + leuchtend (Ahnengeist)

## Gültige IDs (für Tests/Validierung der Presets).
const PROP_IDS: Array = [
	"axe", "pickaxe", "staff", "cane", "orb_staff", "spear", "basket", "sapling", "ledger", "megaphone", "scroll",
	"hammer", "pot", "quill", "paddle", "net", "blowpipe", "shuttle", "sack", "scraper", "cloth", "rake", "wheel",
]

## Requisiten, die in der LINKEN Hand liegen (Körbe, Bücher, Gefäße, Stoff); alles andere rechts.
const LEFT_HAND_PROPS: Array = ["basket", "ledger", "scroll", "pot", "sack", "cloth", "wheel", "net"]
const EXTRA_IDS: Array = ["hardhat", "helm", "tophat", "pauldrons", "scarf", "backpack", "pouch"]

const STEEL := Color(0.62, 0.65, 0.70)
const DARK_STEEL := Color(0.30, 0.32, 0.36)
const WOOD := Color(0.42, 0.28, 0.15)
const LEATHER := Color(0.36, 0.22, 0.12)

## Zubehör anwenden. `parts` = Rückgabe von CharacterPartBuilder.build(); `spec` = Ergebnis
## von NPCLook.resolve().
static func apply(parts: Dictionary, look: Dictionary, spec: Dictionary) -> void:
	var root: Node3D = parts["root"]
	var head: Node3D = parts["head"]

	var cape_variant: Variant = spec.get("cape", null)
	if cape_variant is Color:
		root.add_child(_cape(cape_variant as Color, CharacterLook.torso_width(String(look["build"]))))

	for extra in (spec.get("extras", []) as Array):
		match String(extra):
			"hardhat":
				head.add_child(_hardhat())
			"helm":
				head.add_child(_helm())
			"tophat":
				head.add_child(_tophat())
			"pauldrons":
				_pauldrons(root, look)
			"scarf":
				_scarf(root)
			"backpack":
				root.add_child(_backpack())
			"pouch":
				root.add_child(_pouch())

	var prop_id := String(spec.get("prop", ""))
	if not prop_id.is_empty():
		_give_prop(parts, look, prop_id)

	if bool(spec.get("ghost", false)):
		make_ghost(root, Color(0.62, 0.55, 0.95))

## Halbtransparent + leuchtend: alle Meshes unterhalb von `root` (außer Brillengläsern etc.,
## die schon transparent sind).
static func make_ghost(root: Node, glow: Color) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var m := (n as MeshInstance3D).material_override as StandardMaterial3D
		if m == null or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.72
		m.emission_enabled = true
		m.emission = m.albedo_color.lerp(glow, 0.55)
		m.emission_energy_multiplier = 0.45

# ─────────────────────────────────────────────
# Handrequisiten
# ─────────────────────────────────────────────

static func _give_prop(parts: Dictionary, look: Dictionary, prop_id: String) -> void:
	# Welche Hand/Haltung: Werkzeuge rechts leicht vorn, Bücher/Körbe links.
	var left := prop_id in LEFT_HAND_PROPS
	var arm: Node3D = parts["arm_l"] if left else parts["arm_r"]
	var arm_rot := -0.30
	match prop_id:
		"ledger":
			arm_rot = -0.95
		"scroll":
			arm_rot = -0.65
		"megaphone":
			arm_rot = -1.45
		"basket":
			arm_rot = -0.20
		"spear", "staff", "orb_staff", "cane", "rake", "paddle":
			arm_rot = -0.18
		"pot", "sack", "cloth", "wheel", "net":
			arm_rot = -0.35
		"quill":
			arm_rot = -0.70
		"blowpipe":
			arm_rot = -1.20

	var holder := Node3D.new()
	holder.name = "Prop_" + prop_id
	holder.position = Vector3(0.0, -CharacterPartBuilder.ARM_LEN, 0.0)
	arm.rotation.x = arm_rot
	holder.rotation.x = -arm_rot
	arm.add_child(holder)

	match prop_id:
		"axe":
			_axe(holder)
		"pickaxe":
			_pickaxe(holder)
		"staff":
			_staff(holder, 1.75, true)
		"cane":
			_cane(holder)
		"orb_staff":
			_orb_staff(holder)
		"spear":
			_spear(holder)
		"basket":
			_basket(holder)
		"sapling":
			_sapling(holder)
		"ledger":
			_ledger(holder)
		"megaphone":
			_megaphone(holder)
			holder.rotation.x = -arm_rot + PI * 0.5   # zeigt nach vorn (+Z)
		"scroll":
			_scroll(holder)
		"hammer":
			_hammer(holder)
		"pot":
			_pot(holder)
		"quill":
			_quill(holder)
		"paddle":
			_paddle(holder)
		"net":
			_net(holder)
		"blowpipe":
			_blowpipe(holder)
			holder.rotation.x = -arm_rot + PI * 0.5   # zeigt nach vorn (+Z)
		"shuttle":
			_shuttle(holder)
		"sack":
			_sack(holder)
		"scraper":
			_scraper(holder)
		"cloth":
			_cloth(holder)
		"rake":
			_rake(holder)
		"wheel":
			_wheel(holder)

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

static func _axe(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.026, 0.026, 0.95), _m(WOOD), Vector3(0.0, 0.20, 0.0), "Handle")
	_add(h, ProcGenShapes.box(Vector3(0.05, 0.17, 0.12)), _m(DARK_STEEL, 0.5), Vector3(0.0, 0.62, 0.05), "HeadBlock")
	var blade := _add(h, ProcGenShapes.box(Vector3(0.012, 0.22, 0.14)), _m(STEEL, 0.35), Vector3(0.0, 0.62, 0.15), "Blade")
	blade.rotation.x = 0.0

static func _pickaxe(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.026, 0.026, 0.92), _m(WOOD), Vector3(0.0, 0.18, 0.0), "Handle")
	_add(h, ProcGenShapes.box(Vector3(0.045, 0.055, 0.46)), _m(DARK_STEEL, 0.5), Vector3(0.0, 0.64, 0.0), "Head")
	var tip_f := _add(h, ProcGenShapes.cone(0.032, 0.14, 8), _m(STEEL, 0.4), Vector3(0.0, 0.64, 0.30), "TipFront")
	tip_f.rotation.x = PI * 0.5
	var tip_b := _add(h, ProcGenShapes.cone(0.032, 0.14, 8), _m(STEEL, 0.4), Vector3(0.0, 0.64, -0.30), "TipBack")
	tip_b.rotation.x = -PI * 0.5

static func _staff(h: Node3D, length: float, bands: bool) -> void:
	_add(h, ProcGenShapes.cylinder(0.022, 0.022, length), _m(WOOD), Vector3(0.0, length * 0.5 - 0.35, 0.0), "Shaft")
	if bands:
		var band_mat := _m(Color(0.62, 0.14, 0.12), 0.7)
		_add(h, ProcGenShapes.cylinder(0.028, 0.028, 0.07), band_mat, Vector3(0.0, length - 0.42, 0.0), "BandTop")
		_add(h, ProcGenShapes.cylinder(0.028, 0.028, 0.07), band_mat, Vector3(0.0, -0.28, 0.0), "BandBottom")

static func _cane(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.022, 0.026, 1.05), _m(WOOD), Vector3(0.0, 0.17, 0.0), "Shaft")
	_add(h, ProcGenShapes.sphere(0.04, false, 10, 6), _m(Color(0.80, 0.66, 0.25), 0.4), Vector3(0.0, 0.71, 0.0), "Knob")

static func _orb_staff(h: Node3D) -> void:
	_staff(h, 1.85, false)
	var top := 1.85 - 0.35
	var ring := _add(h, ProcGenShapes.cylinder(0.05, 0.03, 0.06, 12), _m(Color(0.80, 0.66, 0.25), 0.4), Vector3(0.0, top - 0.03, 0.0), "Cradle")
	ring.name = "Cradle"
	_add(h, ProcGenShapes.sphere(0.075, false, 14, 8), _glow_mat(Color(0.70, 0.60, 1.0), 2.2), Vector3(0.0, top + 0.07, 0.0), "Orb")

static func _spear(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.02, 0.02, 2.0), _m(WOOD), Vector3(0.0, 0.62, 0.0), "Shaft")
	_add(h, ProcGenShapes.cone(0.04, 0.24, 8), _m(STEEL, 0.3), Vector3(0.0, 1.74, 0.0), "Tip")
	_add(h, ProcGenShapes.box(Vector3(0.05, 0.12, 0.012)), _m(Color(0.70, 0.18, 0.16), 0.9), Vector3(0.0, 1.56, 0.03), "Pennant")

static func _basket(h: Node3D) -> void:
	var wicker := _m(Color(0.62, 0.46, 0.24), 0.95)
	_add(h, ProcGenShapes.cylinder(0.17, 0.12, 0.17, 14), wicker, Vector3(0.0, -0.14, 0.0), "Basket")
	var handle := _add(h, _torus(0.115, 0.135), wicker, Vector3(0.0, -0.03, 0.0), "BasketHandle")
	handle.rotation.x = PI * 0.5
	var leaf := _m(Color(0.30, 0.58, 0.28), 0.9)
	for i in 5:
		var a := TAU * float(i) / 5.0
		_add(h, ProcGenShapes.sphere(0.05, false, 8, 4), leaf, Vector3(sin(a) * 0.07, -0.05, cos(a) * 0.07), "Herb%d" % i)
	_add(h, ProcGenShapes.sphere(0.028, false, 8, 4), _m(Color(0.92, 0.45, 0.60), 0.8), Vector3(0.05, -0.02, 0.03), "FlowerPink")
	_add(h, ProcGenShapes.sphere(0.026, false, 8, 4), _m(Color(0.95, 0.82, 0.30), 0.8), Vector3(-0.05, -0.02, -0.03), "FlowerYellow")

static func _sapling(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.014, 0.018, 0.55), _m(WOOD), Vector3(0.0, 0.12, 0.0), "Trunk")
	_add(h, ProcGenShapes.sphere(0.075, false, 10, 6), _m(Color(0.30, 0.20, 0.12), 0.95), Vector3(0.0, -0.17, 0.0), "RootBall")
	var leaf := _m(Color(0.28, 0.58, 0.26), 0.9)
	_add(h, ProcGenShapes.sphere(0.10, false, 10, 6), leaf, Vector3(0.0, 0.43, 0.0), "LeafTop")
	_add(h, ProcGenShapes.sphere(0.07, false, 8, 4), leaf, Vector3(0.07, 0.33, 0.03), "LeafSide")
	_add(h, ProcGenShapes.sphere(0.065, false, 8, 4), leaf, Vector3(-0.06, 0.31, -0.03), "LeafSide2")

static func _ledger(h: Node3D) -> void:
	var book := Node3D.new()
	book.name = "Book"
	book.rotation.x = -0.5
	h.add_child(book)
	_add(book, ProcGenShapes.box(Vector3(0.17, 0.045, 0.23)), _m(Color(0.48, 0.12, 0.14), 0.7), Vector3(0.0, 0.0, 0.08), "Cover")
	_add(book, ProcGenShapes.box(Vector3(0.15, 0.03, 0.21)), _m(Color(0.94, 0.92, 0.84), 0.9), Vector3(0.01, 0.0, 0.085), "Pages")
	_add(book, ProcGenShapes.box(Vector3(0.012, 0.05, 0.23)), _m(Color(0.80, 0.66, 0.25), 0.4), Vector3(-0.085, 0.0, 0.08), "Spine")

static func _megaphone(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.14, 0.04, 0.34, 16), _m(Color(0.78, 0.26, 0.20), 0.5), Vector3(0.0, 0.14, 0.0), "Horn")
	_add(h, ProcGenShapes.cylinder(0.145, 0.145, 0.03, 16), _m(Color(0.95, 0.93, 0.88), 0.5), Vector3(0.0, 0.30, 0.0), "Rim")
	_add(h, ProcGenShapes.box(Vector3(0.035, 0.12, 0.045)), _m(DARK_STEEL, 0.6), Vector3(0.0, -0.02, 0.0), "Grip")

static func _scroll(h: Node3D) -> void:
	var roll := _add(h, ProcGenShapes.cylinder(0.04, 0.04, 0.32, 12), _m(Color(0.93, 0.87, 0.70), 0.9), Vector3.ZERO, "Map")
	roll.rotation.z = PI * 0.5
	var ribbon := _add(h, ProcGenShapes.cylinder(0.046, 0.046, 0.035, 12), _m(Color(0.72, 0.18, 0.16), 0.7), Vector3(0.07, 0.0, 0.0), "Ribbon")
	ribbon.rotation.z = PI * 0.5

# ─────────────────────────────────────────────
# Berufs-Requisiten (Töpfer, Schreiber, Glasmacher ...) — siehe ProfessionCatalog
# ─────────────────────────────────────────────

static func _hammer(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.024, 0.024, 0.62), _m(WOOD), Vector3(0.0, 0.12, 0.0), "Handle")
	_add(h, ProcGenShapes.box(Vector3(0.08, 0.10, 0.20)), _m(DARK_STEEL, 0.45), Vector3(0.0, 0.46, 0.04), "Head")

static func _pot(h: Node3D) -> void:
	var clay := _m(Color(0.70, 0.38, 0.22), 0.95)
	_add(h, ProcGenShapes.sphere(0.13, false, 12, 8), clay, Vector3(0.0, -0.12, 0.0), "PotBody")
	_add(h, ProcGenShapes.cylinder(0.075, 0.085, 0.07, 12), clay, Vector3(0.0, 0.0, 0.0), "PotNeck")
	_add(h, ProcGenShapes.cylinder(0.095, 0.095, 0.02, 12), _m(Color(0.58, 0.30, 0.17), 0.95), Vector3(0.0, 0.04, 0.0), "PotRim")

static func _quill(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.008, 0.012, 0.34), _m(Color(0.94, 0.92, 0.86), 0.8), Vector3(0.0, 0.10, 0.0), "Feather")
	_add(h, ProcGenShapes.cone(0.03, 0.18, 6), _m(Color(0.90, 0.88, 0.80), 0.8), Vector3(0.02, 0.30, 0.0), "Vane")
	_add(h, ProcGenShapes.cone(0.008, 0.05, 6), _m(DARK_STEEL, 0.4), Vector3(0.0, -0.10, 0.0), "Nib")

static func _paddle(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.022, 0.022, 1.0), _m(WOOD), Vector3(0.0, 0.15, 0.0), "Shaft")
	_add(h, ProcGenShapes.box(Vector3(0.20, 0.30, 0.025)), _m(Color(0.55, 0.40, 0.22), 0.9), Vector3(0.0, 0.76, 0.0), "Blade")

static func _net(h: Node3D) -> void:
	var rope := _m(Color(0.74, 0.66, 0.46), 0.95)
	var ring := _add(h, _torus(0.16, 0.18), rope, Vector3(0.0, 0.0, 0.08), "NetRing")
	ring.rotation.x = PI * 0.5
	_add(h, ProcGenShapes.cylinder(0.05, 0.03, 0.18, 8), rope, Vector3(0.0, -0.16, 0.08), "NetBag")
	_add(h, ProcGenShapes.sphere(0.035, false, 8, 4), _m(Color(0.62, 0.62, 0.66), 0.5), Vector3(0.0, -0.27, 0.08), "Sinker")

static func _blowpipe(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.014, 0.014, 1.3), _m(DARK_STEEL, 0.5), Vector3(0.0, 0.35, 0.0), "Pipe")
	_add(h, ProcGenShapes.sphere(0.07, false, 10, 6), _glow_mat(Color(1.0, 0.55, 0.20), 2.0), Vector3(0.0, 1.02, 0.0), "Gather")

static func _shuttle(h: Node3D) -> void:
	_add(h, ProcGenShapes.box(Vector3(0.05, 0.05, 0.34)), _m(WOOD), Vector3(0.0, 0.05, 0.0), "Shuttle")
	_add(h, ProcGenShapes.cylinder(0.035, 0.035, 0.12, 8), _m(Color(0.85, 0.80, 0.62), 0.95), Vector3(0.0, 0.10, 0.0), "Thread")

static func _sack(h: Node3D) -> void:
	var burlap := _m(Color(0.74, 0.62, 0.40), 0.98)
	_add(h, ProcGenShapes.sphere(0.15, false, 10, 8), burlap, Vector3(0.0, -0.14, 0.0), "SackBody")
	_add(h, ProcGenShapes.cylinder(0.06, 0.09, 0.08, 8), burlap, Vector3(0.0, 0.02, 0.0), "SackNeck")
	_add(h, ProcGenShapes.cylinder(0.075, 0.075, 0.02, 8), _m(Color(0.40, 0.26, 0.14), 0.9), Vector3(0.0, 0.0, 0.0), "SackTie")

static func _scraper(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.022, 0.022, 0.40), _m(WOOD), Vector3(0.0, 0.05, 0.0), "Handle")
	_add(h, ProcGenShapes.box(Vector3(0.20, 0.07, 0.015)), _m(STEEL, 0.4), Vector3(0.0, 0.27, 0.0), "Blade")

static func _cloth(h: Node3D) -> void:
	_add(h, ProcGenShapes.box(Vector3(0.22, 0.34, 0.03)), _m(Color(0.62, 0.22, 0.58), 0.95), Vector3(0.0, -0.18, 0.0), "Cloth")
	_add(h, ProcGenShapes.box(Vector3(0.22, 0.06, 0.035)), _m(Color(0.85, 0.70, 0.20), 0.95), Vector3(0.0, -0.06, 0.0), "Band")

static func _rake(h: Node3D) -> void:
	_add(h, ProcGenShapes.cylinder(0.022, 0.022, 1.45), _m(WOOD), Vector3(0.0, 0.40, 0.0), "Shaft")
	_add(h, ProcGenShapes.box(Vector3(0.46, 0.05, 0.05)), _m(WOOD), Vector3(0.0, 1.12, 0.0), "Head")
	for i in 5:
		_add(h, ProcGenShapes.box(Vector3(0.025, 0.10, 0.025)), _m(DARK_STEEL, 0.5), Vector3(-0.18 + 0.09 * float(i), 1.07, 0.0), "Tine%d" % i)

static func _wheel(h: Node3D) -> void:
	var wood := _m(WOOD)
	var rim := _add(h, _torus(0.17, 0.21), wood, Vector3(0.0, -0.05, 0.10), "Rim")
	rim.rotation.x = PI * 0.5   # Scheibe in der XY-Ebene, Achse nach vorn (+Z)
	var hub := _add(h, ProcGenShapes.cylinder(0.05, 0.05, 0.08, 10), _m(LEATHER), Vector3(0.0, -0.05, 0.10), "Hub")
	hub.rotation.x = PI * 0.5
	for k in 3:
		var spoke := _add(h, ProcGenShapes.box(Vector3(0.025, 0.40, 0.025)), wood, Vector3(0.0, -0.05, 0.10), "Spoke%d" % k)
		spoke.rotation.z = PI * float(k) / 3.0

# ─────────────────────────────────────────────
# Kopfbedeckungen (Kinder von "Head" → drehen beim Umsehen mit)
# ─────────────────────────────────────────────

static func _hardhat() -> Node3D:
	return WornGearBuilder.make_hardhat()

static func _helm() -> Node3D:
	var n := Node3D.new()
	n.name = "Hat"
	var steel := _m(STEEL, 0.35)
	var dome := _add(n, ProcGenShapes.sphere(0.225, true, 20, 8), steel, Vector3(0.0, 0.035, -0.01), "Dome")
	dome.rotation.x = -0.22
	_add(n, ProcGenShapes.box(Vector3(0.035, 0.13, 0.02)), _m(DARK_STEEL, 0.4), Vector3(0.0, 0.07, 0.205), "NoseGuard")
	_add(n, ProcGenShapes.box(Vector3(0.03, 0.04, 0.34)), _m(Color(0.70, 0.18, 0.16), 0.8), Vector3(0.0, 0.265, -0.02), "Crest")
	var rim := _add(n, ProcGenShapes.cylinder(0.226, 0.226, 0.03, 20), _m(DARK_STEEL, 0.4), Vector3(0.0, 0.05, -0.005), "Rim")
	rim.rotation.x = -0.22
	return n

static func _tophat() -> Node3D:
	return WornGearBuilder.make_tophat()

# ─────────────────────────────────────────────
# Körper-Zubehör
# ─────────────────────────────────────────────

static func _pauldrons(root: Node3D, look: Dictionary) -> void:
	WornGearBuilder.make_pauldrons(root, CharacterPartBuilder.shoulder_x(look))

static func _scarf(root: Node3D) -> void:
	WornGearBuilder.make_scarf(root, Color(0.78, 0.22, 0.20))

static func _backpack() -> Node3D:
	return WornGearBuilder.make_backpack()

static func _pouch() -> Node3D:
	return WornGearBuilder.make_pouch()

static func _cape(color: Color, torso_w: float) -> Node3D:
	return WornGearBuilder.make_cape(color, torso_w)

static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 8
	return t
