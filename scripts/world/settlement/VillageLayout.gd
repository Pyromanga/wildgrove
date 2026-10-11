class_name VillageLayout
extends RefCounted

## VillageLayout — plant EIN Dorf: Straßen, Grundstücke, Gebäudetypen, Wege.
##
## Idee (damit Strukturen "logisch verknüpft" sind):
##   1. Das Zentrum (Marktplatz mit Brunnen bzw. nur Brunnen im Weiler) liegt im Straßenknoten.
##   2. Jede ankommende Fernstraße ist zugleich Hauptstraße des Dorfs; dazu kommen Querstraßen
##      (Städte: zusätzliche Nebengassen).
##   3. Entlang ALLER Straßen entstehen Grundstücke, beidseitig, Front zur Straße.
##   4. Gebäudetypen folgen der Lage: Gasthaus/Kapelle/Handwerk nah am Zentrum, Höfe/Scheunen/
##      Ställe außen; Felder hinter Höfen; Friedhof neben der Kapelle; Mühle am Wasser;
##      Wachposten an den Ortseingängen.
##   5. Von jeder Haustür führt ein kurzer Pfad zur nächsten Straße.
##
## Rein deterministisch aus (Standort, ankommende Straßen, Basis-Gelände).
## Ergebnis: {buildings: Array[Dictionary], streets: Array[Dictionary], paths: Array[Dictionary]}
##   street/path: {a: Vector2, b: Vector2, w: float}
##   building: {id, type, x, z, yaw, y, spread, variant, site}

const STREET_W: float = 4.0
const CROSS_W: float = 3.2
const PATH_W: float = 1.5
const SETBACK: float = 1.6
const SAMPLE_STEP: float = 6.0
const PLAZA_CLEAR: float = 13.0
const OVERLAP_MARGIN: float = 1.2
const SLAB_RESERVE: float = 1.4

## Gebäudetypen, die eher außen liegen (Anteil des Radius), bzw. nur innen.
const OUTER_ONLY: Array[String] = [
	BuildingRecipes.T_FARMSTEAD, BuildingRecipes.T_BARN, BuildingRecipes.T_STABLE, BuildingRecipes.T_GRANARY,
	# Gerberei (Geruch), Salzsiederei (Feuer/Holz), Käserei (Weide) liegen am Ortsrand.
	BuildingRecipes.T_TANNERY, BuildingRecipes.T_SALTWORKS, BuildingRecipes.T_DAIRY,
]
const INNER_ONLY: Array[String] = [
	BuildingRecipes.T_TAVERN, BuildingRecipes.T_CHAPEL, BuildingRecipes.T_SMITHY, BuildingRecipes.T_BAKERY,
	BuildingRecipes.T_WORKSHOP, BuildingRecipes.T_HOUSE_LARGE,
	BuildingRecipes.T_GLASSWORKS, BuildingRecipes.T_SCRIPTORIUM, BuildingRecipes.T_BREWERY, BuildingRecipes.T_DYEHOUSE,
]
const MAX_SPREAD: Dictionary = {
	BuildingRecipes.T_MARKET: 1.8, BuildingRecipes.T_FIELD: 1.5, BuildingRecipes.T_CEMETERY: 1.5,
	BuildingRecipes.T_FARMSTEAD: 1.3,
}
const DEFAULT_MAX_SPREAD: float = 1.1

## Bauliste je Stufe (Reihenfolge = Wichtigkeit). Wird nacheinander auf Grundstücke gelegt.
const QUEUE_HAMLET: Array[String] = [
	BuildingRecipes.T_FARMSTEAD, BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_HOUSE_LONG,
	BuildingRecipes.T_BARN, BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_GRANARY, BuildingRecipes.T_HOUSE_SMALL,
]
const QUEUE_VILLAGE: Array[String] = [
	BuildingRecipes.T_TAVERN, BuildingRecipes.T_CHAPEL, BuildingRecipes.T_SMITHY, BuildingRecipes.T_HOUSE_LONG,
	BuildingRecipes.T_BAKERY, BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_HOUSE_LARGE, BuildingRecipes.T_FARMSTEAD,
	BuildingRecipes.T_WORKSHOP, BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_HOUSE_LONG, BuildingRecipes.T_BARN,
	BuildingRecipes.T_GRANARY, BuildingRecipes.T_STABLE, BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_HOUSE_SMALL,
	# Berufe (Dörfer): Töpferei, Weberei, Wagnerei, Käserei, Gerberei
	BuildingRecipes.T_POTTERY, BuildingRecipes.T_WEAVERY, BuildingRecipes.T_WHEELWRIGHT, BuildingRecipes.T_DAIRY,
	BuildingRecipes.T_TANNERY,
]
const QUEUE_TOWN: Array[String] = [
	BuildingRecipes.T_TAVERN, BuildingRecipes.T_CHAPEL, BuildingRecipes.T_SMITHY, BuildingRecipes.T_BAKERY,
	BuildingRecipes.T_HOUSE_LARGE, BuildingRecipes.T_WORKSHOP, BuildingRecipes.T_HOUSE_LONG, BuildingRecipes.T_HOUSE_LARGE,
	BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_HOUSE_LONG, BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_HOUSE_LARGE,
	BuildingRecipes.T_FARMSTEAD, BuildingRecipes.T_HOUSE_LONG, BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_STABLE,
	BuildingRecipes.T_BARN, BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_GRANARY, BuildingRecipes.T_FARMSTEAD,
	BuildingRecipes.T_HOUSE_SMALL, BuildingRecipes.T_GRANARY, BuildingRecipes.T_HOUSE_LONG, BuildingRecipes.T_HOUSE_SMALL,
	# Berufe (Städte): alle Handwerke, auch Brauhaus, Färberei, Glashütte, Schreibstube, Salzsiederei
	BuildingRecipes.T_BREWERY, BuildingRecipes.T_POTTERY, BuildingRecipes.T_DYEHOUSE, BuildingRecipes.T_WEAVERY,
	BuildingRecipes.T_GLASSWORKS, BuildingRecipes.T_SCRIPTORIUM, BuildingRecipes.T_WHEELWRIGHT, BuildingRecipes.T_TANNERY,
	BuildingRecipes.T_SALTWORKS, BuildingRecipes.T_DAIRY,
]

## `incoming`: Array[PackedVector2Array] — Fernstraßen, jeweils VOM Dorfzentrum nach außen.
static func plan(field: TerrainField, site: Dictionary, incoming: Array) -> Dictionary:
	var result: Dictionary = {"buildings": [], "streets": [], "paths": []}
	if bool(site.get("fixed", false)):
		return result   # Startdorf: handgebaut (WorldSpawner)
	var center: Vector2 = site["center"]
	var radius: float = site["radius"]
	var tier: String = site["tier"]
	var site_id: String = site["id"]
	var site_seed: int = site["seed"]
	var rng := RandomNumberGenerator.new()
	rng.seed = SettlementMath.mix(site_seed, 0, 0, 0xB17D)

	# ── 1. Achsen und Straßen ──
	var main_dir: Vector2 = Vector2.RIGHT.rotated(rng.randf() * TAU)
	if not incoming.is_empty():
		var first: PackedVector2Array = incoming[0]
		main_dir = direction_out(center, first)
	var cross_dir: Vector2 = Vector2(-main_dir.y, main_dir.x)
	var streets: Array = []
	for path: PackedVector2Array in incoming:
		append_clipped(streets, path, center, radius * 1.15, STREET_W)
	if incoming.is_empty():
		streets.append({"a": center - main_dir * radius * 0.85, "b": center, "w": STREET_W})
		streets.append({"a": center, "b": center + main_dir * radius * 0.85, "w": STREET_W})
	var cross_len: float = radius * (0.55 if tier == SettlementSites.TIER_HAMLET else 0.85)
	streets.append({"a": center - cross_dir * cross_len, "b": center, "w": CROSS_W})
	streets.append({"a": center, "b": center + cross_dir * cross_len, "w": CROSS_W})
	if tier == SettlementSites.TIER_TOWN:
		for off: float in [-0.5, 0.5]:
			var mid: Vector2 = center + main_dir * radius * off
			streets.append({"a": mid - cross_dir * radius * 0.7, "b": mid, "w": CROSS_W})
			streets.append({"a": mid, "b": mid + cross_dir * radius * 0.7, "w": CROSS_W})

	# ── 2. Grundstücks-Kandidaten entlang der Straßen ──
	var candidates: Array = []
	for s: Dictionary in streets:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var seg_len: float = a.distance_to(b)
		if seg_len < 1.0:
			continue
		var t: Vector2 = (b - a) / seg_len
		var nrm: Vector2 = Vector2(-t.y, t.x)
		var dist_along: float = rng.randf() * SAMPLE_STEP
		while dist_along <= seg_len:
			var p: Vector2 = a + t * dist_along
			var d_center: float = p.distance_to(center)
			if d_center >= PLAZA_CLEAR and d_center <= radius * 1.1:
				for side: float in [-1.0, 1.0]:
					candidates.append({"pos": p, "n": nrm * side, "w": float(s["w"]), "d": d_center, "key": d_center + rng.randf() * 6.0})
			dist_along += SAMPLE_STEP
	candidates.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["key"]) < float(q["key"]))

	# ── 3. Zentrum ──
	var placed: Array = []
	var center_type: String = BuildingRecipes.T_WELL if tier == SettlementSites.TIER_HAMLET else BuildingRecipes.T_MARKET
	var center_yaw: float = BuildingRecipes.facing_yaw(Vector2.ZERO, main_dir)
	var center_b: Dictionary = make_building(field, center_type, center, center_yaw, rng.randi(), site_id, site_seed, placed.size())
	if not center_b.is_empty():
		placed.append(center_b)

	# ── 4. Hauptbauliste ──
	var queue: Array[String] = QUEUE_VILLAGE
	if tier == SettlementSites.TIER_HAMLET:
		queue = QUEUE_HAMLET
	elif tier == SettlementSites.TIER_TOWN:
		queue = QUEUE_TOWN
	var used: Dictionary = {}
	for type_id: String in queue:
		var b: Dictionary = _place_on_candidates(field, type_id, candidates, used, placed, streets, center, radius, rng, site_id, site_seed)
		if not b.is_empty():
			placed.append(b)

	# ── 5. Sonderbauten ──
	if tier != SettlementSites.TIER_HAMLET:
		var mill: Dictionary = _place_waterside(field, BuildingRecipes.T_MILL, candidates, used, placed, streets, center, radius, rng, site_id, site_seed)
		if not mill.is_empty():
			placed.append(mill)
		# Fischerei: wie die Mühle nur an Wasser (Fluss/See/Küste in der Nähe).
		var fishery: Dictionary = _place_waterside(field, BuildingRecipes.T_FISHERY, candidates, used, placed, streets, center, radius, rng, site_id, site_seed)
		if not fishery.is_empty():
			placed.append(fishery)
	var chapel: Dictionary = _find_type(placed, BuildingRecipes.T_CHAPEL)
	if not chapel.is_empty():
		var cem: Dictionary = _place_beside(field, chapel, BuildingRecipes.T_CEMETERY, placed, rng, site_id, site_seed)
		if not cem.is_empty():
			placed.append(cem)
	var farms: Array = []
	for b: Dictionary in placed:
		if [BuildingRecipes.T_FARMSTEAD, BuildingRecipes.T_BARN, BuildingRecipes.T_STABLE].has(String(b["type"])):
			farms.append(b)
	for f: Dictionary in farms:
		var field_b: Dictionary = _place_behind(field, f, BuildingRecipes.T_FIELD, placed, rng, site_id, site_seed)
		if not field_b.is_empty():
			placed.append(field_b)
	var gate_type: String = BuildingRecipes.T_WAYCROSS if tier == SettlementSites.TIER_HAMLET else BuildingRecipes.T_WATCHPOST
	for path: PackedVector2Array in incoming:
		var gate: Dictionary = _place_gate(field, path, center, radius, gate_type, placed, rng, site_id, site_seed)
		if not gate.is_empty():
			placed.append(gate)

	# ── 6. Wege von den Türen zur Straße ──
	var paths: Array = []
	for b: Dictionary in placed:
		var t_id: String = b["type"]
		if [BuildingRecipes.T_MARKET, BuildingRecipes.T_WELL, BuildingRecipes.T_FIELD, BuildingRecipes.T_WAYCROSS, BuildingRecipes.T_WATCHPOST].has(t_id):
			continue
		var half: Vector2 = BuildingRecipes.half_extents(t_id)
		var bc := Vector2(float(b["x"]), float(b["z"]))
		var door: Vector2 = SettlementMath.local_to_world(bc, float(b["yaw"]), Vector2(0.0, half.y - 1.0))
		var target: Vector2 = closest_street_point(door, streets)
		if door.distance_to(target) > 0.5 and door.distance_to(target) < 14.0:
			paths.append({"a": door, "b": target, "w": PATH_W})

	result["buildings"] = placed
	result["streets"] = streets
	result["paths"] = paths
	return result

# ─────────────────────────────────────────────
# Straßen-Helfer
# ─────────────────────────────────────────────

## Richtung vom Zentrum nach außen entlang einer Straße (Punkt ~30 m entfernt).
static func direction_out(center: Vector2, path: PackedVector2Array) -> Vector2:
	for p: Vector2 in path:
		if p.distance_to(center) > 28.0:
			return (p - center).normalized()
	return (path[path.size() - 1] - center).normalized() if path.size() > 0 else Vector2.RIGHT

## Hängt die Teilstücke einer Fernstraße innerhalb von `max_dist` ans Straßen-Array.
static func append_clipped(out: Array, path: PackedVector2Array, center: Vector2, max_dist: float, w: float) -> void:
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		if a.distance_to(center) > max_dist and b.distance_to(center) > max_dist:
			break
		out.append({"a": a, "b": b, "w": w})

static func closest_street_point(p: Vector2, streets: Array) -> Vector2:
	var best: Vector2 = p
	var best_d: float = INF
	for s: Dictionary in streets:
		var q: Vector2 = SettlementMath.closest_on_segment(p, s["a"] as Vector2, s["b"] as Vector2)
		var d: float = p.distance_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best

# ─────────────────────────────────────────────
# Platzierung
# ─────────────────────────────────────────────

static func _place_on_candidates(
	field: TerrainField, type_id: String, candidates: Array, used: Dictionary, placed: Array,
	streets: Array, center: Vector2, radius: float, rng: RandomNumberGenerator, site_id: String, site_seed: int
) -> Dictionary:
	var half: Vector2 = BuildingRecipes.half_extents(type_id)
	for i in range(candidates.size()):
		if used.has(i):
			continue
		var c: Dictionary = candidates[i]
		var frac: float = float(c["d"]) / radius
		if OUTER_ONLY.has(type_id) and frac < 0.45:
			continue
		if INNER_ONLY.has(type_id) and frac > 0.8:
			continue
		var n: Vector2 = c["n"]
		var lot: Vector2 = (c["pos"] as Vector2) + n * (float(c["w"]) * 0.5 + SETBACK + half.y)
		if lot.distance_to(center) > radius * 1.25:
			continue
		var yaw: float = BuildingRecipes.facing_yaw(Vector2.ZERO, -n)
		if not fits(type_id, lot, yaw, placed, streets, true):
			continue
		var b: Dictionary = make_building(field, type_id, lot, yaw, rng.randi(), site_id, site_seed, placed.size())
		if b.is_empty():
			continue
		used[i] = true
		return b
	return {}

## Gebäude, das Wasser in der Nähe braucht (Mühle, Fischerei): erstes passendes Grundstück ab halbem Radius.
static func _place_waterside(
	field: TerrainField, type_id: String, candidates: Array, used: Dictionary, placed: Array, streets: Array,
	center: Vector2, radius: float, rng: RandomNumberGenerator, site_id: String, site_seed: int
) -> Dictionary:
	var half: Vector2 = BuildingRecipes.half_extents(type_id)
	var tested: int = 0
	for i in range(candidates.size()):
		if used.has(i):
			continue
		var c: Dictionary = candidates[i]
		if float(c["d"]) < radius * 0.5:
			continue
		tested += 1
		if tested > 24:
			break
		var n: Vector2 = c["n"]
		var lot: Vector2 = (c["pos"] as Vector2) + n * (float(c["w"]) * 0.5 + SETBACK + half.y)
		if not _water_near(field, lot, 32.0):
			continue
		var yaw: float = BuildingRecipes.facing_yaw(Vector2.ZERO, -n)
		if not fits(type_id, lot, yaw, placed, streets, true):
			continue
		var b: Dictionary = make_building(field, type_id, lot, yaw, rng.randi(), site_id, site_seed, placed.size())
		if not b.is_empty():
			used[i] = true
			return b
	return {}

static func _water_near(field: TerrainField, p: Vector2, r: float) -> bool:
	for k in range(8):
		var a: float = float(k) * TAU / 8.0
		var x: float = p.x + cos(a) * r
		var z: float = p.y + sin(a) * r
		if field.get_water_level_at(x, z) > field.get_base_height_at(x, z) - 0.2:
			return true
	return false

## Gebäude `type_id` neben `anchor` (links/rechts in dessen Koordinatensystem), gleiche Ausrichtung.
static func _place_beside(
	field: TerrainField, anchor: Dictionary, type_id: String, placed: Array,
	rng: RandomNumberGenerator, site_id: String, site_seed: int
) -> Dictionary:
	var a_half: Vector2 = BuildingRecipes.half_extents(String(anchor["type"]))
	var half: Vector2 = BuildingRecipes.half_extents(type_id)
	var yaw: float = float(anchor["yaw"])
	var ac := Vector2(float(anchor["x"]), float(anchor["z"]))
	for side: float in [1.0, -1.0]:
		var lot: Vector2 = SettlementMath.local_to_world(ac, yaw, Vector2(side * (a_half.x + half.x + 1.5), 0.0))
		if fits(type_id, lot, yaw, placed, [], false):
			var b: Dictionary = make_building(field, type_id, lot, yaw, rng.randi(), site_id, site_seed, placed.size())
			if not b.is_empty():
				return b
	return {}

## Gebäude hinter `anchor` (auf der straßenabgewandten Seite).
static func _place_behind(
	field: TerrainField, anchor: Dictionary, type_id: String, placed: Array,
	rng: RandomNumberGenerator, site_id: String, site_seed: int
) -> Dictionary:
	var a_half: Vector2 = BuildingRecipes.half_extents(String(anchor["type"]))
	var half: Vector2 = BuildingRecipes.half_extents(type_id)
	var yaw: float = float(anchor["yaw"])
	var ac := Vector2(float(anchor["x"]), float(anchor["z"]))
	var offsets: Array[Vector2] = [
		Vector2(0.0, -(a_half.y + half.y + 1.0)),
		Vector2(a_half.x + half.x + 1.0, -a_half.y + half.y),
		Vector2(-(a_half.x + half.x + 1.0), -a_half.y + half.y),
	]
	for off: Vector2 in offsets:
		var lot: Vector2 = SettlementMath.local_to_world(ac, yaw, off)
		if fits(type_id, lot, yaw, placed, [], false):
			var b: Dictionary = make_building(field, type_id, lot, yaw, rng.randi(), site_id, site_seed, placed.size())
			if not b.is_empty():
				return b
	return {}

## Wachposten/Wegkreuz am Ortseingang: seitlich der Fernstraße, Front zur Straße.
static func _place_gate(
	field: TerrainField, path: PackedVector2Array, center: Vector2, radius: float, type_id: String,
	placed: Array, rng: RandomNumberGenerator, site_id: String, site_seed: int
) -> Dictionary:
	var half: Vector2 = BuildingRecipes.half_extents(type_id)
	var target_d: float = radius * 1.08
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var da: float = a.distance_to(center)
		var db: float = b.distance_to(center)
		if da <= target_d and db >= target_d:
			var t: float = inverse_lerp(da, db, target_d) if db > da else 0.0
			var p: Vector2 = a.lerp(b, t)
			var dir: Vector2 = (b - a).normalized()
			var nrm: Vector2 = Vector2(-dir.y, dir.x)
			for side: float in [1.0, -1.0]:
				var lot: Vector2 = p + nrm * side * (STREET_W * 0.5 + 2.0 + half.y)
				var yaw: float = BuildingRecipes.facing_yaw(Vector2.ZERO, -nrm * side)
				if fits(type_id, lot, yaw, placed, [], false):
					var built: Dictionary = make_building(field, type_id, lot, yaw, rng.randi(), site_id, site_seed, placed.size())
					if not built.is_empty():
						return built
			return {}
	return {}

static func _find_type(placed: Array, type_id: String) -> Dictionary:
	for b: Dictionary in placed:
		if String(b["type"]) == type_id:
			return b
	return {}

## Passt das Grundstück (keine Überlappung, nicht auf einer Straße)?
static func fits(
	type_id: String, lot: Vector2, yaw: float, placed: Array, streets: Array, check_streets: bool
) -> bool:
	var half: Vector2 = BuildingRecipes.half_extents(type_id)
	for p: Dictionary in placed:
		var p_half: Vector2 = BuildingRecipes.half_extents(String(p["type"]))
		if SettlementMath.obb_overlap(lot, half, yaw, Vector2(float(p["x"]), float(p["z"])), p_half, float(p["yaw"]), OVERLAP_MARGIN):
			return false
	if check_streets:
		# Haus selbst (ohne Hof) darf keine Straße berühren: Eckpunkte + Kantenmitten des Grundstücks.
		var probe: Array[Vector2] = [
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y),
			Vector2(0.0, -half.y), Vector2(-half.x, 0.0), Vector2(half.x, 0.0),
		]
		for lp: Vector2 in probe:
			var wp: Vector2 = SettlementMath.local_to_world(lot, yaw, lp)
			for s: Dictionary in streets:
				if SettlementMath.dist_to_segment(wp, s["a"] as Vector2, s["b"] as Vector2) < float(s["w"]) * 0.5 + 0.6:
					return false
	return true

## Prüft das Gelände unter dem Grundstück und liefert das fertige Gebäude (oder {} wenn ungeeignet).
## Öffentlich: Prüft Gelände unter dem Grundstück, liefert Gebäude-Dictionary oder {}.
static func make_building(
	field: TerrainField, type_id: String, pos: Vector2, yaw: float, variant: int,
	site_id: String, site_seed: int, index: int
) -> Dictionary:
	var half: Vector2 = BuildingRecipes.half_extents(type_id)
	var samples: Array[Vector2] = [
		Vector2.ZERO, Vector2(-half.x, -half.y) * 0.8, Vector2(half.x, -half.y) * 0.8,
		Vector2(-half.x, half.y) * 0.8, Vector2(half.x, half.y) * 0.8,
	]
	var h_min: float = INF
	var h_max: float = -INF
	for lp: Vector2 in samples:
		var wp: Vector2 = SettlementMath.local_to_world(pos, yaw, lp)
		var h: float = field.get_base_height_at(wp.x, wp.y)
		if field.get_water_level_at(wp.x, wp.y) > h - 0.2:
			return {}
		h_min = minf(h_min, h)
		h_max = maxf(h_max, h)
	var spread: float = h_max - h_min
	var limit: float = float(BuildingRecipes.entry(type_id).get("max_spread", MAX_SPREAD.get(type_id, DEFAULT_MAX_SPREAD)))
	if spread > limit:
		return {}
	return {
		"id": SettlementMath.mix(site_seed, index, 3, 0xB0), "type": type_id, "x": pos.x, "z": pos.y,
		"yaw": yaw, "y": h_max, "spread": spread, "variant": absi(variant) % 1000, "site": site_id,
	}
