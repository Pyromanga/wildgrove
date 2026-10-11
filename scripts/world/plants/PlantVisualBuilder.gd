class_name PlantVisualBuilder
extends RefCounted

## PlantVisualBuilder — baut aus PlantCatalog-"look" eine kleine Pflanze aus Primitiven.
## Sieben Stile decken die zwölf Arten ab; Farben/Höhe kommen aus der Tabelle:
##   daisy   Stiel + Blütenblätter-Kranz + Mitte   (Kamille, Kornblume, Ringelblume, Sonnenblume)
##   umbel   Stiel + flache Dolde                    (Schafgarbe, Mädesüß)
##   rosette Blattrosette + Stiel mit Kopf           (Löwenzahn)
##   nettle  aufrechter Stängel mit Blattpaaren      (Brennnessel)
##   cushion niedriges Polster mit Blütentupfen      (Thymian)
##   cup     Stiel + Blütenschale mit dunkler Mitte  (Klatschmohn, Tulpe)
##   spike   Blattbusch + violette Ähren             (Lavendel)
## Keine Kollision (wie Fern) — Interaktion läuft über die InteractableComponent.

const LEAF := Color(0.18, 0.42, 0.14)
static var _mats: Dictionary = {}

static func build(root: Node3D, look: Dictionary) -> void:
	var style: String = String(look.get("style", "daisy"))
	var h: float = float(look.get("height", 0.4))
	var c1: Color = look.get("color", Color.WHITE)
	var c2: Color = look.get("center", Color(0.95, 0.8, 0.15))
	match style:
		"daisy":
			_stem(root, h, 0.0, 0.0)
			_leaves(root, 3, 0.12, 0.0)
			var head_r: float = 0.05 + h * 0.06
			for i in range(8):
				var a: float = float(i) * TAU / 8.0
				_box(root, Vector3(head_r * 0.9, 0.012, head_r * 0.45),
					Vector3(cos(a) * head_r * 0.85, h, sin(a) * head_r * 0.85), c1, -a)
			_sphere(root, head_r * 0.45, Vector3(0.0, h + 0.005, 0.0), c2, 0.7)
		"umbel":
			_stem(root, h, 0.0, 0.0)
			_leaves(root, 4, 0.18, 0.0)
			_sphere(root, 0.11, Vector3(0.0, h, 0.0), c1, 0.32)
			for i in range(5):
				var a: float = float(i) * TAU / 5.0
				_sphere(root, 0.05, Vector3(cos(a) * 0.08, h - 0.03, sin(a) * 0.08), c1, 0.45)
		"rosette":
			for i in range(9):
				var a: float = float(i) * TAU / 9.0
				_box(root, Vector3(0.20, 0.012, 0.055), Vector3(cos(a) * 0.10, 0.02, sin(a) * 0.10), LEAF, -a)
			_stem(root, 0.22, 0.0, 0.0)
			_sphere(root, 0.05, Vector3(0.0, 0.23, 0.0), c1, 0.8)
		"nettle":
			_stem(root, h, 0.0, 0.0)
			for i in range(4):
				var y: float = 0.12 + float(i) * 0.15
				var yaw: float = float(i) * 0.9
				_box(root, Vector3(0.16, 0.012, 0.075), Vector3(0.08, y, 0.0), c1, yaw)
				_box(root, Vector3(0.16, 0.012, 0.075), Vector3(-0.08, y + 0.05, 0.0), c1.darkened(0.1), yaw)
		"cushion":
			_sphere(root, 0.22, Vector3(0.0, 0.06, 0.0), c1, 0.5)
			for i in range(8):
				var a: float = float(i) * TAU / 8.0 + 0.4
				_sphere(root, 0.02, Vector3(cos(a) * 0.12, 0.15, sin(a) * 0.12), c2, 1.0)
		"cup":
			_stem(root, h, 0.0, 0.0)
			_leaves(root, 3, 0.1, 0.0)
			_sphere(root, 0.06, Vector3(0.0, h + 0.02, 0.0), c1, 0.8)
			_sphere(root, 0.018, Vector3(0.0, h + 0.06, 0.0), c2, 1.0)
		"spike":
			_sphere(root, 0.16, Vector3(0.0, 0.07, 0.0), LEAF, 0.5)
			for i in range(5):
				var a: float = float(i) * TAU / 5.0
				var sx: float = cos(a) * 0.07
				var sz: float = sin(a) * 0.07
				_cylinder(root, 0.008, h, Vector3(sx, h * 0.5, sz), LEAF)
				_capsule(root, 0.022, 0.2, Vector3(sx, h + 0.06, sz), c1)
		_:
			_sphere(root, 0.1, Vector3(0.0, 0.1, 0.0), c1, 1.0)

## Strauch (BushCatalog): mehrere Blattkugeln, aufrechte Ruten (hell-braun) und Früchte als kleine Kugeln
## auf der Oberfläche. `seed` streut die Fruchtpositionen deterministisch (aus der Position), damit
## jeder Strauch etwas anders aussieht, aber auf jedem Peer gleich.
static func build_bush(root: Node3D, look: Dictionary, seed: int) -> void:
	var leaf: Color = look.get("leaf", LEAF)
	var berry: Color = look.get("berry", Color(0.6, 0.1, 0.1))
	var h: float = float(look.get("height", 1.2))
	var w: float = float(look.get("width", 1.5))
	var rods: int = int(look.get("rods", 0))
	var berries: int = int(look.get("berries", 10))
	var bsize: float = float(look.get("berry_size", 0.045))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var blobs: Array[Vector4] = []   # x, y, z = Mitte, w = Radius
	var blob_count: int = 4 + int(w * 1.5)
	for i in range(blob_count):
		var a: float = float(i) * 2.399963 + rng.randf() * 0.5
		var ring: float = (0.18 + 0.32 * rng.randf()) * w
		var r: float = (0.26 + 0.12 * rng.randf()) * w
		var y: float = h * (0.28 + 0.4 * rng.randf())
		var blob := Vector4(cos(a) * ring, y, sin(a) * ring, r)
		blobs.append(blob)
		var shade: float = 0.88 + 0.24 * rng.randf()
		_sphere(root, r, Vector3(blob.x, blob.y, blob.z), Color(leaf.r * shade, leaf.g * shade, leaf.b * shade), 0.85)
	for i in range(rods):
		var a: float = float(i) * TAU / float(maxi(rods, 1)) + rng.randf() * 0.4
		var lean: float = 0.12 + 0.2 * rng.randf()
		var rod_h: float = h * (0.75 + 0.3 * rng.randf())
		_cylinder(root, 0.018, rod_h, Vector3(cos(a) * lean * w * 0.4, rod_h * 0.5, sin(a) * lean * w * 0.4), Color(0.45, 0.33, 0.20))
	for i in range(berries):
		var blob: Vector4 = blobs[rng.randi_range(0, blobs.size() - 1)]
		var theta: float = rng.randf() * TAU
		var up: float = rng.randf_range(-0.2, 0.9)
		var rr: float = sqrt(maxf(0.0, 1.0 - up * up))
		var p := Vector3(blob.x + cos(theta) * rr * blob.w, blob.y + up * blob.w * 0.85, blob.z + sin(theta) * rr * blob.w)
		_sphere(root, bsize, p, berry, 1.0)

static func _mat(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return _mats[key]

static func _add(root: Node3D, mesh: Mesh, pos: Vector3, color: Color, yaw: float = 0.0) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _mat(color)
	inst.position = pos
	inst.rotation.y = yaw
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)

static func _box(root: Node3D, size: Vector3, pos: Vector3, color: Color, yaw: float = 0.0) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(root, m, pos, color, yaw)

static func _sphere(root: Node3D, radius: float, pos: Vector3, color: Color, squash: float = 1.0) -> void:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * squash
	m.radial_segments = 8
	m.rings = 4
	_add(root, m, pos, color)

static func _cylinder(root: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 5
	_add(root, m, pos, color)

static func _capsule(root: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> void:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 6
	m.rings = 3
	_add(root, m, pos, color)

static func _stem(root: Node3D, height: float, _x: float, _z: float) -> void:
	_cylinder(root, 0.012, height, Vector3(0.0, height * 0.5, 0.0), LEAF)

static func _leaves(root: Node3D, count: int, y: float, _unused: float) -> void:
	for i in range(count):
		var a: float = float(i) * TAU / float(count)
		_box(root, Vector3(0.16, 0.01, 0.05), Vector3(cos(a) * 0.08, y + float(i) * 0.03, sin(a) * 0.08), LEAF, -a)
