class_name SettlementSites
extends RefCounted

## SettlementSites — wo liegen Dörfer? Reine, deterministische Standortwahl.
##
## Die Welt wird in Makro-Zellen (CELL Meter) geteilt. Jede Zelle hat per Hash-Wurf höchstens
## EIN Dorf (Weiler / Dorf / Stadt). Der Standort ist der flachste, trockene Kandidat der Zelle.
## Nur Gelände-Basishöhe (ohne Spieler-Änderungen!) wird benutzt, damit alle Peers dieselben
## Dörfer sehen, auch wenn jemand gegraben hat.
##
## Das hier ist billig (wenige Dutzend Höhenabfragen) und liefert nur den Standort —
## das teure Layout (Gebäude, Straßen) kommt erst bei Bedarf (VillageLayout).

const CELL: float = 448.0
const MARGIN: float = 100.0          ## Mindestabstand des Zentrums zum Zellrand (Dorf bleibt in der Zelle)
const VILLAGE_CHANCE: float = 0.75
const CANDIDATES: int = 8
const MAX_SITE_SPREAD: float = 4.5   ## max. Höhenunterschied im Dorfradius
const MIN_ALLOWED_FRACTION: float = 0.75   ## Anteil der Probepunkte in erlaubten Biomen
const SPAWN_EXCLUSION: float = 230.0

const TIER_HAMLET := "hamlet"
const TIER_VILLAGE := "village"
const TIER_TOWN := "town"

const TIER_LABEL: Dictionary = {TIER_HAMLET: "Weiler", TIER_VILLAGE: "Dorf", TIER_TOWN: "Stadt"}
const TIER_RADIUS: Dictionary = {TIER_HAMLET: 38.0, TIER_VILLAGE: 58.0, TIER_TOWN: 80.0}

## Biome, in denen gesiedelt wird.
const ALLOWED_BIOMES: Array[String] = ["meadow", "forest", "winter"]

## Das handgebaute Startdorf (WorldSpawner). Fester Knoten im Straßennetz, ohne generierte Häuser.
const SPAWN_CENTER := Vector2(12.0, 0.0)
const SPAWN_NAME := "Hainau"
const SPAWN_RADIUS: float = 44.0

static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))

static func site_id(cell: Vector2i) -> String:
	return "s_%d_%d" % [cell.x, cell.y]

## Standort der Zelle als Dictionary oder {} (kein Dorf).
## {id, cell, center: Vector2, tier, radius, kind, name, seed, fixed}
static func find_site(field: TerrainField, world_seed: int, cell: Vector2i) -> Dictionary:
	if cell == cell_of(SPAWN_CENTER.x, SPAWN_CENTER.y):
		return {
			"id": site_id(cell), "cell": cell, "center": SPAWN_CENTER, "tier": TIER_VILLAGE,
			"radius": SPAWN_RADIUS, "name": SPAWN_NAME, "kind": VillageKinds.KIND_GROUND,
			"seed": SettlementMath.mix(world_seed, cell.x, cell.y, 1), "fixed": true,
		}
	var rng: RandomNumberGenerator = SettlementMath.rng_for(world_seed, cell.x, cell.y, 0x51AE)
	var chance_roll: float = rng.randf()
	var tier_roll: float = rng.randf()
	# Alle Zufallswerte VOR dem Auswerten ziehen → Ergebnis hängt nicht vom Gelände-Pfad ab.
	var candidates: Array[Vector2] = []
	for i in range(CANDIDATES):
		candidates.append(Vector2(
			float(cell.x) * CELL + MARGIN + rng.randf() * (CELL - 2.0 * MARGIN),
			float(cell.y) * CELL + MARGIN + rng.randf() * (CELL - 2.0 * MARGIN)))
	# Bewusst NACH den Kandidaten gezogen: bestehende Welten behalten so Standorte und Größen.
	var kind_roll: float = rng.randf()
	if chance_roll >= VILLAGE_CHANCE:
		return {}
	var tier: String = TIER_HAMLET
	if tier_roll >= 0.85:
		tier = TIER_TOWN
	elif tier_roll >= 0.45:
		tier = TIER_VILLAGE
	# Sonderart zuerst (falls der Würfel sie vorsieht), sonst/ersatzweise das Bodendorf.
	for kind_id: String in VillageKinds.ids_for_roll(kind_roll):
		var kind: VillageKind = VillageKinds.get_kind(kind_id)
		var radius: float = kind.tier_radius(tier)
		var best: Vector2 = Vector2.ZERO
		var best_score: float = INF
		for p: Vector2 in candidates:
			if p.distance_to(SPAWN_CENTER) < SPAWN_EXCLUSION:
				continue
			var score: float = kind.site_score(field, p, radius)
			if score >= 0.0 and score < best_score:
				best_score = score
				best = p
		if best_score == INF:
			continue
		return {
			"id": site_id(cell), "cell": cell, "center": best, "tier": tier, "radius": radius, "kind": kind_id,
			"name": VillageNames.name_for(SettlementMath.mix(world_seed, cell.x, cell.y, 77), kind_id),
			"seed": SettlementMath.mix(world_seed, cell.x, cell.y, 2), "fixed": false,
		}
	return {}

## Eignung eines Punktes: Höhenspreizung (klein = gut) oder -1 (ungeeignet). Wiederverwendbar für
## jede Dorf-Art: `allowed` = erlaubte Biome, `min_fraction` = Mindestanteil der Probepunkte darin,
## `max_spread` = größter Höhenunterschied im Radius. Wasser im Radius → ungeeignet.
static func score_site(
	field: TerrainField, p: Vector2, radius: float, allowed: Array, min_fraction: float, max_spread: float
) -> float:
	if not _dry_and_allowed(field, p.x, p.y, allowed):
		return -1.0
	var h0: float = field.get_base_height_at(p.x, p.y)
	var h_min: float = h0
	var h_max: float = h0
	var allowed_n: int = 1
	var total: int = 1
	for ring: float in [radius * 0.55, radius]:
		for k in range(8):
			var a: float = float(k) * TAU / 8.0
			var x: float = p.x + cos(a) * ring
			var z: float = p.y + sin(a) * ring
			var h: float = field.get_base_height_at(x, z)
			if field.get_water_level_at(x, z) > h - 0.4:
				return -1.0
			total += 1
			if allowed.has(field.get_biome_id_at(x, z)):
				allowed_n += 1
			h_min = minf(h_min, h)
			h_max = maxf(h_max, h)
	if float(allowed_n) / float(total) < min_fraction:
		return -1.0
	var spread: float = h_max - h_min
	if spread > max_spread:
		return -1.0
	return spread

static func _dry_and_allowed(field: TerrainField, x: float, z: float, allowed: Array) -> bool:
	var h: float = field.get_base_height_at(x, z)
	if field.get_water_level_at(x, z) > h - 0.4:
		return false
	return allowed.has(field.get_biome_id_at(x, z))
