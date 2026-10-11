class_name StructureParts
extends RefCounted

## StructureParts — die KLEINEN Teile, aus denen BuildingRecipes die Gebäude zusammensetzt.
##
## Jede Funktion schreibt in einen PartBatch (lokale Koordinaten; y = 0 ist die Oberkante der
## Bodenplatte, +Z = Vorderseite/Tür). Nichts hier kennt Gelände, Chunks oder NPCs.
##
## Ebenen:  Primitive (PartBatch) → Teile (diese Datei: Wandlauf, Dach, Zaun, Laterne, Stand,
##          Beet, Grabstein, Mühlenflügel …) → Gebäude (BuildingRecipes) → Siedlung.

const WALL_T: float = 0.25
const POST: float = 0.14

const COL_WOOD_DARK := Color(0.36, 0.25, 0.14)
const COL_WOOD := Color(0.50, 0.37, 0.20)
const COL_WOOD_LIGHT := Color(0.62, 0.48, 0.28)
const COL_STONE := Color(0.52, 0.51, 0.47)
const COL_STONE_DARK := Color(0.40, 0.40, 0.38)
const COL_PLASTER := Color(0.82, 0.76, 0.62)
const COL_GLASS := Color(0.12, 0.16, 0.22)
const COL_SOIL := Color(0.30, 0.21, 0.12)
const COL_CROP := Color(0.34, 0.55, 0.18)
const COL_HAY := Color(0.78, 0.66, 0.28)
const COL_PAVING := Color(0.50, 0.48, 0.44)
const COL_IRON := Color(0.22, 0.22, 0.25)

# ─────────────────────────────────────────────
# Boden / Fundament
# ─────────────────────────────────────────────

## Bodenplatte: Oberkante y = 0, reicht `depth` nach unten (deckt Hang-Spalt zum Gelände).
static func slab(b: PartBatch, hx: float, hz: float, depth: float, color: Color) -> void:
	b.add_box(Vector3(hx * 2.0, depth, hz * 2.0), Vector3(0.0, -depth * 0.5, 0.0), color)

## Flaches Pflaster (nur Optik + begehbar), z. B. Marktplatz. Höhe 0.06 über y = 0.
static func paving(b: PartBatch, center: Vector2, half: Vector2, color: Color = COL_PAVING) -> void:
	b.add_box(Vector3(half.x * 2.0, 0.06, half.y * 2.0), Vector3(center.x, 0.03, center.y), color)

# ─────────────────────────────────────────────
# Wände
# ─────────────────────────────────────────────

## Wandlauf von `from` nach `to` (lokale x/z), Höhe `h`, Dicke WALL_T.
## openings: Array[Dictionary] {t0, t1: Meter entlang der Wand, kind: "door"|"window",
## sill: Brüstungshöhe (nur window), top: Oberkante der Öffnung}. Türen reichen bis y = 0.
static func wall_run(
	b: PartBatch, from: Vector2, to: Vector2, h: float, color: Color, openings: Array = []
) -> void:
	var dir: Vector2 = to - from
	var length: float = dir.length()
	if length < 0.05:
		return
	var theta: float = atan2(-dir.y, dir.x)   # lokal +X → dir (Drehung um Y)
	var mid: Vector2 = (from + to) * 0.5
	var sorted: Array = openings.duplicate()
	sorted.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["t0"]) < float(q["t0"]))
	var cursor: float = 0.0
	for o: Dictionary in sorted:
		var t0: float = clampf(float(o["t0"]), 0.0, length)
		var t1: float = clampf(float(o["t1"]), 0.0, length)
		if t1 <= t0:
			continue
		_wall_piece(b, mid, theta, length, cursor, t0, 0.0, h, color)
		var is_door: bool = String(o.get("kind", "door")) == "door"
		var top: float = minf(float(o.get("top", 2.1)), h)
		var sill: float = 0.0 if is_door else float(o.get("sill", 0.9))
		if sill > 0.0:
			_wall_piece(b, mid, theta, length, t0, t1, 0.0, sill, color)
		if h - top > 0.02:
			_wall_piece(b, mid, theta, length, t0, t1, top, h, color)
		if not is_door:
			# Glasplatte: nur Optik, minimal dicker als die Wand.
			var gp: Vector3 = _wall_point(mid, theta, length, (t0 + t1) * 0.5, (sill + top) * 0.5)
			b.add_box(Vector3(t1 - t0 - 0.1, top - sill - 0.1, WALL_T + 0.04), gp, COL_GLASS, theta, false)
		cursor = t1
	_wall_piece(b, mid, theta, length, cursor, length, 0.0, h, color)

static func _wall_piece(
	b: PartBatch, mid: Vector2, theta: float, length: float,
	t0: float, t1: float, y0: float, y1: float, color: Color
) -> void:
	if t1 - t0 < 0.02 or y1 - y0 < 0.02:
		return
	var p: Vector3 = _wall_point(mid, theta, length, (t0 + t1) * 0.5, (y0 + y1) * 0.5)
	b.add_box(Vector3(t1 - t0, y1 - y0, WALL_T), p, color, theta)

## Punkt auf der Wand: t Meter vom Wandanfang, Höhe y.
static func _wall_point(mid: Vector2, theta: float, length: float, t: float, y: float) -> Vector3:
	var off := Vector3(t - length * 0.5, 0.0, 0.0).rotated(Vector3.UP, theta)
	return Vector3(mid.x + off.x, y, mid.y + off.z)

## Rechteckiges Gebäude aus vier Wandläufen. Rect2 in lokalen x/z. door_side: 0 = +Z (Front),
## 1 = -Z, 2 = +X, 3 = -X. Tür in der Mitte der Seite (door_offset verschiebt entlang der Wand).
## windows: Anzahl Fenster je Längsseite (ohne Türseite-Kollision).
static func box_house(
	b: PartBatch, rect: Rect2, wall_h: float, color: Color, door_w: float = 1.2,
	door_h: float = 2.1, door_side: int = 0, door_offset: float = 0.0, windows: int = 1
) -> void:
	var x0: float = rect.position.x
	var x1: float = rect.end.x
	var z0: float = rect.position.y
	var z1: float = rect.end.y
	# Seite 0 = vorn (+Z): von links nach rechts; 1 = hinten; 2 = rechts; 3 = links.
	var sides: Array = [
		{"from": Vector2(x0, z1), "to": Vector2(x1, z1)},
		{"from": Vector2(x0, z0), "to": Vector2(x1, z0)},
		{"from": Vector2(x1, z0), "to": Vector2(x1, z1)},
		{"from": Vector2(x0, z0), "to": Vector2(x0, z1)},
	]
	for i in range(4):
		var s: Dictionary = sides[i]
		var from: Vector2 = s["from"]
		var to: Vector2 = s["to"]
		var length: float = from.distance_to(to)
		var ops: Array = []
		if i == door_side:
			var c: float = length * 0.5 + door_offset
			ops.append({"t0": c - door_w * 0.5, "t1": c + door_w * 0.5, "kind": "door", "top": door_h})
		elif windows > 0 and length > 3.0:
			for k in range(windows):
				var c2: float = length * (float(k) + 1.0) / float(windows + 1)
				ops.append({"t0": c2 - 0.45, "t1": c2 + 0.45, "kind": "window", "sill": 0.9, "top": 1.8})
		wall_run(b, from, to, wall_h, color, ops)

# ─────────────────────────────────────────────
# Dächer, Schornstein
# ─────────────────────────────────────────────

## Giebeldach über Rect2, First entlang der LÄNGEREN Seite, Überstand 0.35.
static func gable_over(b: PartBatch, rect: Rect2, wall_h: float, rise: float, color: Color) -> void:
	var c: Vector2 = rect.get_center()
	var along_x: bool = rect.size.x >= rect.size.y
	var hw: float = (rect.size.x if along_x else rect.size.y) * 0.5 + 0.35
	var hd: float = (rect.size.y if along_x else rect.size.x) * 0.5 + 0.35
	b.add_gable_roof(hw, hd, rise, Vector3(c.x, wall_h, c.y), color, 0.0 if along_x else PI * 0.5)

static func pyramid_over(b: PartBatch, rect: Rect2, wall_h: float, rise: float, color: Color) -> void:
	var c: Vector2 = rect.get_center()
	b.add_pyramid(rect.size.x * 0.5 + 0.3, rect.size.y * 0.5 + 0.3, rise, Vector3(c.x, wall_h, c.y), color)

static func chimney(b: PartBatch, base: Vector3, height: float, color: Color = COL_STONE_DARK) -> void:
	b.add_box(Vector3(0.55, height, 0.55), base + Vector3(0.0, height * 0.5, 0.0), color)

# ─────────────────────────────────────────────
# Zäune, Pfosten, Laternen
# ─────────────────────────────────────────────

## Zaun von a nach c. gaps: Array[Vector2] (t0, t1 in Metern entlang) bleiben offen (Tor).
static func fence_run(
	b: PartBatch, a: Vector2, c: Vector2, height: float = 1.0, color: Color = COL_WOOD,
	gaps: Array = []
) -> void:
	var dir: Vector2 = c - a
	var length: float = dir.length()
	if length < 0.3:
		return
	var theta: float = atan2(-dir.y, dir.x)
	var mid: Vector2 = (a + c) * 0.5
	var posts: int = maxi(2, int(ceil(length / 2.0)) + 1)
	for i in range(posts):
		var t: float = length * float(i) / float(posts - 1)
		if _in_gap(t, gaps):
			continue
		var p: Vector3 = _wall_point(mid, theta, length, t, height * 0.5)
		b.add_box(Vector3(POST, height, POST), p, COL_WOOD_DARK, theta, false)
	# Zwei Querlatten, abschnittsweise um Tore herum.
	var edges: Array[float] = [0.0]
	for g: Variant in gaps:
		var gv: Vector2 = g
		edges.append(clampf(gv.x, 0.0, length))
		edges.append(clampf(gv.y, 0.0, length))
	edges.append(length)
	var k: int = 0
	while k + 1 < edges.size():
		var t0: float = edges[k]
		var t1: float = edges[k + 1]
		if t1 - t0 > 0.2:
			for ry: float in [height * 0.42, height * 0.82]:
				var p2: Vector3 = _wall_point(mid, theta, length, (t0 + t1) * 0.5, ry)
				b.add_box(Vector3(t1 - t0, 0.09, 0.07), p2, color, theta, false)
			# Eine unsichtbar dünne Kollisionswand je Abschnitt (Latten allein sind zu schmal).
			var pc: Vector3 = _wall_point(mid, theta, length, (t0 + t1) * 0.5, height * 0.5)
			b.add_box(Vector3(t1 - t0, height, 0.1), pc, color, theta, true)
		k += 2

static func _in_gap(t: float, gaps: Array) -> bool:
	for g: Variant in gaps:
		var gv: Vector2 = g
		if t > gv.x + 0.01 and t < gv.y - 0.01:
			return true
	return false

## Geschlossener Rechteckzaun um `rect`; gate_side 0..3 wie box_house, Tor in der Mitte.
static func fence_rect(
	b: PartBatch, rect: Rect2, gate_side: int = 0, gate_w: float = 2.0, height: float = 1.0
) -> void:
	var x0: float = rect.position.x
	var x1: float = rect.end.x
	var z0: float = rect.position.y
	var z1: float = rect.end.y
	var sides: Array = [
		[Vector2(x0, z1), Vector2(x1, z1)], [Vector2(x0, z0), Vector2(x1, z0)],
		[Vector2(x1, z0), Vector2(x1, z1)], [Vector2(x0, z0), Vector2(x0, z1)],
	]
	for i in range(4):
		var pair: Array = sides[i]
		var from: Vector2 = pair[0]
		var to: Vector2 = pair[1]
		var gaps: Array = []
		if i == gate_side:
			var m: float = from.distance_to(to) * 0.5
			gaps.append(Vector2(m - gate_w * 0.5, m + gate_w * 0.5))
		fence_run(b, from, to, height, COL_WOOD, gaps)

static func lamp_post(b: PartBatch, base: Vector2, height: float = 3.0, iron: bool = false) -> void:
	var col: Color = COL_IRON if iron else COL_WOOD_DARK
	b.add_cylinder(0.07, height, Vector3(base.x, height * 0.5, base.y), col, true, 6)
	b.add_box(Vector3(0.3, 0.38, 0.3), Vector3(base.x, height + 0.12, base.y), Color(0.95, 0.82, 0.45), 0.0, false)
	b.add_pyramid(0.26, 0.26, 0.22, Vector3(base.x, height + 0.31, base.y), col, 0.0, false)

# ─────────────────────────────────────────────
# Kleinteile
# ─────────────────────────────────────────────

static func barrel(b: PartBatch, base: Vector2) -> void:
	b.add_cylinder(0.38, 0.9, Vector3(base.x, 0.45, base.y), Color(0.40, 0.27, 0.14))

static func crate(b: PartBatch, base: Vector2, side: float = 0.6, rot: float = 0.3) -> void:
	b.add_box(Vector3(side, side, side), Vector3(base.x, side * 0.5, base.y), COL_WOOD, rot)

static func hay_bale(b: PartBatch, base: Vector2, rot: float = 0.0) -> void:
	b.add_box(Vector3(1.0, 0.7, 0.7), Vector3(base.x, 0.35, base.y), COL_HAY, rot)

static func bench(b: PartBatch, center: Vector2, rot: float = 0.0, length: float = 1.6) -> void:
	b.add_box(Vector3(length, 0.1, 0.4), Vector3(center.x, 0.45, center.y), COL_WOOD_LIGHT, rot, false)
	for s: float in [-1.0, 1.0]:
		var off := Vector3(s * (length * 0.5 - 0.15), 0.0, 0.0).rotated(Vector3.UP, rot)
		b.add_box(Vector3(0.1, 0.45, 0.35), Vector3(center.x + off.x, 0.225, center.y + off.z), COL_WOOD_DARK, rot, false)
	# Eine Kollisionsbox für die ganze Bank.
	b.add_box(Vector3(length, 0.5, 0.4), Vector3(center.x, 0.25, center.y), COL_WOOD_LIGHT, rot, true)

static func table(b: PartBatch, center: Vector2, rot: float = 0.0, size: Vector2 = Vector2(1.4, 0.8)) -> void:
	b.add_box(Vector3(size.x, 0.08, size.y), Vector3(center.x, 0.78, center.y), COL_WOOD_LIGHT, rot, false)
	b.add_box(Vector3(size.x - 0.3, 0.74, size.y - 0.3), Vector3(center.x, 0.37, center.y), COL_WOOD_DARK, rot, true)

static func bed(b: PartBatch, center: Vector2, rot: float = 0.0) -> void:
	b.add_box(Vector3(1.0, 0.45, 1.9), Vector3(center.x, 0.225, center.y), Color(0.45, 0.30, 0.18), rot)
	b.add_box(Vector3(0.9, 0.15, 0.5), Vector3(center.x, 0.52, center.y - 0.6), Color(0.85, 0.82, 0.74), rot, false)

## Schild an einem Pfosten (Wirtshaus, Werkstatt …). Brett zeigt nach +Z (lokal, dann rot).
static func signpost(b: PartBatch, base: Vector2, rot: float, board_color: Color) -> void:
	b.add_box(Vector3(0.12, 2.3, 0.12), Vector3(base.x, 1.15, base.y), COL_WOOD_DARK, rot, true)
	var off := Vector3(0.4, 0.0, 0.0).rotated(Vector3.UP, rot)
	b.add_box(Vector3(0.8, 0.45, 0.07), Vector3(base.x + off.x, 2.0, base.y + off.z), board_color, rot, false)

## Marktstand: Theke, vier Pfosten, flaches Giebeldach als Tuch. Front (offene Seite) = +Z.
static func market_stall(b: PartBatch, center: Vector2, rot: float, canopy: Color) -> void:
	var hw: float = 1.1
	var hd: float = 0.8
	b.add_box(Vector3(hw * 2.0, 0.9, 0.5), _rot_off(center, rot, Vector3(0.0, 0.45, -hd + 0.25)), COL_WOOD, rot, true)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.add_box(Vector3(0.1, 2.2, 0.1), _rot_off(center, rot, Vector3(sx * hw, 1.1, sz * hd)), COL_WOOD_DARK, rot, false)
	b.add_gable_roof(hw + 0.2, hd + 0.2, 0.4, _rot_off(center, rot, Vector3(0.0, 2.2, 0.0)), canopy, rot, false)

## Beet: Erdfläche + Reihen niedriger Pflanzen. Nur Optik (begehbar), keine Kollision.
static func crop_plot(b: PartBatch, center: Vector2, half: Vector2, rows: int = 5, color: Color = COL_CROP) -> void:
	b.add_box(Vector3(half.x * 2.0, 0.1, half.y * 2.0), Vector3(center.x, 0.05, center.y), COL_SOIL, 0.0, false)
	var n: int = maxi(1, rows)
	for i in range(n):
		var z: float = center.y - half.y + half.y * 2.0 * (float(i) + 0.5) / float(n)
		b.add_box(Vector3(half.x * 2.0 - 0.6, 0.28, 0.32), Vector3(center.x, 0.24, z), color, 0.0, false)

static func gravestone(b: PartBatch, base: Vector2, rot: float = 0.0, tall: float = 0.9) -> void:
	b.add_box(Vector3(0.55, tall, 0.14), Vector3(base.x, tall * 0.5, base.y), COL_STONE, rot, true)

static func stone_cross(b: PartBatch, base: Vector2) -> void:
	b.add_box(Vector3(0.9, 0.5, 0.9), Vector3(base.x, 0.25, base.y), COL_STONE_DARK)
	b.add_box(Vector3(0.28, 1.9, 0.28), Vector3(base.x, 1.45, base.y), COL_STONE)
	b.add_box(Vector3(1.0, 0.26, 0.26), Vector3(base.x, 2.0, base.y), COL_STONE, 0.0, false)

## Brunnen: Steinring, Wasserfläche, zwei Pfosten + Dach.
static func well(b: PartBatch, center: Vector2) -> void:
	var ring_r: float = 0.95
	for i in range(8):
		var ang: float = float(i) * TAU / 8.0
		b.add_box(Vector3(0.62, 0.9, 0.42), Vector3(center.x + cos(ang) * ring_r, 0.45, center.y + sin(ang) * ring_r), Color(0.55, 0.53, 0.50), -ang + PI * 0.5)
	b.add_cylinder(0.72, 0.04, Vector3(center.x, 0.3, center.y), Color(0.12, 0.28, 0.45), false)
	for sx: float in [-1.0, 1.0]:
		b.add_box(Vector3(0.16, 2.1, 0.16), Vector3(center.x + sx * ring_r, 1.05, center.y), COL_WOOD_DARK)
	b.add_gable_roof(1.35, 0.95, 0.6, Vector3(center.x, 2.1, center.y), Color(0.42, 0.32, 0.20))

## Offener Unterstand (Schmiede/Stall): Pfosten + Dach, Rückwand optional.
static func lean_to(b: PartBatch, rect: Rect2, height: float, roof: Color, back_wall: bool = true) -> void:
	for sx: float in [rect.position.x, rect.end.x]:
		for sz: float in [rect.position.y, rect.end.y]:
			b.add_box(Vector3(0.18, height, 0.18), Vector3(sx, height * 0.5, sz), COL_WOOD_DARK)
	if back_wall:
		wall_run(b, Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), height, COL_WOOD)
	gable_over(b, rect, height, 0.9, roof)

## Mühlenflügel: vier Arme + Nabe, Blick nach +Z (lokal). hub = Nabenposition (y = Höhe).
static func mill_sails(b: PartBatch, hub: Vector3, length: float = 3.4, tilt: float = 0.0) -> void:
	b.add_box(Vector3(0.4, 0.4, 0.5), hub, COL_WOOD_DARK, 0.0, false)
	for k in range(4):
		var ang: float = tilt + float(k) * PI * 0.5
		var dir := Vector3(cos(ang), sin(ang), 0.0)
		var center: Vector3 = hub + dir * (length * 0.5 + 0.2) + Vector3(0.0, 0.0, 0.3)
		# Arme sind nur Optik: Boxen in der XY-Ebene — Drehung um Z geht mit add_box nicht,
		# deshalb achsparallel (Tilt nur in 90°-Schritten sinnvoll).
		if absf(dir.x) > 0.5:
			b.add_box(Vector3(length, 0.28, 0.08), center, COL_WOOD_LIGHT, 0.0, false)
			b.add_box(Vector3(length * 0.9, 0.7, 0.04), center + Vector3(0.0, 0.4, 0.0), COL_PLASTER, 0.0, false)
		else:
			b.add_box(Vector3(0.28, length, 0.08), center, COL_WOOD_LIGHT, 0.0, false)
			b.add_box(Vector3(0.7, length * 0.9, 0.04), center + Vector3(0.4, 0.0, 0.0), COL_PLASTER, 0.0, false)

static func log_stack(b: PartBatch, base: Vector2, rot: float = 0.0) -> void:
	for row in range(3):
		var cnt: int = 4 - row
		for i in range(cnt):
			var off := Vector3((float(i) - float(cnt - 1) * 0.5) * 0.34, 0.0, 0.0).rotated(Vector3.UP, rot)
			b.add_cylinder(0.16, 1.4, Vector3(base.x + off.x, 0.16 + float(row) * 0.29, base.y + off.z), Color(0.45, 0.32, 0.18), false, 6)
	b.add_box(Vector3(1.5, 0.9, 1.4), Vector3(base.x, 0.45, base.y), COL_WOOD_DARK, rot, true)

# ─────────────────────────────────────────────
# Handwerks-Teile (Berufe, siehe docs/professions.md)
# ─────────────────────────────────────────────

## Brennofen/Schmelzofen: Steinzylinder mit Kuppeldach, Schornstein und glühender Öffnung (Front = +Z).
static func kiln(b: PartBatch, base: Vector2, radius: float = 1.0, height: float = 1.8, glow: bool = true) -> void:
	b.add_cylinder(radius, height, Vector3(base.x, height * 0.5, base.y), COL_STONE_DARK)
	b.add_pyramid(radius * 0.8, radius * 0.8, 0.7, Vector3(base.x, height, base.y), COL_STONE, 0.0, false)
	chimney(b, Vector3(base.x, height + 0.3, base.y - radius * 0.3), 1.8)
	if glow:
		b.add_box(Vector3(0.55, 0.45, 0.1), Vector3(base.x, 0.5, base.y + radius - 0.02), Color(1.0, 0.55, 0.18), 0.0, false)

## Bottich/Küpe/Kessel: niedriger Zylinder mit farbiger Flüssigkeit obenauf.
static func vat(b: PartBatch, center: Vector2, radius: float, liquid: Color, wall: Color = COL_WOOD_DARK, height: float = 0.8) -> void:
	b.add_cylinder(radius, height, Vector3(center.x, height * 0.5, center.y), wall)
	b.add_cylinder(radius * 0.86, 0.04, Vector3(center.x, height + 0.01, center.y), liquid, false)

## Trockengestell: zwei Pfosten, Querstange, daran hängende Tücher/Felle (Farben der Reihe nach).
## from/to = Pfostenfüße (lokal x/z).
static func drying_rack(b: PartBatch, from: Vector2, to: Vector2, cloths: Array, height: float = 1.9) -> void:
	var dir: Vector2 = to - from
	var length: float = dir.length()
	if length < 0.5:
		return
	var theta: float = atan2(-dir.y, dir.x)
	var mid: Vector2 = (from + to) * 0.5
	for p: Vector2 in [from, to]:
		b.add_box(Vector3(0.12, height, 0.12), Vector3(p.x, height * 0.5, p.y), COL_WOOD_DARK, theta, false)
	b.add_box(Vector3(length, 0.08, 0.08), Vector3(mid.x, height, mid.y), COL_WOOD, theta, false)
	var n: int = cloths.size()
	for i in range(n):
		var t: float = length * (float(i) + 0.5) / float(n)
		var pt: Vector2 = from + dir.normalized() * t
		b.add_box(Vector3(length / float(n) * 0.8, height * 0.55, 0.04), Vector3(pt.x, height * 0.72, pt.y), cloths[i] as Color, theta, false)
	# Kollision: eine dünne Wand, damit man nicht durch die Tücher läuft.
	b.add_box(Vector3(length, height, 0.1), Vector3(mid.x, height * 0.5, mid.y), COL_WOOD, theta, true)

## Liegendes Rad (Radstapel beim Wagner). Zylinder flach, `layers` übereinander.
static func wheel_stack(b: PartBatch, base: Vector2, radius: float = 0.7, layers: int = 3) -> void:
	for i in range(layers):
		b.add_cylinder(radius, 0.12, Vector3(base.x, 0.06 + 0.13 * float(i), base.y), COL_WOOD_LIGHT, i == 0, 12)
		b.add_cylinder(0.12, 0.14, Vector3(base.x, 0.07 + 0.13 * float(i), base.y), COL_WOOD_DARK, false, 6)

## Käselaib-Regal: Tisch mit gestapelten Laiben.
static func cheese_rack(b: PartBatch, center: Vector2, rot: float = 0.0) -> void:
	table(b, center, rot, Vector2(1.8, 0.8))
	for i in range(3):
		var off := Vector3((float(i) - 1.0) * 0.55, 0.0, 0.0).rotated(Vector3.UP, rot)
		b.add_cylinder(0.24, 0.16, Vector3(center.x + off.x, 0.90, center.y + off.z), Color(0.90, 0.76, 0.32), false, 8)
		b.add_cylinder(0.2, 0.14, Vector3(center.x + off.x, 1.05, center.y + off.z), Color(0.94, 0.82, 0.40), false, 8)

## Tontöpfe auf einem Brett (Töpferei): Reihe kleiner Zylinder.
static func pots(b: PartBatch, from: Vector2, count: int, step: float = 0.5) -> void:
	for i in range(count):
		b.add_cylinder(0.17, 0.36, Vector3(from.x + step * float(i), 0.18, from.y), Color(0.70, 0.38, 0.22), false, 8)

## Häufchen (Sand/Salz): flache Pyramide, nur Optik.
static func heap(b: PartBatch, base: Vector2, radius: float, rise: float, color: Color) -> void:
	b.add_pyramid(radius, radius, rise, Vector3(base.x, 0.0, base.y), color, 0.0, false)

## Umgedrehtes Boot: Rumpf aus Boxen. Länge entlang lokal Z, drehbar.
static func boat(b: PartBatch, center: Vector2, rot: float = 0.0) -> void:
	b.add_box(Vector3(1.3, 0.55, 3.4), Vector3(center.x, 0.45, center.y), Color(0.34, 0.25, 0.16), rot, true)
	b.add_box(Vector3(0.9, 0.35, 3.0), Vector3(center.x, 0.85, center.y), Color(0.42, 0.30, 0.18), rot, false)
	b.add_box(Vector3(0.12, 0.2, 3.6), Vector3(center.x, 0.12, center.y), COL_WOOD_DARK, rot, false)

## Webstuhl: zwei Pfosten, zwei Walzen, Kettfäden (dünne Boxen).
static func loom(b: PartBatch, center: Vector2) -> void:
	for sx: float in [-0.9, 0.9]:
		b.add_box(Vector3(0.14, 2.0, 0.14), Vector3(center.x + sx, 1.0, center.y), COL_WOOD_DARK, 0.0, false)
	b.add_box(Vector3(1.9, 0.12, 0.12), Vector3(center.x, 1.9, center.y), COL_WOOD, 0.0, false)
	b.add_box(Vector3(1.9, 0.12, 0.12), Vector3(center.x, 0.5, center.y), COL_WOOD, 0.0, false)
	for i in range(7):
		b.add_box(Vector3(0.02, 1.3, 0.02), Vector3(center.x - 0.72 + 0.24 * float(i), 1.2, center.y), Color(0.86, 0.82, 0.66), 0.0, false)
	b.add_box(Vector3(1.9, 1.5, 0.3), Vector3(center.x, 0.75, center.y), COL_WOOD, 0.0, true)

## Steg: Bretter von `from` nach `to` (nur begehbar, Kollision = ein Brett).
static func jetty(b: PartBatch, from: Vector2, to: Vector2, width: float = 1.4) -> void:
	var dir: Vector2 = to - from
	var length: float = dir.length()
	if length < 0.5:
		return
	var theta: float = atan2(-dir.y, dir.x)
	var mid: Vector2 = (from + to) * 0.5
	b.add_box(Vector3(length, 0.1, width), Vector3(mid.x, 0.12, mid.y), COL_WOOD_LIGHT, theta, true)
	var posts: int = maxi(2, int(length / 1.6))
	for i in range(posts):
		var p: Vector2 = from + dir.normalized() * (length * float(i) / float(posts - 1))
		b.add_box(Vector3(0.14, 0.9, 0.14), Vector3(p.x, 0.0, p.y), COL_WOOD_DARK, theta, false)

## Lokaler Offset (x, y, z) um `center` (x/z) mit rot gedreht → Weltpunkt im Gebäudesystem.
static func _rot_off(center: Vector2, rot: float, local: Vector3) -> Vector3:
	var o: Vector3 = local.rotated(Vector3.UP, rot)
	return Vector3(center.x + o.x, local.y, center.y + o.z)
