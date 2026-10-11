class_name PartBatch
extends RefCounted

## PartBatch — sammelt viele kleine Bauteile (Boxen, Zylinder, Dachprismen, Pyramiden) zu
## EINEM Mesh (Vertex-Farben) plus Kollisionsformen.
##
## WARUM: Ein Dorf besteht aus hunderten Einzelteilen (Wandsegmente, Pfosten, Zaunlatten, …).
## Als einzelne MeshInstance3D wären das hunderte Draw-Calls und Nodes — auf Mobilgeräten
## nicht tragbar. Hier laufen alle Teile eines Gebäudes in einen SurfaceTool-Puffer und
## werden mit build() zu GENAU EINER MeshInstance3D (ein Material, Farbe pro Vertex) plus
## einem StaticBody3D zusammengesetzt.
##
## Rein deterministisch und ohne Weltbezug: Koordinaten sind lokal zum Gebäude-Ursprung.
## Das Material ist doppelseitig (CULL_DISABLED), damit eine falsche Dreiecks-Windung nie
## unsichtbare Flächen ergibt; Normalen werden deshalb explizit und nach außen gesetzt.

const SEGMENTS_DEFAULT: int = 10

static var _material: StandardMaterial3D = null

var _st: SurfaceTool = SurfaceTool.new()
var _shapes: Array = []        # [{shape: Shape3D, xform: Transform3D}]
var _tri_count: int = 0
## Gruppen-Transformation (push_group/pop_group): alles, was zwischen push und pop hinzugefügt
## wird, liegt relativ zu Ursprung + Drehung der Gruppe. Damit lassen sich vorhandene Bauteile
## (Haus, Laterne, Fass …) unverändert auf Plattformen in der Luft oder gedreht wiederverwenden.
var _cur: Transform3D = Transform3D.IDENTITY
var _stack: Array[Transform3D] = []
var _grouped: bool = false

func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)

static func shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.9
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material

func triangle_count() -> int:
	return _tri_count

func shape_count() -> int:
	return _shapes.size()

# ─────────────────────────────────────────────
# Gruppen (verschobene/gedrehte Teilbereiche)
# ─────────────────────────────────────────────

## Ab hier liegt alles relativ zu `origin` (y = Höhe über dem Gebäude-Nullpunkt) und um `yaw`
## (rad, um die Hochachse; +Z lokal → (sin yaw, cos yaw) wie bei den Gebäuden) gedreht.
## Gruppen dürfen verschachtelt werden.
func push_group(origin: Vector3, yaw: float = 0.0) -> void:
	_stack.append(_cur)
	_cur = _cur * Transform3D(Basis(Vector3.UP, yaw), origin)
	_grouped = true

func pop_group() -> void:
	if _stack.is_empty():
		return
	_cur = _stack.pop_back()
	_grouped = not _stack.is_empty()

# ─────────────────────────────────────────────
# Primitive
# ─────────────────────────────────────────────

## Quader. pos = Mittelpunkt, rot_y = Drehung um die Hochachse (rad).
func add_box(size: Vector3, pos: Vector3, color: Color, rot_y: float = 0.0, collide: bool = true) -> void:
	var h := size * 0.5
	var c: Array[Vector3] = [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	for i in range(8):
		c[i] = _xf(c[i], pos, rot_y)
	# Seiten: unten 0..3, oben 4..7.
	_quad(c[0], c[1], c[2], c[3], color, pos)  # unten
	_quad(c[4], c[5], c[6], c[7], color, pos)  # oben
	_quad(c[0], c[1], c[5], c[4], color, pos)  # hinten (-Z)
	_quad(c[3], c[2], c[6], c[7], color, pos)  # vorne (+Z)
	_quad(c[0], c[3], c[7], c[4], color, pos)  # links (-X)
	_quad(c[1], c[2], c[6], c[5], color, pos)  # rechts (+X)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		_add_shape(shape, Transform3D(Basis(Vector3.UP, rot_y), pos))

## Zylinder (stehend). pos = Mittelpunkt.
func add_cylinder(
	radius: float, height: float, pos: Vector3, color: Color,
	collide: bool = true, segments: int = SEGMENTS_DEFAULT
) -> void:
	var n: int = maxi(3, segments)
	var hy: float = height * 0.5
	var ring_lo: Array[Vector3] = []
	var ring_hi: Array[Vector3] = []
	for i in range(n):
		var a: float = float(i) * TAU / float(n)
		ring_lo.append(pos + Vector3(cos(a) * radius, -hy, sin(a) * radius))
		ring_hi.append(pos + Vector3(cos(a) * radius, hy, sin(a) * radius))
	var top_c := pos + Vector3(0.0, hy, 0.0)
	var bot_c := pos + Vector3(0.0, -hy, 0.0)
	for i in range(n):
		var j: int = (i + 1) % n
		_quad(ring_lo[i], ring_lo[j], ring_hi[j], ring_hi[i], color, pos)
		_tri(top_c, ring_hi[i], ring_hi[j], color, pos)
		_tri(bot_c, ring_lo[i], ring_lo[j], color, pos)
	if collide:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		_add_shape(shape, Transform3D(Basis.IDENTITY, pos))

## Giebeldach (Prisma). pos = Mitte der Grundfläche auf Traufhöhe, First entlang lokal X
## (vor rot_y). half_w = halbe Länge (X), half_d = halbe Tiefe (Z), rise = Firsthöhe.
func add_gable_roof(
	half_w: float, half_d: float, rise: float, pos: Vector3, color: Color,
	rot_y: float = 0.0, collide: bool = true
) -> void:
	var a := _xf(Vector3(-half_w, 0.0, -half_d), pos, rot_y)
	var b := _xf(Vector3(half_w, 0.0, -half_d), pos, rot_y)
	var c := _xf(Vector3(half_w, 0.0, half_d), pos, rot_y)
	var d := _xf(Vector3(-half_w, 0.0, half_d), pos, rot_y)
	var r1 := _xf(Vector3(-half_w, rise, 0.0), pos, rot_y)
	var r2 := _xf(Vector3(half_w, rise, 0.0), pos, rot_y)
	var ref: Vector3 = pos + Vector3(0.0, rise * 0.33, 0.0)
	_quad(a, b, r2, r1, color, ref)   # Rückseite
	_quad(d, c, r2, r1, color, ref)   # Vorderseite
	_tri(a, d, r1, color, ref)        # Giebel links
	_tri(b, c, r2, color, ref)        # Giebel rechts
	_quad(a, b, c, d, color, ref)     # Unterseite
	if collide:
		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array([
			Vector3(-half_w, 0.0, -half_d), Vector3(half_w, 0.0, -half_d),
			Vector3(half_w, 0.0, half_d), Vector3(-half_w, 0.0, half_d),
			Vector3(-half_w, rise, 0.0), Vector3(half_w, rise, 0.0),
		])
		_add_shape(shape, Transform3D(Basis(Vector3.UP, rot_y), pos))

## Pyramide (Turm-/Zeltdach). pos = Mitte der Grundfläche.
func add_pyramid(
	half_w: float, half_d: float, rise: float, pos: Vector3, color: Color,
	rot_y: float = 0.0, collide: bool = true
) -> void:
	var a := _xf(Vector3(-half_w, 0.0, -half_d), pos, rot_y)
	var b := _xf(Vector3(half_w, 0.0, -half_d), pos, rot_y)
	var c := _xf(Vector3(half_w, 0.0, half_d), pos, rot_y)
	var d := _xf(Vector3(-half_w, 0.0, half_d), pos, rot_y)
	var apex := pos + Vector3(0.0, rise, 0.0)
	var ref: Vector3 = pos + Vector3(0.0, rise * 0.25, 0.0)
	_tri(a, b, apex, color, ref)
	_tri(b, c, apex, color, ref)
	_tri(c, d, apex, color, ref)
	_tri(d, a, apex, color, ref)
	_quad(a, b, c, d, color, ref)
	if collide:
		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array([
			Vector3(-half_w, 0.0, -half_d), Vector3(half_w, 0.0, -half_d),
			Vector3(half_w, 0.0, half_d), Vector3(-half_w, 0.0, half_d),
			Vector3(0.0, rise, 0.0),
		])
		_add_shape(shape, Transform3D(Basis(Vector3.UP, rot_y), pos))

## Kegelstumpf (stehend, z. B. Stamm, Wurzelanlauf, Blätterdach, Pilzhut). pos = Mittelpunkt.
## r_bottom/r_top dürfen 0 sein (Kegel). Kollision = konvexe Hülle.
func add_frustum(
	r_bottom: float, r_top: float, height: float, pos: Vector3, color: Color,
	collide: bool = true, segments: int = SEGMENTS_DEFAULT
) -> void:
	var n: int = maxi(3, segments)
	var hy: float = height * 0.5
	var lo: Array[Vector3] = []
	var hi: Array[Vector3] = []
	for i in range(n):
		var a: float = float(i) * TAU / float(n)
		lo.append(pos + Vector3(cos(a) * r_bottom, -hy, sin(a) * r_bottom))
		hi.append(pos + Vector3(cos(a) * r_top, hy, sin(a) * r_top))
	var top_c := pos + Vector3(0.0, hy, 0.0)
	var bot_c := pos + Vector3(0.0, -hy, 0.0)
	for i in range(n):
		var j: int = (i + 1) % n
		_quad(lo[i], lo[j], hi[j], hi[i], color, pos)
		_tri(top_c, hi[i], hi[j], color, pos)
		_tri(bot_c, lo[i], lo[j], color, pos)
	if collide:
		var shape := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for i in range(n):
			pts.append(lo[i] - pos)
			pts.append(hi[i] - pos)
		shape.points = pts
		_add_shape(shape, Transform3D(Basis.IDENTITY, pos))

## Schräges Brett von p0 nach p1 (Oberkante-Mittellinie), `width` quer (waagerecht), `thickness`
## nach unten. Für Rampen, Hängebrücken, Streben, Seile. Nicht für (fast) senkrechte Verläufe.
func add_plank(
	p0: Vector3, p1: Vector3, width: float, thickness: float, color: Color, collide: bool = true
) -> void:
	var f: Vector3 = p1 - p0
	if f.length_squared() < 0.0001:
		return
	var side: Vector3 = f.cross(Vector3.UP)
	if side.length_squared() < 0.000001:
		side = Vector3.RIGHT
	side = side.normalized() * (width * 0.5)
	var drop := Vector3(0.0, -thickness, 0.0)
	var c: Array[Vector3] = [
		p0 - side + drop, p0 + side + drop, p1 + side + drop, p1 - side + drop,
		p0 - side, p0 + side, p1 + side, p1 - side,
	]
	var ref: Vector3 = (p0 + p1) * 0.5 + drop * 0.5
	_quad(c[0], c[1], c[2], c[3], color, ref)   # unten
	_quad(c[4], c[5], c[6], c[7], color, ref)   # oben
	_quad(c[0], c[1], c[5], c[4], color, ref)   # Anfang
	_quad(c[3], c[2], c[6], c[7], color, ref)   # Ende
	_quad(c[0], c[3], c[7], c[4], color, ref)   # Seite -
	_quad(c[1], c[2], c[6], c[5], color, ref)   # Seite +
	if collide:
		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array(c)
		_add_shape(shape, Transform3D.IDENTITY)

# ─────────────────────────────────────────────
# Zusammenbau
# ─────────────────────────────────────────────

## Fertiger Node3D: Kind "Mesh" (MeshInstance3D) + Kind "Body" (StaticBody3D mit allen Formen).
## Nach build() darf der Batch nicht weiterverwendet werden (SurfaceTool ist verbraucht).
func build(node_name: String = "Parts") -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	if _tri_count > 0:
		var mesh: ArrayMesh = _st.commit()
		var inst := MeshInstance3D.new()
		inst.name = "Mesh"
		inst.mesh = mesh
		inst.material_override = shared_material()
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(inst)
	if not _shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		root.add_child(body)
		for entry: Dictionary in _shapes:
			var col := CollisionShape3D.new()
			col.shape = entry["shape"] as Shape3D
			col.transform = entry["xform"] as Transform3D
			body.add_child(col)
	return root

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

static func _xf(v: Vector3, pos: Vector3, rot_y: float) -> Vector3:
	if rot_y == 0.0:
		return v + pos
	return v.rotated(Vector3.UP, rot_y) + pos

func _add_shape(shape: Shape3D, local: Transform3D) -> void:
	_shapes.append({"shape": shape, "xform": (_cur * local) if _grouped else local})

## Dreieck mit nach AUSSEN (weg von `ref`) zeigender Normale.
func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color, ref: Vector3) -> void:
	if _grouped:
		a = _cur * a
		b = _cur * b
		c = _cur * c
		ref = _cur * ref
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 0.0000001:
		return
	n = n.normalized()
	var centroid: Vector3 = (a + b + c) / 3.0
	if n.dot(centroid - ref) < 0.0:
		n = -n
	for v: Vector3 in [a, b, c]:
		_st.set_color(color)
		_st.set_normal(n)
		_st.add_vertex(v)
	_tri_count += 1

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, ref: Vector3) -> void:
	_tri(a, b, c, color, ref)
	_tri(a, c, d, color, ref)
