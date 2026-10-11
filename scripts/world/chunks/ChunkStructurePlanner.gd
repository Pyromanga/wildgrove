class_name ChunkStructurePlanner
extends RefCounted

## ChunkStructurePlanner — entscheidet pro Chunk, OB und WO ein zufälliges Gebäude steht.
##
## Wunsch (2026-10-05): "Gebäude, die randomly spawnen, mit NPCs". BiomeDefinition.structure_types
## ("cottage", "well", "barn", "ruin") war bisher reine Daten-Deko ohne Konsumenten.
##
## REIN DETERMINISTISCH und frei von Nodes: gleicher (world_seed, coord) → exakt derselbe Plan,
## auf jedem Peer, bei jedem erneuten Laden des Chunks. Kein Netzwerk-Sync und kein Eintrag im
## Save nötig (dieselbe Strategie wie ChunkEntitySpawner für Bäume/Tiere). Der Plan ist ein
## Dictionary, damit Spawner (NPCs), Builder (Geometrie) und Vegetation (Freihaltezone) ihn
## teilen können, ohne voneinander zu wissen.
##
## Eigener RNG-Strom (SEED_SALT): eine spätere Änderung an der Prop-Logik verschiebt die
## Gebäude NICHT, und umgekehrt.
##
## Plan-Schlüssel:
##   type       String   "cottage" | "barn" | "well" | "ruin"
##   x, z       float    Weltposition des Gebäude-Mittelpunkts
##   base_y     float    Höhe der Bodenplatten-OBERKANTE (= höchster Geländepunkt der Fläche)
##   spread     float    Höhenunterschied des Geländes unter der Fläche (bestimmt Fundamenttiefe)
##   yaw_steps  int      0..3 — Drehung um die Hochachse in 90°-Schritten
##   half_x/z   float    halbe Kantenlänge der Fläche (lokal, vor der Drehung)
##   radius     float    Freihaltezone für Bäume/Tiere/Gras (Weltmeter um x,z)
##   seed       int      Seed für Variationen im Builder (Farben, Ruinen-Lücken)

const LOG_CAT := "ChunkStructurePlanner"

## Wahrscheinlichkeit pro Chunk (nur Biome mit nicht-leeren structure_types).
## 0.16 ≈ ein Gebäude alle ~6 Chunks, im 9×9-Ladebereich also rund ein Dutzend.
const CHUNK_CHANCE: float = 0.16
const MAX_SITE_ATTEMPTS: int = 8
## Größter erlaubter Höhenunterschied unter der Fläche. Die Platte endet auf dem HÖCHSTEN
## Punkt, an der tiefsten Stelle steht man also bis zu spread + SLAB_TOP davor — 0.45 + 0.12
## bleibt mit JUMP_VELOCITY 6.0 jederzeit überspringbar, auch ohne Stufen-Logik im Spieler.
const MAX_HEIGHT_SPREAD: float = 0.45
## Mindesthöhe des tiefsten Flächenpunkts über dem Wasser (kein Haus im Uferschlamm).
const WATER_CLEARANCE: float = 0.7
## Oberkante der Bodenplatte über base_y (Konstante gehört dem Builder, hier nur gespiegelt
## für Tests — siehe ChunkStructureBuilder.SLAB_TOP).
## Abstand zum Chunk-Rand = ENTITY_MARGIN (6.0, ChunkEntitySpawner) + 1: Bäume des Nachbar-
## chunks halten selbst 6 m Abstand zu IHRER Kante, so bleibt zwischen Gebäude und fremden
## Bäumen immer mindestens 1 m Luft, obwohl der Nachbar nichts von diesem Gebäude weiß.
const EDGE_MARGIN: float = 7.0
## Zusätzlicher Sperrring um die Spawn-Plateau-Fläche (spawn_blend_radius aus TerrainConfig):
## Dorf, Handelsstraße und Farmbeete liegen dort, Gebäude dürfen sie nicht überdecken.
const SPAWN_EXCLUSION_EXTRA: float = 40.0
const SEED_SALT: int = 0x57A1C7

## type → {half: Vector2 (halbe Fläche inkl. Vorplatz), radius: float (Freihaltezone)}.
## Geometrie/NPC-Plätze zu jedem Typ: ChunkStructureBuilder.
const TYPES: Dictionary = {
	"cottage": {"half": Vector2(3.5, 4.0), "radius": 7.0},
	"barn":    {"half": Vector2(5.0, 5.5), "radius": 8.5},
	"well":    {"half": Vector2(2.2, 2.2), "radius": 4.5},
	"ruin":    {"half": Vector2(4.0, 4.0), "radius": 6.5},
}

## Plant ein Gebäude für `coord`. Leeres Dictionary = in diesem Chunk steht keins.
static func plan(
	coord: Vector2i, center: Vector2, gen: TerrainField, base_seed: int, chunk_size: float
) -> Dictionary:
	if gen == null:
		return {}
	var biome: BiomeDefinition = gen.get_biome_at(center.x, center.y)
	if not is_instance_valid(biome) or biome.structure_types.is_empty():
		return {}

	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed ^ (coord.x * 2654435) ^ (coord.y * 40503) ^ SEED_SALT
	if rng.randf() >= CHUNK_CHANCE:
		return {}

	var usable: Array[String] = []
	for type_id: String in biome.structure_types:
		if TYPES.has(type_id):
			usable.append(type_id)
	if usable.is_empty():
		return {}
	var type_id: String = usable[rng.randi_range(0, usable.size() - 1)]
	var spec: Dictionary = TYPES[type_id]
	var half: Vector2 = spec["half"]
	var radius: float = spec["radius"]

	var limit: float = chunk_size * 0.5 - EDGE_MARGIN - radius
	if limit <= 0.0:
		return {}

	var cfg: TerrainConfig = gen.get_config()
	var spawn_ring: float = (cfg.spawn_blend_radius if cfg != null else 90.0) + SPAWN_EXCLUSION_EXTRA

	for _attempt in range(MAX_SITE_ATTEMPTS):
		var wx: float = center.x + rng.randf_range(-limit, limit)
		var wz: float = center.y + rng.randf_range(-limit, limit)
		var yaw_steps: int = rng.randi_range(0, 3)
		if Vector2(wx, wz).length() < spawn_ring:
			continue
		# Dörfer, Straßen und Dorfgrundstücke haben Vorrang vor Zufalls-Einzelgebäuden: die
		# Siedlungsplanung (SettlementRegistry) legt dort selbst logisch verknüpfte Gebäude hin.
		if _collides_with_settlement(gen, wx, wz, radius):
			continue
		var site: Dictionary = evaluate_site(gen, wx, wz, yaw_steps, half)
		if site.is_empty():
			continue
		return {
			"type": type_id,
			"x": wx, "z": wz,
			"base_y": site["base_y"],
			"spread": site["spread"],
			"yaw_steps": yaw_steps,
			"half_x": half.x, "half_z": half.y,
			"radius": radius,
			"seed": rng.randi(),
		}
	return {}

## true, wenn ein Einzelgebäude mit Umkreis `radius` an (wx, wz) in ein Dorf, auf eine Straße
## oder auf ein Siedlungsgrundstück fiele.
static func _collides_with_settlement(gen: TerrainField, wx: float, wz: float, radius: float) -> bool:
	var reg: SettlementRegistry = gen.get_settlements()
	if not reg.village_at(wx, wz, radius + 12.0).is_empty():
		return true
	for k in range(5):
		var ox: float = 0.0 if k == 0 else (radius if k % 2 == 1 else -radius)
		var oz: float = 0.0 if k < 3 else (radius if k == 3 else -radius)
		if reg.blocks_vegetation(wx + ox, wz + oz, 3.0):
			return true
	return false

## Prüft eine Fläche (9 Stichproben: Ecken, Kantenmitten, Mitte — gedreht um yaw_steps·90°).
## Leer = ungeeignet (Wasser/zu uneben). Sonst {base_y, spread}.
static func evaluate_site(
	gen: TerrainField, wx: float, wz: float, yaw_steps: int, half: Vector2
) -> Dictionary:
	var yaw: float = float(yaw_steps) * PI * 0.5
	var lo: float = INF
	var hi: float = -INF
	for ix in range(-1, 2):
		for iz in range(-1, 2):
			var local := Vector3(float(ix) * half.x, 0.0, float(iz) * half.y)
			var p: Vector3 = local.rotated(Vector3.UP, yaw)
			var sx: float = wx + p.x
			var sz: float = wz + p.z
			var h: float = gen.get_height_at(sx, sz)
			if h < gen.get_water_level_at(sx, sz) + WATER_CLEARANCE:
				return {}
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var spread: float = hi - lo
	if spread > MAX_HEIGHT_SPREAD:
		return {}
	return {"base_y": hi, "spread": spread}

## Weltposition eines lokalen Gebäudepunkts (lx, lz) — gleiche Drehung wie
## Node3D.rotation.y = yaw_steps · 90° im Builder.
static func local_to_world(plan: Dictionary, lx: float, lz: float) -> Vector2:
	var yaw: float = float(int(plan["yaw_steps"])) * PI * 0.5
	var p: Vector3 = Vector3(lx, 0.0, lz).rotated(Vector3.UP, yaw)
	return Vector2(float(plan["x"]) + p.x, float(plan["z"]) + p.z)
