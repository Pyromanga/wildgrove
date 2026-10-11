extends ServiceNode
# justified: ServiceTicker-Registrierung (add_child) und on_tick() brauchen Node-Lifecycle.
class_name ConditionalEncounterService

## ConditionalEncounterService — "Special-Bedingungs"-Gegner: Typen, die
## NUR unter bestimmten Umständen auftauchen (Biom + Wetter + Tageszeit),
## statt wie goblin/skeleton permanent über BiomeDefinition.enemy_chances.
##
## ABGRENZUNG ZU AmbientSpawnService (bewusst EIGENER Dienst, kein drittes
## Feld an _Point drangeschraubt): AmbientSpawnService kreist um ORTSFESTE
## Quellen (ein Grabstein/Lagerfeuer existiert immer, spawnt immer denselben
## Typ in seiner Nähe). Hier gibt es KEINE Quelle — ein Werwolf soll nicht an
## einem bestimmten Punkt kleben, sondern überall im Wald auftauchen können,
## sobald es Nacht wird, unabhängig davon ob dort je ein Grabstein/Lagerfeuer
## stand. Das Konzept ist "Zustand der Welt um den SPIELER" statt "Zustand an
## einem registrierten PUNKT" — ein grundsätzlich anderer Prüf-Ort (pro
## Spieler statt pro registrierter Quelle), daher eigener Dienst statt eines
## dritten, immer wachsenderen _Point-Feldsatzes in AmbientSpawnService.
##
## ABGRENZUNG ZU ChunkEntitySpawner.enemy_chances: jener Pfad ist EINMALIG
## pro Chunk-Erstladung und rein deterministisch aus dem Seed (kein Tick,
## keine Laufzeit-Bedingungen möglich) — ein Chunk, der zufällig mittags
## geladen wird, hätte nie eine Chance auf einen Nacht-exklusiven Gegner.
## Bedingungen, die sich über die Zeit ÄNDERN (Wetter, Tag/Nacht), brauchen
## zwingend einen wiederkehrenden Tick — identisch zur Begründung, warum
## AmbientSpawnService ein eigener, tick-basierter Dienst ist statt Teil von
## ChunkEntitySpawner.
##
## DATENMODELL: ENCOUNTERS ist bewusst ein einfaches Array[Dictionary]
## statt eigener Resource-Klasse/.tres-Dateien — die Definitionen sind reine
## Spawn-Logik-Konfiguration (Biome/Wetter/Nacht/Chance), kein vom
## Spieldesign befülltes Content-Artefakt wie Items/Quests (die sehr wohl
## .tres sind, siehe DataManifest-Konvention dort). Neue Encounter: Eintrag
## hier ergänzen, kein neuer Dateityp/Schema nötig. type_id muss in
## WorldEntityRegistry registriert sein, sonst spawnt nichts (EntityOrchestrator.
## register_definition() loggt den Fehler bereits selbst).
##
## Feld-Bedeutung pro Eintrag:
##   type_id:       Entity-Typ (muss registriert sein)
##   biomes:        Array[String], leer = jedes Biom erlaubt
##   weathers:      Array[String], leer = jedes Wetter erlaubt (siehe WeatherService.WEATHER_TYPES)
##   night_only:    true = nur wenn WorldTimeService.is_night()
##   chance:        0..1, pro fälligem Check gewürfelt (kein Garant selbst wenn alle Bedingungen passen)
##   check_interval:Sekunden zwischen Checks FÜR DIESEN Encounter, pro Spieler
##   max_nearby:    Population-Cap DIESES Typs im activation_radius um den Spieler
##   min_radius/max_radius: Spawn-Ring um den Spieler (nicht direkt auf ihm)
const ENCOUNTERS: Array[Dictionary] = [
	{
		"type_id": "werewolf",
		"biomes": ["forest", "dense_forest", "mountain"],
		"weathers": [],
		"night_only": true,
		"chance": 0.15,
		"check_interval": 90.0,
		"max_nearby": 1,
		"min_radius": 15.0,
		"max_radius": 35.0,
	},
	{
		"type_id": "fog_wraith",
		"biomes": ["swamp", "meadow"],
		"weathers": ["fog", "storm"],
		"night_only": false,
		"chance": 0.2,
		"check_interval": 60.0,
		"max_nearby": 1,
		"min_radius": 12.0,
		"max_radius": 30.0,
	},
]

const LOG_CAT := "ConditionalEncounterService"
## Jitter wie bei AmbientSpawnService — verhindert, dass bei vielen Spielern
## alle Checks für denselben Encounter-Typ im selben Tick fällig werden.
const CHECK_JITTER_SECS: float = 15.0

var _ticker: ServiceTicker = null
var _rng := RandomNumberGenerator.new()
## key: "<peer_id>:<encounter_index>" → nächster fälliger Check (Unix-Zeit).
var _next_check_at: Dictionary = {}

## Callable(type_id: String, position: Vector3) -> Node3D
var _spawn_cb: Callable = Callable()
## Callable(world_x: float, world_z: float) -> String
var _get_biome_id_cb: Callable = Callable()
## Callable(world_x: float, world_z: float) -> float
var _get_height_cb: Callable = Callable()
## Callable() -> String
var _get_weather_cb: Callable = Callable()
## Callable() -> bool
var _is_night_cb: Callable = Callable()

# ─────────────────────────────────────────────
# Phase 4/5/7
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_ticker = deps.get_optional(ServiceKeys.TICKER) as ServiceTicker
	_rng.randomize()
	AppLogger.log_debug("ConditionalEncounterService konfiguriert (wartet auf Callback-Injection).", LOG_CAT)

func on_ready() -> void:
	if is_instance_valid(_ticker):
		_ticker.register_service(self)
	AppLogger.log_info("ConditionalEncounterService bereit (%d Encounter-Typen)." % ENCOUNTERS.size(), LOG_CAT)

func on_cleanup() -> void:
	_next_check_at.clear()
	_spawn_cb = Callable()
	AppLogger.log_debug("ConditionalEncounterService bereinigt.", LOG_CAT)

# ─────────────────────────────────────────────
# Callback-Injection (von WorldService.on_ready()) — gleiches Muster wie
# AmbientSpawnService/RespawnService: kein direkter Service-Zugriff, um
# keinen zirkulären DI-Graphen mit WorldService zu erzeugen (TerrainField/
# WeatherService/WorldTimeService sind reine WorldService-interne Felder,
# nicht Teil des DI-Containers — siehe deren Klassenkommentare).
func set_callbacks(
	spawn_cb: Callable, get_biome_id_cb: Callable, get_height_cb: Callable,
	get_weather_cb: Callable, is_night_cb: Callable
) -> void:
	assert(spawn_cb.is_valid(), "ConditionalEncounterService: spawn_cb ungültig!")
	_spawn_cb = spawn_cb
	_get_biome_id_cb = get_biome_id_cb
	_get_height_cb = get_height_cb
	_get_weather_cb = get_weather_cb
	_is_night_cb = is_night_cb
	AppLogger.log_debug("Callbacks injiziert.", LOG_CAT)

# ─────────────────────────────────────────────
# Tick — pro Spieler, pro Encounter-Typ
# ─────────────────────────────────────────────

func on_tick(_delta: float) -> void:
	if not _spawn_cb.is_valid():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var now := Time.get_unix_time_from_system()
	for player in tree.get_nodes_in_group("player"):
		if not player is Node3D:
			continue
		var peer_id: int = player.get_meta("owner_peer_id", 1)
		for i in range(ENCOUNTERS.size()):
			_check_encounter(peer_id, i, ENCOUNTERS[i], player as Node3D, now)

func _check_encounter(peer_id: int, index: int, enc: Dictionary, player: Node3D, now: float) -> void:
	var key := "%d:%d" % [peer_id, index]
	var due: float = _next_check_at.get(key, 0.0)
	if now < due:
		return
	_next_check_at[key] = now + float(enc["check_interval"]) + _rng.randf_range(-CHECK_JITTER_SECS, CHECK_JITTER_SECS)

	if bool(enc["night_only"]) and _is_night_cb.is_valid() and not bool(_is_night_cb.call()):
		return

	var weathers: Array = enc["weathers"]
	if not weathers.is_empty() and _get_weather_cb.is_valid():
		var current: String = _get_weather_cb.call()
		if not weathers.has(current):
			return

	var pos: Vector3 = player.global_position
	var biomes: Array = enc["biomes"]
	if not biomes.is_empty() and _get_biome_id_cb.is_valid():
		var biome_id: String = _get_biome_id_cb.call(pos.x, pos.z)
		if not biomes.has(biome_id):
			return

	if _rng.randf() > float(enc["chance"]):
		return

	var type_id: String = enc["type_id"]
	if _count_nearby_of_type(type_id, pos, float(enc["max_radius"])) >= int(enc["max_nearby"]):
		return

	var angle := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(float(enc["min_radius"]), float(enc["max_radius"]))
	var spawn_x := pos.x + cos(angle) * dist
	var spawn_z := pos.z + sin(angle) * dist
	var spawn_y: float = _get_height_cb.call(spawn_x, spawn_z) if _get_height_cb.is_valid() else pos.y
	var spawn_pos := Vector3(spawn_x, spawn_y, spawn_z)

	var entity = _spawn_cb.call(type_id, spawn_pos)
	if is_instance_valid(entity):
		AppLogger.log_info(
			"Special-Encounter '%s' @ %s (Spieler peer %d)." % [type_id, str(spawn_pos), peer_id], LOG_CAT
		)

## Zählt Entities MIT PASSENDEM entity_type-Meta (EntityOrchestrator.
## spawn_entity() setzt das bei jedem Spawn, siehe dortiger Kommentar) —
## anders als AmbientSpawnService._count_nearby_enemies() (zählt ALLE
## "enemies" pauschal), weil der Cap hier gezielt PRO SPEZIALTYP gelten
## soll: ein Werwolf in der Nähe soll keinen Fuchs-Goblin-Spawn blockieren
## und umgekehrt, aber einen ZWEITEN Werwolf schon.
func _count_nearby_of_type(type_id: String, position: Vector3, radius: float) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var n := 0
	for node in tree.get_nodes_in_group("enemies"):
		if node is Node3D and node.get_meta("entity_type", "") == type_id:
			if (node as Node3D).global_position.distance_to(position) <= radius:
				n += 1
	return n
