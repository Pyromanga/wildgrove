class_name ChunkStructureBuilder
extends RefCounted

## ChunkStructureBuilder — baut aus einem ChunkStructurePlanner-Plan die Geometrie eines
## Gebäudes: Meshes + Kollision aus Godot-Primitiven (Boxen, Zylinder, ein Prisma fürs Dach).
##
## Das Ergebnis ist ein Node3D, der als Kind des Chunk-Nodes hängt und mit ihm freigegeben
## wird (kein eigener Lebenszyklus nötig). Alles ist deterministisch aus plan["seed"].
##
## KOORDINATEN (lokal, vor der Drehung): Ursprung = Mitte der Fläche auf Höhe base_y,
## +Z = Vorderseite (Tür/Vorplatz). Die Bodenplatte reicht von der Oberkante SLAB_TOP
## weit genug nach unten, damit am Hang keine Lücke zum Gelände entsteht.

const SLAB_TOP: float = 0.12
const WALL_T: float = 0.25

## type → NPC-Typ, der dort steht (leer = niemand). Muss in WorldEntityRegistry registriert sein.
const NPC_TYPE_BY_STRUCTURE: Dictionary = {
	"cottage": "settler_npc",
	"barn":    "farmer_npc",
	"well":    "water_carrier_npc",
}

## type → mögliche NPC-Plätze (lokal x, z) auf dem Vorplatz, innerhalb der Bodenplatte.
const NPC_SLOTS: Dictionary = {
	"cottage": [Vector2(-1.4, 2.6), Vector2(1.5, 2.8)],
	"barn":    [Vector2(-2.2, 3.8), Vector2(2.4, 4.0)],
	"well":    [Vector2(1.6, 1.5)],
}

static var _materials: Dictionary = {}

static func npc_slots(type_id: String) -> Array:
	return NPC_SLOTS.get(type_id, [])

static func npc_type(type_id: String) -> String:
	return String(NPC_TYPE_BY_STRUCTURE.get(type_id, ""))

## Baut das Gebäude. Position/Drehung werden hier gesetzt, relativ zu chunk_center (Weltmeter).
static func build(plan: Dictionary, chunk_center: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "Structure_%s" % String(plan["type"])
	root.position = Vector3(float(plan["x"]) - chunk_center.x, float(plan["base_y"]), float(plan["z"]) - chunk_center.y)
	root.rotation.y = float(int(plan["yaw_steps"])) * PI * 0.5

	var body := StaticBody3D.new()
	body.name = "Body"
	root.add_child(body)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(plan["seed"])
	var hx: float = float(plan["half_x"])
	var hz: float = float(plan["half_z"])
	var depth: float = float(plan["spread"]) + 1.4

	match String(plan["type"]):
		"cottage":
			_slab(body, hx, hz, depth, Color(0.46, 0.44, 0.41))
			_house(body, rng, {
				"bw": 5.0, "bd": 4.5, "z0": -3.5, "wh": 2.6, "rh": 1.7,
				"door_w": 1.2, "door_h": 2.1, "chimney": true,
				"walls": [Color(0.80, 0.72, 0.56), Color(0.52, 0.38, 0.24), Color(0.62, 0.60, 0.56)],
				"roofs": [Color(0.55, 0.22, 0.16), Color(0.42, 0.32, 0.20), Color(0.30, 0.33, 0.38)],
			})
			_interior_cottage(body)
			_crate(body, Vector3(2.6, SLAB_TOP + 0.3, 1.9), 0.6)
			_barrel(body, Vector3(-2.7, SLAB_TOP, 1.8))
		"barn":
			_slab(body, hx, hz, depth, Color(0.44, 0.42, 0.39))
			_house(body, rng, {
				"bw": 8.0, "bd": 7.0, "z0": -5.0, "wh": 3.4, "rh": 2.4,
				"door_w": 2.6, "door_h": 2.8, "chimney": false,
				"walls": [Color(0.55, 0.22, 0.16), Color(0.50, 0.36, 0.22)],
				"roofs": [Color(0.34, 0.28, 0.20), Color(0.30, 0.33, 0.38)],
			})
			_interior_barn(body, rng)
			_barrel(body, Vector3(-4.0, SLAB_TOP, 3.2))
			_barrel(body, Vector3(-3.4, SLAB_TOP, 3.9))
		"well":
			_slab(body, hx, hz, depth, Color(0.48, 0.46, 0.43))
			_well(body)
		"ruin":
			_slab(body, hx, hz, depth, Color(0.36, 0.36, 0.33))
			_ruin(body, rng)
	return root

# ─────────────────────────────────────────────
# Grundbausteine
# ─────────────────────────────────────────────

static func _mat(color: Color, double_sided: bool = false) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), str(double_sided)]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		if double_sided:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]

## Box mit Mesh und (optional) Kollision. pos = Mittelpunkt, relativ zum Gebäude-Ursprung.
static func _box(
	body: StaticBody3D, size: Vector3, pos: Vector3, color: Color,
	collide: bool = true, rot_y: float = 0.0
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _mat(color)
	inst.position = pos
	inst.rotation.y = rot_y
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(inst)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = pos
		col.rotation.y = rot_y
		body.add_child(col)

static func _slab(body: StaticBody3D, hx: float, hz: float, depth: float, color: Color) -> void:
	_box(body, Vector3(hx * 2.0, depth, hz * 2.0), Vector3(0.0, SLAB_TOP - depth * 0.5, 0.0), color)

## Giebeldach über Rechteck, First entlang X. Doppelseitig (Winkel/Windung egal), mit
## konvexer Kollision, damit man nicht durchs Dach fällt.
static func _roof(
	body: StaticBody3D, half_w: float, half_d: float, rise: float, pos: Vector3, color: Color
) -> void:
	var a := Vector3(-half_w, 0.0, -half_d)
	var b := Vector3( half_w, 0.0, -half_d)
	var c := Vector3( half_w, 0.0,  half_d)
	var d := Vector3(-half_w, 0.0,  half_d)
	var r1 := Vector3(-half_w, rise, 0.0)
	var r2 := Vector3( half_w, rise, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Vector3 in [a, b, r2, a, r2, r1, d, r1, r2, d, r2, c, a, r1, d, b, c, r2, a, d, c, a, c, b]:
		st.add_vertex(v)
	st.generate_normals()
	var inst := MeshInstance3D.new()
	inst.mesh = st.commit()
	inst.material_override = _mat(color, true)
	inst.position = pos
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(inst)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a, b, c, d, r1, r2])
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	body.add_child(col)

static func _cylinder(
	body: StaticBody3D, radius: float, height: float, pos: Vector3, color: Color, collide: bool = true
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _mat(color)
	inst.position = pos
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(inst)
	if collide:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = pos
		body.add_child(col)

static func _barrel(body: StaticBody3D, ground: Vector3) -> void:
	_cylinder(body, 0.38, 0.9, ground + Vector3(0.0, 0.45, 0.0), Color(0.40, 0.27, 0.14))

static func _crate(body: StaticBody3D, center: Vector3, side: float) -> void:
	_box(body, Vector3(side, side, side), center, Color(0.50, 0.37, 0.20), true, 0.3)

# ─────────────────────────────────────────────
# Haus (Hütte + Scheune)
# ─────────────────────────────────────────────

static func _house(body: StaticBody3D, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var bw: float = p["bw"]
	var bd: float = p["bd"]
	var z0: float = p["z0"]
	var z1: float = z0 + bd
	var zc: float = (z0 + z1) * 0.5
	var wh: float = p["wh"]
	var rise: float = p["rh"]
	var dw: float = p["door_w"]
	var dh: float = p["door_h"]
	var y0: float = SLAB_TOP
	var wall_colors: Array = p["walls"]
	var roof_colors: Array = p["roofs"]
	var wall_c: Color = wall_colors[rng.randi_range(0, wall_colors.size() - 1)]
	var roof_c: Color = roof_colors[rng.randi_range(0, roof_colors.size() - 1)]

	# Rückwand + Seitenwände
	_box(body, Vector3(bw, wh, WALL_T), Vector3(0.0, y0 + wh * 0.5, z0 + WALL_T * 0.5), wall_c)
	for sx: float in [-1.0, 1.0]:
		_box(body, Vector3(WALL_T, wh, bd), Vector3(sx * (bw * 0.5 - WALL_T * 0.5), y0 + wh * 0.5, zc), wall_c)
	# Vorderwand mit Türöffnung: zwei Segmente + Sturz
	var seg: float = (bw - dw) * 0.5
	for sx: float in [-1.0, 1.0]:
		_box(body, Vector3(seg, wh, WALL_T), Vector3(sx * (dw * 0.5 + seg * 0.5), y0 + wh * 0.5, z1 - WALL_T * 0.5), wall_c)
	_box(body, Vector3(dw, wh - dh, WALL_T), Vector3(0.0, y0 + dh + (wh - dh) * 0.5, z1 - WALL_T * 0.5), wall_c)
	# Fenster: dunkle Platten leicht vor der Seitenwand (nur Optik)
	for sx: float in [-1.0, 1.0]:
		_box(body, Vector3(0.06, 0.7, 0.9), Vector3(sx * (bw * 0.5 + 0.01), y0 + wh * 0.55, zc), Color(0.12, 0.16, 0.22), false)
	# Dach
	_roof(body, bw * 0.5 + 0.35, bd * 0.5 + 0.35, rise, Vector3(0.0, y0 + wh, zc), roof_c)
	if bool(p.get("chimney", false)):
		_box(body, Vector3(0.55, rise + 1.0, 0.55), Vector3(bw * 0.28, y0 + wh + (rise + 1.0) * 0.5 - 0.1, zc - bd * 0.2), Color(0.45, 0.42, 0.40))

static func _interior_cottage(body: StaticBody3D) -> void:
	# Bett an der Rückwand, Tisch daneben — nur grobe Möbelblöcke.
	_box(body, Vector3(1.0, 0.45, 1.9), Vector3(-1.7, SLAB_TOP + 0.225, -2.4), Color(0.45, 0.30, 0.18))
	_box(body, Vector3(0.9, 0.15, 0.5), Vector3(-1.7, SLAB_TOP + 0.52, -3.0), Color(0.85, 0.82, 0.74), false)
	_box(body, Vector3(1.1, 0.75, 0.8), Vector3(1.4, SLAB_TOP + 0.375, -2.6), Color(0.50, 0.36, 0.20))

static func _interior_barn(body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(3, 5)):
		var px: float = rng.randf_range(-3.0, 3.0)
		var pz: float = rng.randf_range(-4.2, 0.4)
		_box(body, Vector3(1.0, 0.7, 0.7), Vector3(px, SLAB_TOP + 0.35, pz), Color(0.78, 0.66, 0.28), true, rng.randf_range(0.0, PI))

# ─────────────────────────────────────────────
# Brunnen + Ruine
# ─────────────────────────────────────────────

static func _well(body: StaticBody3D) -> void:
	var ring_r: float = 0.95
	for i in range(8):
		var ang: float = float(i) * TAU / 8.0
		_box(body, Vector3(0.62, 0.9, 0.42), Vector3(cos(ang) * ring_r, SLAB_TOP + 0.45, sin(ang) * ring_r), Color(0.55, 0.53, 0.50), true, -ang + PI * 0.5)
	_cylinder(body, 0.72, 0.04, Vector3(0.0, SLAB_TOP + 0.3, 0.0), Color(0.12, 0.28, 0.45), false)
	for sx: float in [-1.0, 1.0]:
		_box(body, Vector3(0.16, 2.1, 0.16), Vector3(sx * ring_r, SLAB_TOP + 1.05, 0.0), Color(0.42, 0.30, 0.18))
	_roof(body, 1.35, 0.95, 0.6, Vector3(0.0, SLAB_TOP + 2.1, 0.0), Color(0.42, 0.32, 0.20))

static func _ruin(body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	var stone := Color(0.52, 0.51, 0.47)
	var moss := Color(0.40, 0.46, 0.34)
	var half: float = 3.2
	# Vier Seiten, jede in zwei Teilstücke mit zufälliger Resthöhe (mitunter fehlt eins ganz).
	for side in range(4):
		for part in range(2):
			if rng.randf() < 0.25:
				continue
			var wall_h: float = rng.randf_range(0.5, 2.5)
			var along: float = -half * 0.5 + float(part) * half
			var pos := Vector3(0.0, 0.0, 0.0)
			var size := Vector3(half - 0.3, wall_h, WALL_T)
			var rot: float = 0.0
			match side:
				0: pos = Vector3(along, 0.0, -half)
				1: pos = Vector3(along, 0.0, half)
				2:
					pos = Vector3(-half, 0.0, along)
					rot = PI * 0.5
				3:
					pos = Vector3(half, 0.0, along)
					rot = PI * 0.5
			pos.y = SLAB_TOP + wall_h * 0.5
			_box(body, size, pos, stone if rng.randf() < 0.7 else moss, true, rot)
	# Eckpfeiler (teils abgebrochen) und herumliegende Steinblöcke.
	for cx: float in [-half, half]:
		for cz: float in [-half, half]:
			var ph: float = rng.randf_range(1.0, 3.0)
			_cylinder(body, 0.35, ph, Vector3(cx, SLAB_TOP + ph * 0.5, cz), stone)
	for i in range(rng.randi_range(3, 6)):
		var s: float = rng.randf_range(0.4, 0.8)
		_box(body, Vector3(s, s * 0.7, s), Vector3(rng.randf_range(-2.4, 2.4), SLAB_TOP + s * 0.35, rng.randf_range(-2.4, 2.4)), moss, true, rng.randf_range(0.0, PI))
