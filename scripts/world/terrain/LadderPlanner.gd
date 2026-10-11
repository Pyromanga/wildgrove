class_name LadderPlanner
extends RefCounted

## LadderPlanner — plant, wo und wie lang eine Leiter an einer Grubenwand verläuft.
##
## Reine Rechenklasse (kein Node, kein Inventar, keine Welt): bekommt nur die Höhenfunktion
## des Geländes (TerrainField.get_height_at) und liefert einen fertigen Record für
## LadderRegistry — oder einen Ablehnungsgrund. Dadurch komplett ohne Szene testbar.
##
## ABLAUF
##   1. Vom Spieler aus in Blickrichtung nach einer Wand suchen (WALL_SCAN Meter weit):
##      steigt das Gelände um MIN_RISE, ist es eine Wand NACH OBEN (Spieler steht unten);
##      fällt es um MIN_RISE, ist es die Kante einer Grube (Spieler steht am Rand oben).
##   2. Den Wandfuß ("Toe") bestimmen: im ersten Fall der letzte Punkt auf Bodenhöhe vor der
##      Wand, im zweiten Fall der tiefste Punkt der Grube (dort hört das Gefälle auf).
##   3. Vom Fuß aus der Wand folgen (Richtung zur Wand), bis das Gelände oben wieder
##      abflacht (Rand) — oder eine schon vorhandene Leiter beginnt (Anschluss).
##   4. Den Linienzug in Punkte alle POINT_SPACING Meter ausdünnen und WALL_CLEARANCE vor
##      die Wand in die Luft rücken (siehe LadderPath).
##
## KOSTEN: METERS_PER_LADDER Meter Leiter pro Item (aufgerundet, mindestens 1).

const LADDER_ITEM: String = "ladder"

const SCAN_STEP: float = 0.25
## Wie weit vor dem Spieler nach der Wand gesucht wird (der ebene Grubenboden ist ~4 m breit).
const WALL_SCAN: float = 6.0
## Ab diesem Höhenunterschied gilt Gelände als Wand.
const MIN_RISE: float = 1.5
## Bis zu dieser Höhe über dem Boden zählt ein Punkt noch zum Wandfuß.
const TOE_TOLERANCE: float = 0.4
## Abflachen (Rand oben): über die nächsten PLATEAU_WINDOW Schritte steigt es < PLATEAU_RISE.
const PLATEAU_WINDOW: int = 6
const PLATEAU_RISE: float = 0.3
## Längster waagerechter Weg an der Wand entlang, und längste Leiter überhaupt.
const MAX_RUN: float = 16.0
const MAX_LENGTH: float = 40.0
const MIN_LENGTH: float = 1.0
const POINT_SPACING: float = 1.0
const METERS_PER_LADDER: float = 4.0
## Anschluss an eine vorhandene Leiter: deren Fuß höchstens so weit (waagerecht / senkrecht) entfernt.
const JOIN_RADIUS: float = 1.0
const JOIN_DY: float = 1.2
## Wie weit hinter dem Kopf der Ausstiegspunkt oben liegt (auf dem Rand).
const EXIT_PUSH: float = 0.8

## origin: Spielerposition. facing: waagerechte Blickrichtung (y wird ignoriert).
## ground_fn(x, z) -> float: Geländehöhe (NAN = unbekannt).
## join_fn(pos: Vector3) -> bool (optional): true, wenn an `pos` eine Leiter ansetzt.
##
## Rückgabe: {ok: bool, reason: String, record: Dictionary, cost: Dictionary}
##   reason: "" | "no_ground" | "no_wall" | "too_long"
static func plan(origin: Vector3, facing: Vector3, ground_fn: Callable, join_fn: Callable = Callable()) -> Dictionary:
	var f2 := Vector2(facing.x, facing.z)
	if f2.length_squared() < 0.0001:
		return _fail("no_wall")
	f2 = f2.normalized()
	var y0: float = _h(ground_fn, origin.x, origin.z)
	if is_nan(y0):
		return _fail("no_ground")

	# 1. Wand suchen.
	var mode: int = 0        # 1 = Wand steigt (Spieler unten), -1 = Gelände fällt (Spieler am Rand)
	var d_hit: float = 0.0
	var d: float = 0.0
	while d <= WALL_SCAN:
		var h: float = _h(ground_fn, origin.x + f2.x * d, origin.z + f2.y * d)
		if is_nan(h):
			return _fail("no_ground")
		if h - y0 >= MIN_RISE:
			mode = 1
			d_hit = d
			break
		if y0 - h >= MIN_RISE:
			mode = -1
			d_hit = d
			break
		d += SCAN_STEP
	if mode == 0:
		return _fail("no_wall")

	# 2. Wandfuß.
	var toe_d: float = 0.0
	var wall_dir := f2
	if mode == 1:
		toe_d = d_hit
		while toe_d > 0.0 and _h(ground_fn, origin.x + f2.x * toe_d, origin.z + f2.y * toe_d) - y0 > TOE_TOLERANCE:
			toe_d -= SCAN_STEP
		toe_d = maxf(toe_d, 0.0)
	else:
		wall_dir = -f2
		toe_d = -1.0
		var dd: float = d_hit
		while dd <= d_hit + MAX_RUN:
			var here: float = _h(ground_fn, origin.x + f2.x * dd, origin.z + f2.y * dd)
			var next1: float = _h(ground_fn, origin.x + f2.x * (dd + SCAN_STEP), origin.z + f2.y * (dd + SCAN_STEP))
			var next2: float = _h(ground_fn, origin.x + f2.x * (dd + 2.0 * SCAN_STEP), origin.z + f2.y * (dd + 2.0 * SCAN_STEP))
			if next1 >= here - 0.05 and next2 >= here - 0.05:
				toe_d = dd
				break
			dd += SCAN_STEP
		if toe_d < 0.0:
			return _fail("no_wall")
	var toe := Vector2(origin.x + f2.x * toe_d, origin.z + f2.y * toe_d)

	# 3. Der Wand folgen.
	var samples: Array[Vector3] = []
	var h0: float = _h(ground_fn, toe.x, toe.y)
	var max_samples: int = int(MAX_RUN / SCAN_STEP)
	for i in range(max_samples + 1):
		var px: float = toe.x + wall_dir.x * SCAN_STEP * float(i)
		var pz: float = toe.y + wall_dir.y * SCAN_STEP * float(i)
		var ph: float = _h(ground_fn, px, pz)
		if is_nan(ph):
			return _fail("no_ground")
		samples.append(Vector3(px, ph, pz))
		if i >= PLATEAU_WINDOW:
			var k: int = i - PLATEAU_WINDOW
			if samples[k].y - h0 >= MIN_RISE and samples[i].y - samples[k].y < PLATEAU_RISE:
				samples.resize(k + 1)
				break
		if join_fn.is_valid() and samples[i].y - h0 >= 1.0 and bool(join_fn.call(samples[i])):
			break
	if samples.size() < 2 or samples[samples.size() - 1].y - h0 < 1.0:
		return _fail("no_wall")

	# 4. Linienzug ausdünnen und vor die Wand rücken.
	var wd3 := Vector3(wall_dir.x, 0.0, wall_dir.y)
	var off: Vector3 = -wd3 * LadderPath.WALL_CLEARANCE
	var pts := PackedVector3Array()
	pts.append(samples[0] + off)
	var since: float = 0.0
	for i in range(1, samples.size()):
		since += samples[i - 1].distance_to(samples[i])
		if since >= POINT_SPACING or i == samples.size() - 1:
			pts.append(samples[i] + off)
			since = 0.0
	var length: float = 0.0
	for i in range(1, pts.size()):
		length += pts[i - 1].distance_to(pts[i])
	if length > MAX_LENGTH:
		return _fail("too_long")
	if length < MIN_LENGTH:
		return _fail("no_wall")

	# Ausstiege: oben auf dem Rand hinter dem Kopf, unten auf dem Boden vor dem Fuß.
	var top: Vector3 = samples[samples.size() - 1]
	var ex: float = top.x + wall_dir.x * EXIT_PUSH
	var ez: float = top.z + wall_dir.y * EXIT_PUSH
	var ey: float = _h(ground_fn, ex, ez)
	ey = (top.y if is_nan(ey) else ey) + 0.1
	var foot: Vector3 = pts[0]
	var bx: float = foot.x - wd3.x * LadderPath.STAND_OFFSET
	var bz: float = foot.z - wd3.z * LadderPath.STAND_OFFSET
	var by: float = _h(ground_fn, bx, bz)
	by = (foot.y if is_nan(by) else by) + 0.1

	var flat := PackedFloat32Array()
	for p in pts:
		flat.append(p.x)
		flat.append(p.y)
		flat.append(p.z)
	var cost_n: int = maxi(1, ceili(length / METERS_PER_LADDER))
	var record: Dictionary = {
		"key": make_key(foot),
		"x": foot.x, "y": foot.y, "z": foot.z,
		"pts": flat,
		"dx": wall_dir.x, "dz": wall_dir.y,
		"ex": ex, "ey": ey, "ez": ez,
		"bx": bx, "by": by, "bz": bz,
		"len": length,
		"cost": cost_n,
	}
	return {"ok": true, "reason": "", "record": record, "cost": {LADDER_ITEM: cost_n}}

## Schlüssel einer Leiter aus ihrem Fußpunkt (auf 0,5 m gerundet): zwei Leitern am selben
## Fußpunkt gelten als Doppelbelegung.
static func make_key(foot: Vector3) -> String:
	return "L_%d_%d_%d" % [roundi(foot.x * 2.0), roundi(foot.y * 2.0), roundi(foot.z * 2.0)]

static func _h(fn: Callable, x: float, z: float) -> float:
	return float(fn.call(x, z))

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "record": {}, "cost": {}}
