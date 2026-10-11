class_name CanopyTree
extends RefCounted

## CanopyTree — Geometrie EINES Riesenbaums des Baumdorfs (Rezept, wie BuildingRecipes für Bodenhäuser).
##
## Lokale Koordinaten: Ursprung = Stammmitte am Boden, y = 0 = höchster Geländepunkt unter dem Baum
## (Wurzelanlauf reicht darunter). Alles ist aus PartBatch-Primitiven gebaut, begehbare Teile haben Kollision.
##
## Aufbau von unten nach oben
##   Wurzeln + Stamm   5 Kegelstümpfe (Radius 4.6 → 2.6 m), Höhe = oberste Ebene + 14–16 m
##   Rampe             Wendel um den Stamm (Radius 11.2 m, 15° Steigung, 1.8 m breit) vom Boden bis zur
##                     obersten Ebene; an jeder Ebene führt ein flacher Steg auf die Plattform
##   Plattformen       runde Decks (Radius 9.5 m) auf den Ebenen LEVELS, Geländer rundum mit Lücken
##   Hütten            Wohnhäuser (Bausteine aus StructureParts) im Ring um den Stamm, Tür nach außen
##   Halle             optional auf der obersten Ebene des Altbaums (offener Pavillon)
##   Brückenhälften    je Link eine halbe Hängebrücke bis zur Mitte; der Nachbarbaum baut die andere Hälfte
##   Krone             gestapelte Blätterscheiben + Büschel (nur Optik)
##
## Alle Maße sind Konstanten hier; CanopyLayout kennt nur die Größen FOOTPRINT_HALF/LEVELS.

const FOOTPRINT_HALF: float = 12.5

## Höhen der Plattform-Ebenen über dem Boden. Ebene BRIDGE_LEVEL trägt die Hängebrücken (bei allen Bäumen gleich hoch).
const LEVELS: Array[float] = [7.0, 13.5, 20.0, 26.5]
const BRIDGE_LEVEL: int = 1

const PLATFORM_R: float = 9.5
const PLATFORM_T: float = 0.45
const RAIL_R: float = 9.3
const RAIL_H: float = 1.0
const RAIL_GAP: float = 0.32          ## halbe Lücke (rad) im Geländer an Zufahrten und Brücken

const RAMP_R: float = 11.2
const RAMP_W: float = 1.8
const RAMP_T: float = 0.35
const RAMP_SLOPE: float = 0.27        ## Steigung (≈ 15°)
const RAMP_STEP: float = 0.175        ## Bogenmaß je Rampenstück
const LEAD_IN_R0: float = 10.45       ## äußeres Ende der Zufahrt (ragt 15 cm in die Rampe)
const LEAD_IN_R1: float = 9.0
const LEAD_IN_W: float = 2.0

const ANCHOR_R: float = 9.2           ## Brückenanker am Plattformrand
const BRIDGE_W: float = 1.6
const BRIDGE_T: float = 0.18
const BRIDGE_SAG: float = 1.2
const BRIDGE_SEG: float = 2.4

const HUT_R: float = 5.3
const HUT_BLOCK_MARGIN: float = 0.5   ## Abstand (rad) der Hütten zu Zufahrt/Brücke
const HUT_MIN_SEP: float = 1.0
const HUT_SLOTS: int = 12

const CROWN_CLEARANCE: float = 14.0
const ELDER_CROWN_CLEARANCE: float = 16.0
const MIN_LANDING_SEP: float = 0.6    ## Zufahrt ↔ Brücke (rad)
const MIN_PASS_CLEARANCE: float = 2.6 ## Rampe ↔ Brücke senkrecht (m), wo die Rampe die Brücke kreuzt
const PHASE_STEPS: int = 120

const COL_BARK := Color(0.34, 0.26, 0.19)
const COL_BARK_DARK := Color(0.26, 0.19, 0.13)
const COL_DECK := Color(0.56, 0.42, 0.26)
const COL_TIMBER := Color(0.40, 0.29, 0.17)
const COL_PLAZA := Color(0.46, 0.43, 0.38)
const LEAF_COLORS: Array[Color] = [
	Color(0.20, 0.40, 0.16), Color(0.26, 0.47, 0.18), Color(0.19, 0.36, 0.22), Color(0.33, 0.49, 0.17),
]
const HUT_WALLS: Array[Color] = [
	Color(0.55, 0.40, 0.24), Color(0.45, 0.33, 0.20), Color(0.62, 0.50, 0.32), Color(0.50, 0.42, 0.30),
]
const HUT_ROOFS: Array[Color] = [
	Color(0.30, 0.45, 0.20), Color(0.60, 0.52, 0.26), Color(0.42, 0.22, 0.16), Color(0.28, 0.38, 0.24),
]
const TRUNK_RADII: Array[float] = [4.6, 4.1, 3.6, 3.1, 2.6]

# ─────────────────────────────────────────────
# Rampen-Mathematik (auch von CanopyLayout und den Tests benutzt)
# ─────────────────────────────────────────────

## Höhengewinn je Bogenmaß der Rampe (m/rad).
static func ramp_c() -> float:
	return RAMP_SLOPE * RAMP_R

## Rampenhöhe bei (abgewickeltem) Winkel `theta`; `phase` = Startwinkel, `y0` = Starthöhe (Boden-Tiefstpunkt).
static func ramp_y(theta: float, phase: float, y0: float) -> float:
	return y0 + ramp_c() * (theta - phase)

static func ramp_point(theta: float, phase: float, y0: float, radius: float = RAMP_R) -> Vector3:
	return Vector3(cos(theta) * radius, ramp_y(theta, phase, y0), sin(theta) * radius)

## Winkel, bei dem die Rampe Höhe `level_y` erreicht (dort liegt die Zufahrt zur Plattform).
static func landing_angle(level_y: float, phase: float, y0: float) -> float:
	return phase + (level_y - y0) / ramp_c()

static func ang_diff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))

static func level_heights(level_count: int) -> Array:
	return LEVELS.slice(0, clampi(level_count, 1, LEVELS.size()))

## Welt-(x,z)-Offset des Rampenanfangs zur Baummitte (dort mündet der Fußweg).
static func ramp_start_offset(phase: float) -> Vector2:
	return Vector2(cos(phase), sin(phase)) * RAMP_R

## Wie gut passt Startwinkel `phase`? (≥ 1 = alle Abstandsregeln eingehalten, kleiner = schlechter.)
## Regeln: Zufahrten liegen ≥ MIN_LANDING_SEP neben Brückenankern; dort, wo die Rampe die Brückenachse
## kreuzt, liegt sie ≥ MIN_PASS_CLEARANCE über/unter der Brücke.
static func phase_score(phase: float, level_ys: Array, link_angles: Array, y0: float) -> float:
	if link_angles.is_empty():
		return 1.0
	var c: float = ramp_c()
	var top: float = float(level_ys[level_ys.size() - 1])
	var bridge_y: float = LEVELS[BRIDGE_LEVEL]
	var score: float = INF
	for a: float in link_angles:
		for ly: float in level_ys:
			score = minf(score, ang_diff(a, landing_angle(ly, phase, y0)) / MIN_LANDING_SEP)
		var delta: float = wrapf(a - phase, 0.0, TAU)
		var k: int = 0
		while true:
			var y: float = y0 + c * (delta + TAU * float(k))
			if y > top + MIN_PASS_CLEARANCE:
				break
			score = minf(score, absf(y - bridge_y) / MIN_PASS_CLEARANCE)
			k += 1
	return score

## Bester von PHASE_STEPS gleichmäßigen Startwinkeln (deterministisch; `salt` verteilt die Bäume ohne Brücken).
static func pick_phase(level_ys: Array, link_angles: Array, y0: float, salt: int) -> float:
	var best_phase: float = 0.0
	var best_score: float = -INF
	for k in range(PHASE_STEPS):
		var ph: float = TAU * float((k + absi(salt)) % PHASE_STEPS) / float(PHASE_STEPS)
		var sc: float = phase_score(ph, level_ys, link_angles, y0)
		if sc > best_score + 0.000001:
			best_score = sc
			best_phase = ph
	return best_phase

## Hüttenwinkel einer Ebene: bis `count` Plätze im 30°-Raster ab `start`, ≥ HUT_MIN_SEP auseinander und
## ≥ HUT_BLOCK_MARGIN von gesperrten Winkeln (Zufahrt, Brücken).
static func hut_angles(count: int, blocked: Array, start: int) -> Array[float]:
	var out: Array[float] = []
	for k in range(HUT_SLOTS):
		if out.size() >= count:
			break
		var a: float = TAU * float((k + start) % HUT_SLOTS) / float(HUT_SLOTS)
		var ok: bool = true
		for bl: float in blocked:
			if ang_diff(a, bl) < HUT_BLOCK_MARGIN:
				ok = false
		for o: float in out:
			if ang_diff(a, o) < HUT_MIN_SEP:
				ok = false
		if ok:
			out.append(a)
	return out

## Mittellinie einer Brückenhälfte (lokal zur Baummitte): vom Anker bis zur Brückenmitte.
## link: {mx, mz = Offset der Brückenmitte, dh = Höhe Nachbar − eigene Höhe}. Beide Bäume berechnen
## dieselbe Gesamtbrücke (lineare Höhe + Durchhang), jeder baut seine Hälfte → sie treffen sich in der Mitte.
static func bridge_points(link: Dictionary, level_y: float) -> PackedVector3Array:
	var m := Vector2(float(link["mx"]), float(link["mz"]))
	var d: float = m.length()
	var pts := PackedVector3Array()
	if d <= ANCHOR_R + 1.0:
		return pts
	var dir: Vector2 = m / d
	var half_len: float = d - ANCHOR_R
	var n: int = maxi(2, ceili(half_len / BRIDGE_SEG))
	var dh: float = float(link["dh"])
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		var u: float = 0.5 * t
		var r: float = ANCHOR_R + half_len * t
		# Höhenunterschied weich (smoothstep) und Durchhang als sin²: beide laufen mit Steigung 0 in die
		# Plattformen, sonst stünde der Deckrand als Kante vor der Brücke (Physiktest). Beide Funktionen sind
		# symmetrisch (f(1−u) = 1−f(u) bzw. f(1−u) = f(u)) → beide Hälften treffen sich exakt in der Mitte.
		var smooth: float = u * u * (3.0 - 2.0 * u)
		var sag: float = BRIDGE_SAG * pow(sin(PI * u), 2.0)
		pts.append(Vector3(dir.x * r, level_y + dh * smooth - sag, dir.y * r))
	return pts

# ─────────────────────────────────────────────
# Bauen
# ─────────────────────────────────────────────

## role: "elder" (Dorfmitte) oder "grove". info: Gebäude-Datensatz (spread, params) — leer = Standardbaum.
## params: level_count, huts (Array[int] je Ebene), hall (bool), phase (rad), links (Array[Dictionary]).
static func build(b: PartBatch, role: String, variant: int, slab_depth: float, info: Dictionary) -> void:
	var params: Dictionary = info.get("params", {}) as Dictionary
	var is_elder: bool = role == "elder"
	var level_count: int = clampi(int(params.get("level_count", 3 if is_elder else 2)), 2, LEVELS.size())
	var level_ys: Array = level_heights(level_count)
	var huts: Array = params.get("huts", [3, 3, 0] if is_elder else [2, 2]) as Array
	var hall: bool = bool(params.get("hall", false))
	var phase: float = float(params.get("phase", 0.0))
	var links: Array = params.get("links", []) as Array
	var spread: float = float(info.get("spread", maxf(0.0, slab_depth - 1.4)))
	var y0: float = -spread
	var top: float = float(level_ys[level_ys.size() - 1])
	var height: float = top + (ELDER_CROWN_CLEARANCE if is_elder else CROWN_CLEARANCE)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(variant) * 7919 + 13
	var link_angles: Array = []
	for l: Dictionary in links:
		link_angles.append(atan2(float(l["mz"]), float(l["mx"])))

	_trunk(b, height, slab_depth)
	_roots(b)
	_crown(b, height, variant, rng)
	for li in range(level_ys.size()):
		var ly: float = float(level_ys[li])
		var landing: float = landing_angle(ly, phase, y0)
		var gaps: Array = [landing]
		if li == BRIDGE_LEVEL:
			gaps.append_array(link_angles)
		_platform(b, ly, li, gaps)
		var is_hall_level: bool = hall and li == level_ys.size() - 1
		if is_hall_level:
			_hall(b, ly)
		else:
			var count: int = int(huts[li]) if li < huts.size() else 0
			var angles: Array[float] = hut_angles(count, gaps, (variant + li * 5) % HUT_SLOTS)
			for k in range(angles.size()):
				_hut(b, angles[k], ly, variant + k * 3 + li)
	_ramp(b, level_ys, phase, y0, slab_depth)
	for ly2: float in level_ys:
		_lead_in(b, float(ly2), phase, y0)
	for l2: Dictionary in links:
		_bridge(b, l2)
	_ground_props(b, is_elder, variant)

static func _yaw_for_x(dx: float, dz: float) -> float:
	return atan2(-dz, dx)

static func _trunk(b: PartBatch, height: float, slab_depth: float) -> void:
	var base_top: float = 3.0
	b.add_frustum(7.0, TRUNK_RADII[0], base_top + slab_depth, Vector3(0.0, (base_top - slab_depth) * 0.5, 0.0), COL_BARK_DARK, true, 14)
	var ys: Array[float] = [base_top, height * 0.3, height * 0.55, height * 0.8, height]
	for i in range(4):
		var h: float = ys[i + 1] - ys[i]
		var col: Color = COL_BARK.lerp(COL_BARK_DARK, 0.35 * float(i % 2))
		b.add_frustum(TRUNK_RADII[i], TRUNK_RADII[i + 1], h, Vector3(0.0, ys[i] + h * 0.5, 0.0), col, true, 14)

## Wurzelanläufe (nur Optik): schräge Balken vom Boden zum Stamm.
static func _roots(b: PartBatch) -> void:
	for k in range(6):
		var a: float = TAU * float(k) / 6.0 + 0.3
		b.add_plank(
			Vector3(cos(a) * 8.0, -0.3, sin(a) * 8.0), Vector3(cos(a) * 4.2, 3.0, sin(a) * 4.2),
			1.6, 1.4, COL_BARK_DARK, false)

static func _crown(b: PartBatch, height: float, variant: int, rng: RandomNumberGenerator) -> void:
	var leaf: Color = LEAF_COLORS[absi(variant) % LEAF_COLORS.size()]
	var leaf2: Color = LEAF_COLORS[(absi(variant) + 1) % LEAF_COLORS.size()]
	b.add_frustum(12.0, 16.0, 3.2, Vector3(0.0, height - 5.0, 0.0), leaf, false, 12)
	b.add_frustum(16.0, 13.0, 3.4, Vector3(0.0, height - 2.0, 0.0), leaf2, false, 12)
	b.add_frustum(13.0, 8.0, 3.2, Vector3(0.0, height + 1.1, 0.0), leaf, false, 12)
	b.add_frustum(8.0, 2.5, 3.0, Vector3(0.0, height + 3.9, 0.0), leaf2, false, 10)
	for k in range(6):
		var a: float = TAU * float(k) / 6.0 + rng.randf() * 0.5
		var r: float = 12.5 + rng.randf() * 2.5
		b.add_frustum(4.8, 3.2, 4.0, Vector3(cos(a) * r, height - 5.5 + rng.randf() * 2.0, sin(a) * r), leaf if k % 2 == 0 else leaf2, false, 8)

## Deck der Ebene `level_y` + Streben darunter + Geländer (Lücken bei `gaps`: Zufahrt, Brücken).
static func _platform(b: PartBatch, level_y: float, level_index: int, gaps: Array) -> void:
	b.add_cylinder(PLATFORM_R, PLATFORM_T, Vector3(0.0, level_y - PLATFORM_T * 0.5, 0.0), COL_DECK, true, 16)
	for k in range(4):
		var a: float = TAU * float(k) / 4.0 + 0.4 * float(level_index) + 0.3
		b.add_plank(
			Vector3(cos(a) * 3.2, level_y - 3.8, sin(a) * 3.2), Vector3(cos(a) * 8.8, level_y - PLATFORM_T, sin(a) * 8.8),
			0.7, 0.5, COL_TIMBER, false)
	var n: int = 16
	var posts: Array = []
	for k in range(n):
		var a2: float = TAU * float(k) / float(n) + 0.19
		var skip: bool = false
		for g: float in gaps:
			if ang_diff(a2, g) < RAIL_GAP:
				skip = true
		if skip:
			posts.append(null)
			continue
		var p := Vector2(cos(a2), sin(a2)) * RAIL_R
		posts.append(p)
		b.add_box(Vector3(0.14, RAIL_H, 0.14), Vector3(p.x, level_y + RAIL_H * 0.5, p.y), COL_TIMBER, 0.0, false)
	for k in range(n):
		var p0: Variant = posts[k]
		var p1: Variant = posts[(k + 1) % n]
		if p0 == null or p1 == null:
			continue
		var v0 := p0 as Vector2
		var v1 := p1 as Vector2
		b.add_plank(Vector3(v0.x, level_y + RAIL_H, v0.y), Vector3(v1.x, level_y + RAIL_H, v1.y), 0.12, 0.7, COL_DECK, true)

## Wohnhütte auf Plattformhöhe `level_y`, Tür nach außen (zum Rand).
static func _hut(b: PartBatch, angle: float, level_y: float, variant: int) -> void:
	var wall: Color = HUT_WALLS[absi(variant) % HUT_WALLS.size()]
	var roof: Color = HUT_ROOFS[absi(variant / 2) % HUT_ROOFS.size()]
	b.push_group(Vector3(cos(angle) * HUT_R, level_y, sin(angle) * HUT_R), atan2(cos(angle), sin(angle)))
	var rect := Rect2(-1.8, -1.4, 3.6, 2.8)
	StructureParts.box_house(b, rect, 2.5, wall, 1.0, 2.0, 0, 0.0, 1)
	if absi(variant) % 3 == 0:
		StructureParts.pyramid_over(b, rect, 2.5, 1.7, roof)
	else:
		StructureParts.gable_over(b, rect, 2.5, 1.4, roof)
	StructureParts.bed(b, Vector2(-0.9, -0.2))
	StructureParts.lamp_post(b, Vector2(-1.5, 1.9), 2.0)
	StructureParts.barrel(b, Vector2(1.5, 1.9))
	b.pop_group()

## Offene Versammlungshalle auf der obersten Ebene des Altbaums (Stamm steht in der Mitte).
static func _hall(b: PartBatch, level_y: float) -> void:
	b.push_group(Vector3(0.0, level_y, 0.0), 0.0)
	for sx: float in [-4.6, 4.6]:
		for sz: float in [-4.6, 4.6]:
			b.add_box(Vector3(0.3, 3.2, 0.3), Vector3(sx, 1.6, sz), COL_TIMBER, 0.0, true)
	b.add_pyramid(6.0, 6.0, 2.6, Vector3(0.0, 3.2, 0.0), HUT_ROOFS[0], 0.0, false)
	StructureParts.bench(b, Vector2(3.9, 0.0), PI * 0.5, 2.2)
	StructureParts.bench(b, Vector2(-3.9, 0.0), PI * 0.5, 2.2)
	StructureParts.bench(b, Vector2(0.0, 3.9), 0.0, 2.2)
	StructureParts.bench(b, Vector2(0.0, -3.9), 0.0, 2.2)
	for corner: Vector2 in [Vector2(7.6, 0.0), Vector2(-7.6, 0.0), Vector2(0.0, 7.6), Vector2(0.0, -7.6)]:
		StructureParts.lamp_post(b, corner, 2.2, true)
	b.pop_group()

## Wendelrampe um den Stamm vom Boden bis zur obersten Plattform, mit Stützen und Außengeländer.
static func _ramp(b: PartBatch, level_ys: Array, phase: float, y0: float, slab_depth: float) -> void:
	var th_end: float = landing_angle(float(level_ys[level_ys.size() - 1]), phase, y0) + 0.06
	var n: int = ceili((th_end - phase) / RAMP_STEP)
	var r_out: float = RAMP_R + RAMP_W * 0.5 + 0.05
	for i in range(n):
		var ta: float = phase + float(i) * RAMP_STEP
		var tb: float = minf(phase + float(i + 1) * RAMP_STEP, th_end)
		var pa: Vector3 = ramp_point(ta, phase, y0)
		var pb: Vector3 = ramp_point(tb, phase, y0)
		if i < n - 1:
			pb += (pb - pa).normalized() * 0.1
		b.add_plank(pa, pb, RAMP_W, RAMP_T, COL_DECK, true)
		if pa.y > 0.2:
			var oa: Vector3 = ramp_point(ta, phase, y0, r_out) + Vector3(0.0, RAIL_H, 0.0)
			var ob: Vector3 = ramp_point(tb, phase, y0, r_out) + Vector3(0.0, RAIL_H, 0.0)
			b.add_plank(oa, ob, 0.1, 0.8, COL_TIMBER, true)
		if i % 3 == 1 and pa.y > 1.0:
			var under: float = pa.y - RAMP_T
			b.add_box(Vector3(0.45, under + slab_depth, 0.45), Vector3(pa.x, (under - slab_depth) * 0.5, pa.z), COL_BARK_DARK, 0.0, true)

## Zufahrt von der Rampe auf die Plattform der Ebene `level_y`: ein FLACHER Steg auf Deckhöhe, der dort liegt,
## wo die Rampe genau diese Höhe erreicht (Winkel landing_angle). Flach und bündig mit dem Deck, damit es weder
## eine Kante am Deckrand noch eine Kante zur Rampe gibt, an der man hängen bleibt (Physiktest sichert das ab).
## Er reicht nur 15 cm in den Rampenring: Wer auf der Rampe die Deckhöhe erreicht, tritt nach innen auf den Steg.
static func _lead_in(b: PartBatch, level_y: float, phase: float, y0: float) -> void:
	var phi: float = landing_angle(level_y, phase, y0)
	var p0 := Vector3(cos(phi) * LEAD_IN_R0, level_y, sin(phi) * LEAD_IN_R0)
	var p1 := Vector3(cos(phi) * LEAD_IN_R1, level_y, sin(phi) * LEAD_IN_R1)
	b.add_plank(p0, p1, LEAD_IN_W, 0.3, COL_DECK, true)

## Brückenhälfte zu einem Nachbarbaum (Planken + beidseitiges Geländer).
static func _bridge(b: PartBatch, link: Dictionary) -> void:
	var pts: PackedVector3Array = bridge_points(link, LEVELS[BRIDGE_LEVEL])
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var dir: Vector3 = (c - a).normalized()
		var c_ext: Vector3 = c + dir * 0.08
		b.add_plank(a, c_ext, BRIDGE_W, BRIDGE_T, COL_DECK, true)
		var side: Vector3 = dir.cross(Vector3.UP).normalized() * (BRIDGE_W * 0.5 - 0.05)
		for s: float in [-1.0, 1.0]:
			b.add_plank(a + side * s + Vector3(0.0, 1.0, 0.0), c_ext + side * s + Vector3(0.0, 1.0, 0.0), 0.08, 0.85, COL_TIMBER, true)

## Bodenschmuck am Stammfuß (nur innerhalb des Rampenrings, r < 8.5 m).
static func _ground_props(b: PartBatch, is_elder: bool, variant: int) -> void:
	if is_elder:
		b.add_frustum(6.6, 6.6, 0.1, Vector3(0.0, 0.05, 0.0), COL_PLAZA, false, 16)
		for k in range(4):
			var a: float = TAU * float(k) / 4.0 + 0.4
			StructureParts.bench(b, Vector2(cos(a), sin(a)) * 6.0, _yaw_for_x(-sin(a), cos(a)), 1.8)
		StructureParts.lamp_post(b, Vector2(cos(0.4 + PI * 0.25), sin(0.4 + PI * 0.25)) * 6.8, 2.6, true)
		StructureParts.lamp_post(b, Vector2(cos(0.4 + PI * 1.25), sin(0.4 + PI * 1.25)) * 6.8, 2.6, true)
		StructureParts.barrel(b, Vector2(5.4, -4.2))
		StructureParts.crate(b, Vector2(-5.2, -4.6))
	else:
		var a2: float = float(absi(variant) % 8) * TAU / 8.0
		StructureParts.lamp_post(b, Vector2(cos(a2), sin(a2)) * 6.2, 2.4)
		StructureParts.crate(b, Vector2(cos(a2 + 2.0), sin(a2 + 2.0)) * 5.8)
		StructureParts.barrel(b, Vector2(cos(a2 + 2.5), sin(a2 + 2.5)) * 5.8)
