class_name ChunkEntitySpawner
extends RefCounted

## ChunkEntitySpawner — Spawnt Props/Tiere/Gegner für einen Chunk.
##
## Extrahiert aus ChunkManager._spawn_chunk_entities().
## Deterministisch über (chunk_seed ^ coord): gleicher Seed → gleiche Entities.
##
## Spawn-Callable wird per DI injiziert (_init-Parameter) — kein direkter
## Service-Zugriff. Konsistent mit dem übrigen DI-Modell des Projekts.
##
## Round 75: Props/Gegner werden jetzt tatsächlich über BiomeDefinition.
## prop_chances/enemy_chances des Chunks gewählt (vorher: hartcodiert
## "oak_tree"). Biom wird EINMAL pro Chunk am Chunk-Zentrum gesampelt (nicht
## pro Prop) — bei der aktuellen Biom-Noise-Wellenlänge (~285m, BIOME_FREQ
## 0.0035) liegt ein 64m-Chunk nur selten auf einer Biom-Grenze; exaktere
## Pro-Prop-Sampling wäre möglich, aber 3-4× mehr Noise-Aufrufe pro Chunk für
## einen in der Praxis seltenen Randfall — bewusst nicht gemacht, siehe
## TODO-offene-probleme.md falls das mal zum echten Problem wird (sichtbare
## "Biom-Kante mitten im Chunk" mit falscher Vegetation).

const LOG_CAT      := "ChunkEntitySpawner"
const ENTITY_MARGIN := 6.0  # Abstand zum Chunk-Rand
## Mindesthöhe ÜBER dem Wasserspiegel, ab der etwas spawnt (Uferstreifen bleibt frei —
## keine Bäume im Wasser, keine Tiere am Beckenrand).
const SHORE_MARGIN := 0.3
## Welche Tierarten per Zufall in _spawn_animal() ausgewählt werden. War ursprünglich ein
## hardcodiertes `types[rng.randi_range(0, 2)]` mit fest "2" als oberer Grenze — jede neue
## Tierart hätte das stillschweigend NIE spawnen lassen. _spawn_animal() liest die obere
## Grenze seitdem aus der Array-Größe ab (siehe _all_land_animal_types() unten).
## Die zehn handgeschriebenen Arten (siehe WorldEntityRegistry-Kommentar) — bleiben als
## fester Grundstock bestehen, MUSS synchron mit deren "animals"-Einträgen in
## WorldEntityRegistry.register_all() gehalten werden (dieselbe Konvention wie
## WorldEntityRegistry.KNOWN_PROP_TYPES/KNOWN_ENEMY_TYPES).
const CURATED_LAND_ANIMAL_TYPES: Array[String] = ["deer", "rabbit", "boar", "fox", "squirrel", "sheep", "bee", "spider", "snake", "bear"]
const CURATED_FISH_TYPES: Array[String] = ["fish"]

## Wunsch "nachhaltig über ein Skript lösen, massiv viele Tiere hinzufügen": NICHT mehr als
## `const`, weil AnimalSpeciesDB.land_species_ids()/aquatic_species_ids() zur Laufzeit
## ausgewertet werden (GDScript-`const` erlaubt keine Funktionsaufrufe im Initializer) — neue
## Arten aus AnimalSpeciesDB landen dadurch automatisch hier, ohne dass diese Datei je wieder
## angefasst werden muss. Keine Caching-Optimierung nötig: Chunk-Erzeugung ist kein Hot-Path
## (einmal pro neu geladenem Chunk, nicht pro Frame).
static func _all_land_animal_types() -> Array[String]:
	var result := CURATED_LAND_ANIMAL_TYPES.duplicate()
	result.append_array(AnimalSpeciesDB.land_species_ids())
	return result

static func _all_fish_types() -> Array[String]:
	var result := CURATED_FISH_TYPES.duplicate()
	result.append_array(AnimalSpeciesDB.aquatic_species_ids())
	return result

## Wahrscheinlichkeit pro Chunk, dass EIN Fisch spawnt, analog zum "jeder dritte Chunk"-Takt
## bei _spawn_animal() — bewusst kein fixer Modulo-Takt wie dort (Wasserflächen sind ohnehin
## schon seltener als Land, ein zusätzlicher harter Chunk-Filter würde Fische praktisch nie
## sichtbar machen), siehe _spawn_fish().
const FISH_CHANCE := 0.35

## ── DICHTE (2026-10-05, "viel zu wenig Bäume") ───────────────────────────
## Globaler Regler für die Zahl der Prop-Versuche pro Chunk (BiomeDefinition.prop_attempts_*).
## 1.0 = Biom-Werte unverändert; auf schwachen Geräten ZUERST hier senken (z. B. 0.6).
const PROP_DENSITY_MULT: float = 1.0
## Fallback, wenn ein Biom keine eigenen prop_attempts_* hat (0/0).
const DEFAULT_ATTEMPTS_MIN: int = 8
const DEFAULT_ATTEMPTS_MAX: int = 16
## Hainbildung: 2-4 Zentren pro Chunk, GROVE_SHARE der Versuche landet normalverteilt (σ =
## GROVE_SPREAD m) darum, der Rest gleichverteilt. Ergibt Wäldchen und Lichtungen statt Raster.
const GROVE_SHARE: float = 0.6
const GROVE_SPREAD: float = 9.0
## Mindestabstand zwischen zwei Props im selben Chunk = Summe ihrer Radien (keine ineinander
## wachsenden Stämme). Bäume sind seit der Größen-Überarbeitung (2026-10-07) 7-14 m hohe Objekte
## mit mehreren Metern Krone; Wunsch 2026-10-08 "in Wäldern Bäume richtig dicht an dicht": nur
## 3 m Mindestabstand zwischen Stämmen (Kronen überlappen → geschlossenes Blätterdach).
const PROP_RADIUS_SMALL: float = 0.8
const PROP_RADIUS_TREE: float = 1.5
const TREE_PROP_TYPES: Array[String] = ["oak_tree", "maple_tree", "willow_tree", "pine_tree"]

var _chunk_size:   float
var _base_seed:    int
var _spawn_entity: Callable
## Optional: func(type_id: String, pos: Vector3) -> bool — bereits abgeerntete Objekte (Bäume,
## Erze) entstehen beim erneuten Laden des Chunks nicht wieder (WorldData.harvested_objects).
var _is_harvested: Callable

## { Vector2i: Array[Node3D] } — was dieser Spawner pro Chunk erzeugt hat. Ohne diese Buchführung
## blieben Bäume/Tiere eines entladenen Chunks für immer in der Welt (schwebend) und würden beim
## Zurückkehren doppelt entstehen.
var _spawned: Dictionary = {}
var _bucket: Array[Node3D] = []

## { Vector2i: Array[Vector3] } — Freihaltezonen (x = Welt-X, y = Welt-Z, z = Radius), aktuell die
## Gebäude des Chunks. Props/Tiere/Gegner weichen aus, ChunkVegetationBuilder liest sie über
## get_clear_zones().
var _clear_zones: Dictionary = {}
## Während spawn_for_chunk(): Zonen des gerade bearbeiteten Chunks.
var _active_zones: Array[Vector3] = []
## Dörfer/Straßen der Welt (TerrainField.get_settlements()); Props/Tiere/Gegner weichen ihnen aus.
var _settlements: SettlementRegistry = null

func _init(
	chunk_size: float, base_seed: int, spawn_entity_cb: Callable,
	is_harvested_cb: Callable = Callable()
) -> void:
	_chunk_size   = chunk_size
	_base_seed    = base_seed
	_spawn_entity = spawn_entity_cb
	_is_harvested = is_harvested_cb

## Entfernt alle Entities, die spawn_for_chunk(coord) erzeugt hat. unload_cb: func(node: Node3D) -> void
## (WorldService: EntityOrchestrator.unload_entity — NICHT despawn_entity, siehe dort).
## Schon anderweitig freigegebene Entities (gefällter Baum, getötetes Tier) werden übersprungen.
func despawn_for_chunk(coord: Vector2i, unload_cb: Callable) -> void:
	var nodes: Array = _spawned.get(coord, [])
	_spawned.erase(coord)
	_clear_zones.erase(coord)
	if not unload_cb.is_valid():
		return
	for node in nodes:
		if is_instance_valid(node):
			unload_cb.call(node)

## Freihaltezonen des Chunks (Array[Vector3]: x = Welt-X, y = Welt-Z, z = Radius).
func get_clear_zones(coord: Vector2i) -> Array:
	return _clear_zones.get(coord, [])

func get_spawned_count(coord: Vector2i) -> int:
	var n: int = 0
	for node in _spawned.get(coord, []):
		if is_instance_valid(node):
			n += 1
	return n

## Spawnt EINE Entity, merkt sie sich für den Chunk und überspringt bereits Abgeerntetes.
func _spawn(type_id: String, pos: Vector3) -> void:
	if _is_harvested.is_valid() and bool(_is_harvested.call(type_id, pos)):
		return
	var node: Variant = _spawn_entity.call(type_id, pos)
	if is_instance_valid(node) and node is Node3D:
		_bucket.append(node as Node3D)

## Spawnt Props/Tiere/Gegner für coord.
## center: Chunk-Zentrum in Weltkoordinaten (Vector2).
## gen: TerrainField für Höhen-/Biom-/Wasser-Lookup (alles in Weltkoordinaten).
## chunk_node (optional): Eltern-Node für Gebäude-Geometrie. Ohne ihn (Unit-Tests) entstehen
## keine Gebäude und keine Gebäude-NPCs.
func spawn_for_chunk(
	coord: Vector2i, center: Vector2, gen: TerrainField, chunk_node: Node3D = null
) -> void:
	if not _spawn_entity.is_valid():
		return

	# Doppelt laden (ohne Entladen dazwischen) darf nichts verdoppeln.
	if _spawned.has(coord):
		return
	_bucket = []

	var half: float = _chunk_size * 0.5 - ENTITY_MARGIN
	var rng := RandomNumberGenerator.new()
	rng.seed = _base_seed ^ (coord.x * 1234567) ^ (coord.y * 7654321)

	# Round 75: EINMAL pro Chunk gesampelt (siehe Klassenkommentar), am Chunk-Zentrum.
	var biome: BiomeDefinition = gen.get_biome_at(center.x, center.y)

	# Gebäude ZUERST: es legt die Freihaltezone fest, der alles Folgende ausweicht.
	_active_zones = []
	_settlements = gen.get_settlements()
	if is_instance_valid(chunk_node):
		_spawn_structure(coord, center, gen, chunk_node)
		_spawn_settlement(center, gen, chunk_node)
	# Tier-Zoo am Spawn (ZooPlacer): hier keine Bäume/Tiere/Props würfeln.
	_active_zones.append_array(ZooLayout.zones_for_chunk(center, _chunk_size))
	_clear_zones[coord] = _active_zones

	_spawn_props(biome, center, gen, rng, half)
	_spawn_animal(coord, center, gen, rng, half)
	_spawn_fish(center, gen, rng, half)
	_spawn_enemy(coord, biome, center, gen, rng, half)

	_spawned[coord] = _bucket
	_bucket = []
	_active_zones = []

func _spawn_props(
	biome: BiomeDefinition, center: Vector2, gen: TerrainField,
	rng: RandomNumberGenerator, half: float
) -> void:
	if not is_instance_valid(biome) or biome.prop_chances.is_empty():
		return
	var a_min: int = biome.prop_attempts_min if biome.prop_attempts_min > 0 else DEFAULT_ATTEMPTS_MIN
	var a_max: int = biome.prop_attempts_max if biome.prop_attempts_max >= a_min else maxi(a_min, DEFAULT_ATTEMPTS_MAX)
	var count: int = maxi(1, roundi(float(rng.randi_range(a_min, a_max)) * PROP_DENSITY_MULT))

	# Hain-Zentren (siehe GROVE_SHARE) — immer gewürfelt, damit der RNG-Strom nicht davon abhängt,
	# ob später ein Versuch verworfen wird.
	var groves: Array[Vector2] = []
	for _g in range(rng.randi_range(2, 4)):
		groves.append(Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half)))

	# Wunsch "Friedhöfe natürlich spawnen": max. EIN Friedhof pro Chunk, auch
	# wenn "graveyard_gravestone" innerhalb derselben Chunk-Schleife mehrfach
	# rollen würde — sonst könnten sich zwei Cluster überlappen/verschmelzen.
	var graveyard_placed_this_chunk := false
	var placed: Array[Vector3] = []   # x = lokal X, y = lokal Z, z = Radius
	for _i in range(count):
		var lx: float
		var lz: float
		if rng.randf() < GROVE_SHARE:
			var g: Vector2 = groves[rng.randi_range(0, groves.size() - 1)]
			lx = clampf(g.x + rng.randfn(0.0, GROVE_SPREAD), -half, half)
			lz = clampf(g.y + rng.randfn(0.0, GROVE_SPREAD), -half, half)
		else:
			lx = rng.randf_range(-half, half)
			lz = rng.randf_range(-half, half)
		var wx: float = center.x + lx
		var wz: float = center.y + lz
		if _in_clear_zone(wx, wz):
			continue
		var h:  float = gen.get_height_at(wx, wz)
		if h <= gen.get_water_level_at(wx, wz) + SHORE_MARGIN:
			continue
		if _is_unsuitable_for_props(gen, wx, wz, h, rng):
			continue
		var type_id: String = _roll_weighted_type(
			biome.prop_chances, WorldEntityRegistry.KNOWN_PROP_TYPES, rng
		)
		if type_id.is_empty():
			continue
		var radius: float = PROP_RADIUS_TREE if type_id in TREE_PROP_TYPES else PROP_RADIUS_SMALL
		if _too_close(placed, lx, lz, radius):
			continue
		placed.append(Vector3(lx, lz, radius))
		if type_id == "graveyard_gravestone":
			if graveyard_placed_this_chunk:
				continue
			graveyard_placed_this_chunk = true
			_spawn_graveyard_cluster(Vector3(wx, h, wz), gen, rng)
			continue
		_spawn(type_id, Vector3(wx, h, wz))

func _too_close(placed: Array[Vector3], lx: float, lz: float, radius: float) -> bool:
	for p: Vector3 in placed:
		var dx: float = p.x - lx
		var dz: float = p.y - lz
		var min_dist: float = p.z + radius
		if dx * dx + dz * dz < min_dist * min_dist:
			return true
	return false

## true, wenn (wx, wz) in einer Freihaltezone (Gebäude) dieses Chunks liegt.
func _in_clear_zone(wx: float, wz: float) -> bool:
	for z: Vector3 in _active_zones:
		var dx: float = wx - z.x
		var dz: float = wz - z.y
		if dx * dx + dz * dz < z.z * z.z:
			return true
	if _settlements != null and _settlements.blocks_vegetation(wx, wz, 0.8):
		return true
	return false

## Gebäude + NPCs dieses Chunks (Plan: ChunkStructurePlanner, Geometrie: ChunkStructureBuilder).
## Die Geometrie hängt am Chunk-Node (verschwindet mit ihm), die NPCs laufen über _spawn() und
## damit durch dieselbe Buchführung wie Bäume/Tiere (despawn_for_chunk, Netzwerk-Namensvergabe).
func _spawn_structure(
	coord: Vector2i, center: Vector2, gen: TerrainField, chunk_node: Node3D
) -> void:
	var plan: Dictionary = ChunkStructurePlanner.plan(coord, center, gen, _base_seed, _chunk_size)
	if plan.is_empty():
		return
	_active_zones.append(Vector3(float(plan["x"]), float(plan["z"]), float(plan["radius"])))
	chunk_node.add_child(ChunkStructureBuilder.build(plan, center))

	var npc_type: String = ChunkStructureBuilder.npc_type(String(plan["type"]))
	var slots: Array = ChunkStructureBuilder.npc_slots(String(plan["type"]))
	if npc_type.is_empty() or slots.is_empty():
		return
	# Eigener RNG-Strom (aus dem Plan-Seed): NPC-Anzahl bleibt stabil, auch wenn sich die
	# Prop-Logik ändert.
	var srng := RandomNumberGenerator.new()
	srng.seed = int(plan["seed"]) ^ 0x4E5043
	var npc_count: int = srng.randi_range(1, slots.size())
	var floor_y: float = float(plan["base_y"]) + ChunkStructureBuilder.SLAB_TOP
	for i in range(npc_count):
		var slot: Vector2 = slots[i]
		var wp: Vector2 = ChunkStructurePlanner.local_to_world(plan, slot.x, slot.y)
		_spawn(npc_type, Vector3(wp.x, floor_y, wp.y))

## Dorf- und Wegesrand-Gebäude dieses Chunks (Plan: SettlementRegistry, Geometrie:
## ChunkSettlementBuilder) samt ihrer Bewohner. Jeder Bewohner-Slot hängt fest am Gebäude;
## die Typen sind Mehrfach-Spawns (Siedler/Bauer/Wasserträger), keine Quest-NPCs.
## Die Freihaltezone (Kreis um jedes Gebäude) kommt zu den Straßen-/Grundstückstests oben hinzu.
func _spawn_settlement(center: Vector2, gen: TerrainField, chunk_node: Node3D) -> void:
	var buildings: Array = ChunkSettlementBuilder.buildings_for_chunk(gen, center, _chunk_size)
	if buildings.is_empty():
		return
	chunk_node.add_child(ChunkSettlementBuilder.build(buildings, center))
	for b: Dictionary in buildings:
		var type_id: String = b["type"]
		_active_zones.append(Vector3(float(b["x"]), float(b["z"]), BuildingRecipes.radius(type_id)))
		var slots: Array = BuildingRecipes.npc_slots(type_id)
		if slots.is_empty():
			continue
		# Pro Gebäude stabiler Bruchteil der Slots besetzt (nicht jedes Haus hat Bewohner vor der Tür).
		var srng := RandomNumberGenerator.new()
		srng.seed = int(b["id"]) ^ 0x4E5043
		for slot_entry: Variant in slots:
			var entry: Array = slot_entry
			if srng.randf() < 0.7:
				_spawn(String(entry[0]), ChunkSettlementBuilder.npc_world_pos(b, entry[1] as Vector2))

## Props (Bäume, Büsche, Steine …) wachsen nicht auf Steilwänden und nicht im Hochgebirge:
## ab TREELINE_START dünnen sie aus, ab TREELINE_END gibt es keine mehr (Fels/Schnee).
const TREELINE_START: float = 30.0
const TREELINE_END: float = 48.0
const MAX_PROP_SLOPE_DEG: float = 38.0

func _is_unsuitable_for_props(
	gen: TerrainField, wx: float, wz: float, h: float, rng: RandomNumberGenerator
) -> bool:
	if h >= TREELINE_END:
		return true
	if h > TREELINE_START and rng.randf() < (h - TREELINE_START) / (TREELINE_END - TREELINE_START):
		return true
	# Slope nur prüfen, wenn es überhaupt hoch/bergig genug sein könnte (spart 4 Höhenabfragen).
	if h > 8.0 and gen.get_slope_at(wx, wz, 1.5) > MAX_PROP_SLOPE_DEG:
		return true
	return false

## Ein "Friedhof" ist mehrere Grabsteine, kein einzelner (siehe Wunsch
## "Friedhöfe natürlich spawnen" — Mehrzahl). anchor: bereits höhengeprüfte
## Mittelposition (siehe Aufrufer). Jeder einzelne Stein wird trotzdem
## individuell höhen-/wassergeprüft, weil ein 4m-Radius auf welligem Terrain
## durchaus einen Stein unter Wasser oder auf einen Steilhang setzen könnte.
func _spawn_graveyard_cluster(anchor: Vector3, gen: TerrainField, rng: RandomNumberGenerator) -> void:
	const CLUSTER_RADIUS: float = 4.0
	var stone_count := rng.randi_range(3, 5)
	var placed := 0
	var attempts := 0
	while placed < stone_count and attempts < stone_count * 4:
		attempts += 1
		var ox: float = rng.randf_range(-CLUSTER_RADIUS, CLUSTER_RADIUS)
		var oz: float = rng.randf_range(-CLUSTER_RADIUS, CLUSTER_RADIUS)
		var wx: float = anchor.x + ox
		var wz: float = anchor.z + oz
		var h:  float = gen.get_height_at(wx, wz)
		if h <= gen.get_water_level_at(wx, wz) + SHORE_MARGIN:
			continue
		_spawn("graveyard_gravestone", Vector3(wx, h, wz))
		placed += 1

func _spawn_animal(
	coord: Vector2i, center: Vector2, gen: TerrainField,
	rng: RandomNumberGenerator, half: float
) -> void:
	# TUNING (Feedback "noch nichts Exotisches gesehen"): war "jeder DRITTE Chunk bekommt
	# EIN Tier" — zur Zeit von Round 75 gab es 6 Landtierarten, eine bestimmte Art zu sehen
	# war also nicht selten. Mit mittlerweile 64 Landtierarten (CURATED_LAND_ANIMAL_TYPES +
	# AnimalSpeciesDB) ist die Chance, GENAU eine bestimmte Art (z.B. "tiger") in einem
	# einzelnen Spawn zu treffen, auf 1/64 gefallen — bei unverändertem Spawn-Takt hätte sich
	# die SICHTBARE Vielfalt trotz 10x mehr Arten praktisch nicht erhöht. Jetzt: jeder ZWEITE
	# Chunk (statt dritte) UND 1-2 Tiere statt genau einem pro Treffer — zusammen ~2-3x mehr
	# Tier-Spawns gesamt, näherungsweise proportional zur gewachsenen Artenvielfalt.
	if (abs(coord.x) + abs(coord.y)) % 2 != 0:
		return

	var animal_types := _all_land_animal_types()
	var spawn_count := rng.randi_range(1, 2)
	for _i in spawn_count:
		var animal_type: String = animal_types[rng.randi_range(0, animal_types.size() - 1)]
		var lx: float = rng.randf_range(-half, half)
		var lz: float = rng.randf_range(-half, half)
		var h:  float = gen.get_height_at(center.x + lx, center.y + lz)
		if _in_clear_zone(center.x + lx, center.y + lz):
			continue
		if h > gen.get_water_level_at(center.x + lx, center.y + lz) + SHORE_MARGIN:
			_spawn(animal_type, Vector3(center.x + lx, h, center.y + lz))

## Gegenstück zu _spawn_animal(), aber umgekehrte Höhenprüfung: Landtiere spawnen nur
## ÜBER dem Wasserspiegel + SHORE_MARGIN, ein Fisch nur AUF ODER UNTER dem Wasserspiegel
## (kein SHORE_MARGIN-Abzug — ein Fisch direkt am Ufer ist noch "im Wasser", anders als ein
## Baum/Tier direkt am Ufer, das noch "an Land" sein soll). Spawnt an der tatsächlichen
## Wasserhöhe (nicht am Terrainboden darunter) — siehe Fish.gd/_aquatic-Kommentar in
## AnimalBase.gd: ein Fisch "steht" nicht auf dem Seeboden, er schwebt an der Oberfläche.
func _spawn_fish(
	center: Vector2, gen: TerrainField, rng: RandomNumberGenerator, half: float
) -> void:
	if rng.randf() > FISH_CHANCE:
		return
	var lx: float = rng.randf_range(-half, half)
	var lz: float = rng.randf_range(-half, half)
	var wx: float = center.x + lx
	var wz: float = center.y + lz
	var water_level: float = gen.get_water_level_at(wx, wz)
	var h: float = gen.get_height_at(wx, wz)
	if h >= water_level:
		return  # kein Wasser an dieser Stelle in diesem Chunk
	var fish_types := _all_fish_types()
	var fish_type: String = fish_types[rng.randi_range(0, fish_types.size() - 1)]
	_spawn(fish_type, Vector3(wx, water_level, wz))

## Round 75 (Anfrage "vermehrt Skelette [im Wüsten-Biom]"). Ein Versuch pro
## Chunk, analog zur bisherigen _spawn_animal()-Kadenz — kein "jeder dritte
## Chunk"-Gate wie bei Tieren, die Wahrscheinlichkeit steckt schon in
## BiomeDefinition.enemy_chances selbst (z.B. desert: 0.06 pro Chunk).
func _spawn_enemy(
	_coord: Vector2i, biome: BiomeDefinition, center: Vector2, gen: TerrainField,
	rng: RandomNumberGenerator, half: float
) -> void:
	if not is_instance_valid(biome) or biome.enemy_chances.is_empty():
		return
	var type_id: String = _roll_weighted_type(
		biome.enemy_chances, WorldEntityRegistry.KNOWN_ENEMY_TYPES, rng
	)
	if type_id.is_empty():
		return
	var lx: float = rng.randf_range(-half, half)
	var lz: float = rng.randf_range(-half, half)
	var h:  float = gen.get_height_at(center.x + lx, center.y + lz)
	if _in_clear_zone(center.x + lx, center.y + lz):
		return
	if h > gen.get_water_level_at(center.x + lx, center.y + lz) + SHORE_MARGIN:
		_spawn(type_id, Vector3(center.x + lx, h, center.y + lz))

## Rollt EINEN Typ aus `chances` ({type_id: chance_0_to_1}), nur unter den in
## `known` gelisteten (tatsächlich registrierten) Typen — alles andere wird
## stillschweigend übersprungen (siehe WorldEntityRegistry.KNOWN_PROP_TYPES-Kommentar).
##
## Echtes gewichtetes Sampling (2026-10-05, vorher "erster Treffer in Deklarationsreihenfolge
## gewinnt" — spätere Einträge bekamen dadurch systematisch weniger als ihre Chance, und die
## Reihenfolge im Dictionary war versteckte Spielmechanik): ein Wurf, die bekannten Chancen
## bilden aufeinanderfolgende Intervalle. Summe <= 1 → jede Zahl ist exakt die Wahrscheinlichkeit
## pro Versuch, der Rest ergibt "nichts". Summe > 1 → auf 1 normiert (nie "nichts").
func _roll_weighted_type(
	chances: Dictionary, known: Array[String], rng: RandomNumberGenerator
) -> String:
	var total: float = 0.0
	for type_id: String in chances.keys():
		if type_id in known:
			total += maxf(0.0, float(chances[type_id]))
	if total <= 0.0:
		return ""
	var roll: float = rng.randf() * maxf(total, 1.0)
	var acc: float = 0.0
	for type_id: String in chances.keys():
		if not (type_id in known):
			continue
		acc += maxf(0.0, float(chances[type_id]))
		if roll < acc:
			return type_id
	return ""
