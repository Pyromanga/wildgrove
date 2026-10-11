class_name TerrainEditLayer
extends RefCounted

## TerrainEditLayer — Spielerveränderungen am Gelände ("Umgraben"), als dünn besetzte
## Delta-Schicht ÜBER dem prozeduralen Basis-Terrain.
##
## WARUM EINE DELTA-SCHICHT: Das Basis-Terrain ist reine Funktion von (world_seed,
## Position) und wird auf jedem Peer identisch generiert (siehe TerrainField).
## Änderungen speichern wir deshalb NICHT als ganze Heightmaps, sondern nur als
## Abweichung pro Gitterpunkt. Speicher/Save wachsen mit der Anzahl geänderter Punkte,
## nicht mit der Weltgröße — und die Schicht ist eine kleine, klar abgegrenzte Menge
## an Daten, die sich später unverändert replizieren lässt (Koop-Ausbau).
##
## GITTER: Die Deltas liegen auf einem GLOBALEN Gitter mit SPACING Metern Abstand —
## bewusst identisch zum Vertex-Abstand der Chunk-Meshes (CHUNK_SIZE 64 m /
## Auflösung 32 = 2 m). Chunk-Zentren sind Vielfache von 64, Vertices liegen also
## exakt auf Gitterpunkten. Weil Nachbar-Chunks an ihrer Grenze dieselben globalen
## Gitterpunkte teilen, bleiben Chunk-Nähte auch nach Änderungen lückenlos.
##
## GRENZEN: Die Gesamtabweichung pro Punkt ist auf [MAX_DELTA_DOWN, MAX_DELTA_UP]
## begrenzt (kein Loch bis ins Nichts, kein Turm bis in den Himmel). Nach unten sind es
## 30 m — tief genug für richtige Schächte (Erze/Edelsteine, siehe DigFindTable); zurück nach
## oben kommt man ab ~4 m Tiefe nur noch über Leitern (LadderRegistry). Nach oben bleibt es
## bei 4 m: Aufschütten ist kein Bauen in die Höhe (dafür gibt es Bauteile).
##
## Reine Datenklasse: kein Node, kein Service, keine Engine-Abhängigkeit außer Vektoren.

const SPACING: float = 2.0
const MAX_DELTA_DOWN: float = -30.0
const MAX_DELTA_UP: float = 4.0
## Deltas werden auf dieses Raster gerundet (stabil für Save + spätere Replikation).
const QUANTUM: float = 0.05
## Deltas kleiner als dieser Betrag zählen als "nicht verändert" und werden entfernt.
const EPSILON: float = 0.02

## { Vector2i (Gitterindex): float (Höhenabweichung in m) }
var _deltas: Dictionary = {}

# ─────────────────────────────────────────────
# Abfragen
# ─────────────────────────────────────────────

func is_empty() -> bool:
	return _deltas.is_empty()

func get_edit_count() -> int:
	return _deltas.size()

func get_delta_lattice(ix: int, iz: int) -> float:
	return float(_deltas.get(Vector2i(ix, iz), 0.0))

## Höhenabweichung an beliebiger Weltposition (bilinear zwischen den 4 Gitterpunkten).
## Auf Gitterpunkten exakt der gespeicherte Wert.
func get_delta_at(world_x: float, world_z: float) -> float:
	if _deltas.is_empty():
		return 0.0
	var fx: float = world_x / SPACING
	var fz: float = world_z / SPACING
	var ix0: int = floori(fx)
	var iz0: int = floori(fz)
	var tx: float = fx - float(ix0)
	var tz: float = fz - float(iz0)
	var d00: float = get_delta_lattice(ix0,     iz0)
	var d10: float = get_delta_lattice(ix0 + 1, iz0)
	var d01: float = get_delta_lattice(ix0,     iz0 + 1)
	var d11: float = get_delta_lattice(ix0 + 1, iz0 + 1)
	return lerpf(lerpf(d00, d10, tx), lerpf(d01, d11, tx), tz)

# ─────────────────────────────────────────────
# Koordinaten-Helfer
# ─────────────────────────────────────────────

static func world_to_lattice(world_x: float, world_z: float) -> Vector2i:
	return Vector2i(roundi(world_x / SPACING), roundi(world_z / SPACING))

static func lattice_to_world(p: Vector2i) -> Vector2:
	return Vector2(float(p.x) * SPACING, float(p.y) * SPACING)

## Alle Gitterpunkte, deren Weltposition höchstens `radius` vom Zentrum entfernt ist.
static func lattice_points_in_radius(center_x: float, center_z: float, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if radius <= 0.0:
		return out
	var min_i: Vector2i = world_to_lattice(center_x - radius, center_z - radius)
	var max_i: Vector2i = world_to_lattice(center_x + radius, center_z + radius)
	for iz in range(min_i.y - 1, max_i.y + 2):
		for ix in range(min_i.x - 1, max_i.x + 2):
			var w: Vector2 = lattice_to_world(Vector2i(ix, iz))
			if Vector2(w.x - center_x, w.y - center_z).length() <= radius:
				out.append(Vector2i(ix, iz))
	return out

## Weiche Gewichtung: 1.0 im Zentrum, 0.0 am Rand (Kosinus-Verlauf).
##
## core_radius > 0 macht den Pinsel "flachbödig": bis core_radius bleibt das Gewicht 1.0
## (ebener Grubenboden), erst dahinter fällt es bis `radius` auf 0 ab. Ohne Kern (Default 0)
## ist es der reine Glockenverlauf — ein tiefes Loch würde dann zum Trichter, dessen Spitze
## man nicht mehr betreten kann. Mit Kern entsteht ein Schacht: ebener Boden, steile Wände.
static func falloff(dist: float, radius: float, core_radius: float = 0.0) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	if dist <= core_radius:
		return 1.0
	var t: float = (dist - core_radius) / (radius - core_radius)
	return 0.5 * (1.0 + cos(PI * t))

## Welche Chunks besitzen mindestens einen der Punkte als Vertex? Ein Chunk mit Zentrum c
## besitzt alle Vertices mit |x - c.x| <= chunk_size/2 und |z - c.y| <= chunk_size/2 —
## Punkte genau auf der Grenze gehören also zu bis zu vier Chunks.
static func chunks_for_points(points: Array[Vector2i], chunk_size: float) -> Array[Vector2i]:
	var seen: Dictionary = {}
	var half: float = chunk_size * 0.5
	for p in points:
		var w: Vector2 = lattice_to_world(p)
		var cx: int = roundi(w.x / chunk_size)
		var cz: int = roundi(w.y / chunk_size)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var coord := Vector2i(cx + dx, cz + dz)
				var center := Vector2(float(coord.x) * chunk_size, float(coord.y) * chunk_size)
				if absf(w.x - center.x) <= half and absf(w.y - center.y) <= half:
					seen[coord] = true
	var out: Array[Vector2i] = []
	for k in seen.keys():
		out.append(k)
	return out

# ─────────────────────────────────────────────
# Änderungen
# ─────────────────────────────────────────────

## Verschiebt EINEN Gitterpunkt um `amount` (mit Begrenzung). true, wenn sich der
## gespeicherte Wert dadurch tatsächlich geändert hat.
func add_delta(p: Vector2i, amount: float) -> bool:
	var old: float = float(_deltas.get(p, 0.0))
	return _store(p, old + amount, old)

## Setzt einen Gitterpunkt auf einen absoluten Delta-Wert (mit Begrenzung).
func set_delta(p: Vector2i, value: float) -> bool:
	var old: float = float(_deltas.get(p, 0.0))
	return _store(p, value, old)

## Pinsel: verschiebt alle Gitterpunkte im Radius um amount * falloff.
## amount < 0 gräbt, amount > 0 schüttet auf. Gibt die tatsächlich veränderten Punkte
## zurück (leer, wenn z.B. überall bereits das Limit erreicht ist).
## core_radius: siehe falloff() — Punkte innerhalb bekommen das volle Gewicht.
func apply_brush(center_x: float, center_z: float, radius: float, amount: float, core_radius: float = 0.0) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	for p in lattice_points_in_radius(center_x, center_z, radius):
		var w: Vector2 = lattice_to_world(p)
		var weight: float = falloff(Vector2(w.x - center_x, w.y - center_z).length(), radius, core_radius)
		if weight <= 0.0:
			continue
		if add_delta(p, amount * weight):
			changed.append(p)
	return changed

## Plant das Einebnen von Gitterpunkten auf die Zielhöhe `target_y` — OHNE etwas zu
## verändern (zweistufig, damit ein abgelehnter Plan keinen halben Zustand hinterlässt).
##
## ground_fn(world_x, world_z) -> float liefert die AKTUELLE Geländehöhe (inkl. bereits
## vorhandener Deltas, in der Praxis per Physik-Raycast). Die Basishöhe wird daher nicht
## separat gebraucht: neues Delta = altes Delta + (Ziel - aktuelle Höhe).
##
## Rückgabe: {ok: bool, reason: String, changes: {Vector2i: float (neues Delta)}}
##   reason: "" | "no_ground" (keine Höhe ermittelbar) | "too_steep" (Limit überschritten)
func plan_level(points: Array[Vector2i], target_y: float, ground_fn: Callable) -> Dictionary:
	var changes: Dictionary = {}
	for p in points:
		var w: Vector2 = lattice_to_world(p)
		var current: float = float(ground_fn.call(w.x, w.y))
		if is_nan(current):
			return {"ok": false, "reason": "no_ground", "changes": {}}
		var old: float = float(_deltas.get(p, 0.0))
		var wanted: float = old + (target_y - current)
		var clamped: float = clampf(wanted, MAX_DELTA_DOWN, MAX_DELTA_UP)
		if absf(clamped - wanted) > QUANTUM:
			return {"ok": false, "reason": "too_steep", "changes": {}}
		changes[p] = clamped
	return {"ok": true, "reason": "", "changes": changes}

## Wendet einen von plan_level() gelieferten Plan an. Gibt die veränderten Punkte zurück.
func apply_changes(changes: Dictionary) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	for p: Vector2i in changes.keys():
		if set_delta(p, float(changes[p])):
			changed.append(p)
	return changed

func clear() -> void:
	_deltas.clear()

# ─────────────────────────────────────────────
# Persistenz
# ─────────────────────────────────────────────

## Flaches Array [ix, iz, delta, ix, iz, delta, ...] — kompakt und mit var_to_str()
## speicherbar. (Ganzzahl-Indizes sind als float bis 2^24 exakt — weit über jede Weltgröße.)
func to_save() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: Vector2i in _deltas.keys():
		out.append(float(p.x))
		out.append(float(p.y))
		out.append(float(_deltas[p]))
	return out

## Lädt aus to_save()-Format (PackedFloat32Array oder Array). Ungültige/unvollständige
## Eingaben werden ignoriert statt zu crashen — ein kaputter Save darf die Welt nicht killen.
func load_save(raw: Variant) -> void:
	_deltas.clear()
	var values: Array = []
	if raw is PackedFloat32Array:
		for v in (raw as PackedFloat32Array):
			values.append(v)
	elif raw is Array:
		values = raw as Array
	else:
		return
	var i: int = 0
	while i + 2 < values.size():
		var v0: Variant = values[i]
		var v1: Variant = values[i + 1]
		var v2: Variant = values[i + 2]
		i += 3
		if not (v0 is float or v0 is int) or not (v1 is float or v1 is int) or not (v2 is float or v2 is int):
			continue
		set_delta(Vector2i(int(v0), int(v1)), float(v2))

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _store(p: Vector2i, wanted: float, old: float) -> bool:
	var value: float = snappedf(clampf(wanted, MAX_DELTA_DOWN, MAX_DELTA_UP), QUANTUM)
	if absf(value) < EPSILON:
		_deltas.erase(p)
		return absf(old) >= EPSILON
	_deltas[p] = value
	return not is_equal_approx(value, old)
