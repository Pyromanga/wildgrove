class_name RoadPaths
extends RefCounted

## RoadPaths — wählt Partner-Dörfer und legt den Verlauf einer Straße zwischen zwei Dörfern fest.
##
## Straßen sind Polylinien (Stützpunkt etwa alle STEP Meter), leicht geschwungen und um
## Wasser herum gelegt. Deterministisch aus (Seed, Endpunkte). Der Verlauf hängt NUR von den
## Basishöhen ab, nicht von Spieler-Änderungen.

const STEP: float = 18.0
const WOBBLE: float = 14.0
const MAX_LINK: float = 720.0
const WIDTH: float = 3.4

## Partner eines Dorfs: die 1–2 nächsten Nachbarn (aus den 3×3 Zellen um das Dorf).
## `others`: alle Standorte der Nachbarzellen (ohne das Dorf selbst).
static func pick_partners(site: Dictionary, others: Array) -> Array:
	var center: Vector2 = site["center"]
	var sorted: Array = others.duplicate()
	sorted.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		return center.distance_squared_to(p["center"] as Vector2) < center.distance_squared_to(q["center"] as Vector2))
	var result: Array = []
	if sorted.is_empty():
		return result
	var first: Dictionary = sorted[0]
	var d1: float = center.distance_to(first["center"] as Vector2)
	if d1 > MAX_LINK:
		return result
	result.append(first)
	if sorted.size() > 1:
		var second: Dictionary = sorted[1]
		var d2: float = center.distance_to(second["center"] as Vector2)
		if d2 <= d1 * 1.5 and d2 <= MAX_LINK:
			result.append(second)
	return result

## Schlüssel einer Kante, unabhängig von der Richtung.
static func edge_key(id_a: String, id_b: String) -> String:
	return id_a + "|" + id_b if id_a < id_b else id_b + "|" + id_a

## Verlauf von a nach b (inkl. beider Endpunkte). `key_hash` macht die Schwünge pro Kante einzigartig.
static func build_path(field: TerrainField, a: Vector2, b: Vector2, key_hash: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var length: float = a.distance_to(b)
	pts.append(a)
	if length < STEP * 1.5:
		pts.append(b)
		return pts
	var n: int = int(ceil(length / STEP))
	var dir: Vector2 = (b - a) / length
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var ph1: float = float(key_hash % 1000) / 1000.0 * TAU
	var ph2: float = float((key_hash >> 10) % 1000) / 1000.0 * TAU
	for i in range(1, n):
		var t: float = float(i) / float(n)
		var wobble: float = (sin(t * TAU * 1.3 + ph1) * 0.6 + sin(t * TAU * 3.1 + ph2) * 0.4) * WOBBLE * sin(PI * t)
		var p: Vector2 = a.lerp(b, t) + normal * wobble
		pts.append(_dodge_water(field, p, normal))
	pts.append(b)
	return pts

static func _wet(field: TerrainField, p: Vector2) -> bool:
	var h: float = field.get_base_height_at(p.x, p.y)
	return field.get_water_level_at(p.x, p.y) > h - 0.3

## Weicht seitlich aus, falls p im Wasser liegt (sonst Furt: unverändert).
static func _dodge_water(field: TerrainField, p: Vector2, normal: Vector2) -> Vector2:
	if not _wet(field, p):
		return p
	for k in range(1, 7):
		for sgn: float in [1.0, -1.0]:
			var q: Vector2 = p + normal * sgn * float(k) * 10.0
			if not _wet(field, q):
				return q
	return p
