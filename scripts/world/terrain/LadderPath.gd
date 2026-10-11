class_name LadderPath
extends RefCounted

## LadderPath — die Geometrie EINER Leiter als Linienzug (Polyline), abgeleitet aus dem
## gespeicherten Record (siehe LadderRegistry). Reine Rechenklasse: kein Node, kein Zustand.
##
## WARUM EIN LINIENZUG STATT EINER GERADEN: Das Gelände ist ein Höhenfeld; eine Grubenwand ist
## nie exakt senkrecht und meist leicht gekrümmt. Eine gerade Sehne zwischen Fuß und Rand
## würde dort in der Erde verschwinden (Wand ragt in die Sehne hinein) oder frei davor
## schweben. Der Linienzug folgt dem Boden Punkt für Punkt (siehe LadderPlanner) und liegt
## dabei WALL_CLEARANCE vor der Wand in der Luft.
##
## BEGRIFFE
##   s         Bogenlänge entlang der Leiter in Metern: 0 = Fuß (unten), length = Kopf (oben).
##   wall_dir  waagerechte Einheitsrichtung ZUR Wand hin. Wer "zur Wand" läuft, klettert
##             hinauf, wer davon weg läuft, klettert hinab (siehe PlayerLadder).
##   Standpunkt  Position des Spielers auf der Leiter: STAND_OFFSET vor der Leiterlinie
##             (so steckt der Körper nicht in der Wand).
##
## Ist ein Spieler auf der Leiter, wird er DIREKT auf den Standpunkt gesetzt (keine
## Kollision) — deshalb darf die Linie ein paar Zentimeter im Boden liegen, ohne dass man
## hängen bleibt. An Ein-/Ausstiegen wird dagegen immer ein echter, begehbarer Punkt gewählt.

## Abstand der Leiterlinie zur Bodenoberfläche (waagerecht, zur Grube hin).
const WALL_CLEARANCE: float = 0.35
## Abstand Spieler ↔ Leiterlinie (waagerecht, weiter zur Grube hin).
const STAND_OFFSET: float = 0.35

var key: String = ""
## Leiterlinie, von unten (Fuß) nach oben (Kopf).
var points: PackedVector3Array = PackedVector3Array()
## Standpunkte des Spielers, Punkt für Punkt zu `points` gehörig.
var stand_points: PackedVector3Array = PackedVector3Array()
## Kumulierte Bogenlänge je Punkt (cum[0] = 0).
var cum: PackedFloat32Array = PackedFloat32Array()
var length: float = 0.0
var wall_dir: Vector3 = Vector3.FORWARD
## Begehbarer Punkt oben (auf dem Rand, hinter dem Kopf) und unten (auf dem Boden, vor dem Fuß).
var exit_top: Vector3 = Vector3.ZERO
var exit_bottom: Vector3 = Vector3.ZERO
var bounds: AABB = AABB()

## Baut den Pfad aus einem Record. null bei ungültigen/unvollständigen Daten (ein kaputter
## Spielstand darf die Welt nicht killen).
static func from_record(rec: Dictionary) -> LadderPath:
	var raw: Variant = rec.get("pts", null)
	var flat: Array = []
	if raw is PackedFloat32Array:
		for v in (raw as PackedFloat32Array):
			flat.append(v)
	elif raw is Array:
		flat = raw as Array
	else:
		return null
	if flat.size() < 6 or flat.size() % 3 != 0:
		return null
	var path := LadderPath.new()
	path.key = String(rec.get("key", ""))
	var dx: float = float(rec.get("dx", 0.0))
	var dz: float = float(rec.get("dz", 0.0))
	var dir := Vector3(dx, 0.0, dz)
	if dir.length_squared() < 0.0001:
		return null
	path.wall_dir = dir.normalized()
	var acc: float = 0.0
	var i: int = 0
	while i + 2 < flat.size():
		var p := Vector3(float(flat[i]), float(flat[i + 1]), float(flat[i + 2]))
		if not path.points.is_empty():
			acc += path.points[path.points.size() - 1].distance_to(p)
		path.points.append(p)
		path.stand_points.append(p - path.wall_dir * STAND_OFFSET)
		path.cum.append(acc)
		i += 3
	path.length = acc
	if path.length <= 0.01:
		return null
	path.exit_top = Vector3(float(rec.get("ex", 0.0)), float(rec.get("ey", 0.0)), float(rec.get("ez", 0.0)))
	path.exit_bottom = Vector3(float(rec.get("bx", 0.0)), float(rec.get("by", 0.0)), float(rec.get("bz", 0.0)))
	var box := AABB(path.stand_points[0], Vector3.ZERO)
	for p in path.points:
		box = box.expand(p)
	for p in path.stand_points:
		box = box.expand(p)
	path.bounds = box
	return path

## Punkt auf der Leiterlinie bei Bogenlänge s (s wird auf [0, length] begrenzt).
func point_at(s: float) -> Vector3:
	return _lerp_along(points, s)

## Standpunkt des Spielers bei Bogenlänge s.
func stand_point(s: float) -> Vector3:
	return _lerp_along(stand_points, s)

## Nächster Punkt der STAND-Linie zu `pos`. Rückgabe: {s: float, dist: float}.
func nearest(pos: Vector3) -> Dictionary:
	var best_s: float = 0.0
	var best_d: float = INF
	for i in range(stand_points.size() - 1):
		var a: Vector3 = stand_points[i]
		var b: Vector3 = stand_points[i + 1]
		var ab: Vector3 = b - a
		var seg_len2: float = ab.length_squared()
		var t: float = 0.0
		if seg_len2 > 0.000001:
			t = clampf((pos - a).dot(ab) / seg_len2, 0.0, 1.0)
		var d: float = pos.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_s = cum[i] + t * sqrt(seg_len2)
	return {"s": best_s, "dist": best_d}

func _lerp_along(arr: PackedVector3Array, s: float) -> Vector3:
	if s <= 0.0:
		return arr[0]
	if s >= length:
		return arr[arr.size() - 1]
	for i in range(cum.size() - 1):
		if s <= cum[i + 1]:
			var seg: float = cum[i + 1] - cum[i]
			var t: float = 0.0 if seg <= 0.000001 else (s - cum[i]) / seg
			return arr[i].lerp(arr[i + 1], t)
	return arr[arr.size() - 1]
