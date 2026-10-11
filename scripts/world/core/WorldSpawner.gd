class_name WorldSpawner
extends RefCounted

## WorldSpawner — Koordiniert das Spawning aller Welt-Entities.
##
## Delegiert an spezialisierte Klassen:
##   EnemySpawner    → Tiere + Feinde
##   PetRestorer     → Gespeicherte Pets wiederherstellen
##
## ChunkManager wird direkt in WorldService.on_world_scene_ready() gestartet.
## Kein Service — wird von WorldService als Hilfsklasse instanziiert.

const LOG_CAT := "WorldSpawner"

var _entity_orchestrator: EntityOrchestrator
var _terrain: TerrainField
var _world_gen: WorldGenerationService
var _data: WorldData

var _enemy_spawner: EnemySpawner
var _pet_restorer: PetRestorer

## Callable(pos: Vector3, peer_id: int) -> Node3D. Pflicht-Dep, kein Default:
## der Player MUSS über WorldService.spawn_entity() laufen, sonst registriert ihn
## niemand bei ChunkManager (siehe spawn_all() — keine Fallback-Spawn-Variante mehr,
## das war exakt der Bug: ein stiller Fallback auf _entity_orchestrator.spawn_entity()
## direkt hat den kaputten Pfad unbemerkt am Leben gehalten).
var _spawn_player_cb: Callable

func _init(
	orchestrator: EntityOrchestrator,
	terrain: TerrainField,
	world_gen: WorldGenerationService,
	world_data: WorldData,
	spawn_player_cb: Callable
) -> void:
	assert(spawn_player_cb.is_valid(), "WorldSpawner: spawn_player_cb ist Pflicht — kein Fallback mehr.")
	_entity_orchestrator = orchestrator
	_terrain   = terrain
	_world_gen           = world_gen
	_data                = world_data
	_spawn_player_cb     = spawn_player_cb

	_enemy_spawner = EnemySpawner.new(orchestrator, terrain)
	_pet_restorer  = PetRestorer.new(world_data, orchestrator)

## Haupt-Entry-Point: spawnt alles für eine frische Welt-Session.
## peer_id: lokale peer_id des Spielers — wird für set_multiplayer_authority() auf
## dem Player-Node genutzt (E-2). Default 1 für Solo/Host.
## spawn_local_player: ADR-010 Round 55 — false NUR für Tier 3 (Dedizierter Server):
## der Host-Prozess ist dort reine Autorität, kein spielender Client, braucht also
## kein eigenes Player-Entity. Alles andere (Terrain, Tiere, Quest-NPC, Enemies,
## Pets, Wasser) wird unverändert gespawnt — die Welt existiert unabhängig davon,
## ob der Host selbst mitspielt. Default true — Tier 1/2 unverändert.
## Awaitet intern auf die (async) Positions-Generierung, falls kein Save vorhanden
## ist — Aufrufer müssen entsprechend `await spawner.spawn_all(...)` verwenden.
func spawn_all(world_root: Node3D, peer_id: int = 1, spawn_local_player: bool = true) -> void:
	var t := AppLogger.log_begin("WorldSpawner.spawn_all()", LOG_CAT)

	if _data.typed_tree_positions.is_empty() and _data.typed_ore_positions.is_empty():
		await _generate_positions()

	# Typisiertes Spawning: typed_*_positions enthält { type_id: [Vector3, ...] }
	var trees_spawned := 0
	for type_id in _data.typed_tree_positions:
		for pos in _data.typed_tree_positions[type_id]:
			if not _data.is_harvested_by_type(type_id, pos):
				_entity_orchestrator.spawn_entity(type_id, pos)
				trees_spawned += 1

	var ores_spawned := 0
	for type_id in _data.typed_ore_positions:
		for pos in _data.typed_ore_positions[type_id]:
			if not _data.is_harvested_by_type(type_id, pos):
				_entity_orchestrator.spawn_entity(type_id, pos)
				ores_spawned += 1

	_enemy_spawner.spawn_animals()

	var quest_h: float = 0.0
	if is_instance_valid(_terrain):
		quest_h = _terrain.get_height_at(8.0, -5.0)
	# BUGFIX ("Erik gibt nie eine zweite Quest"): "woodcutter_npc" statt
	# generischem "quest_npc" — siehe WoodcutterNPC.gd Klassenkommentar.
	_entity_orchestrator.spawn_entity("woodcutter_npc", Vector3(8.0, quest_h, -5.0))

	var shop_h: float = 0.0
	if is_instance_valid(_terrain):
		shop_h = _terrain.get_height_at(12.0, -5.0)
	_entity_orchestrator.spawn_entity("shop_npc", Vector3(12.0, shop_h, -5.0))

	var bank_h: float = 0.0
	if is_instance_valid(_terrain):
		bank_h = _terrain.get_height_at(16.0, -5.0)
	_entity_orchestrator.spawn_entity("bank_npc", Vector3(16.0, bank_h, -5.0))

	var auction_h: float = 0.0
	if is_instance_valid(_terrain):
		auction_h = _terrain.get_height_at(20.0, -5.0)
	_entity_orchestrator.spawn_entity("auction_house_npc", Vector3(20.0, auction_h, -5.0))

	# ADR-048 Round 106: Tutorial-Teil 2 — bewusst NAHE am Player-Spawnpunkt
	# (0,0,0, siehe unten), nicht bei den anderen NPCs auf der "Handels-
	# straße" bei x=8..20 — der Guide soll das Erste sein, was ein frisch
	# gespawnter Spieler sieht, nicht erst nach einem Fußmarsch entdeckt
	# werden. Versatz (-3, 3) statt exakt (0,0), damit der NPC nicht direkt
	# auf dem Player-Spawnpunkt steht.
	var guide_h: float = 0.0
	if is_instance_valid(_terrain):
		guide_h = _terrain.get_height_at(-3.0, 3.0)
	_entity_orchestrator.spawn_entity("tutorial_guide_npc", Vector3(-3.0, guide_h, 3.0))

	# Wunsch "es fehlt ein NPC den ich beklauen kann" — auf derselben
	# "Handelsstraße" wie shop/bank/auction (x=8..20), einen Schritt weiter
	# bei x=24, damit er nicht mit den anderen NPCs überlappt.
	var villager_h: float = 0.0
	if is_instance_valid(_terrain):
		villager_h = _terrain.get_height_at(24.0, -5.0)
	_entity_orchestrator.spawn_entity("villager_npc", Vector3(24.0, villager_h, -5.0))

	# Wunsch "Quests weiter ausbauen + NPCs": zwei neue Quest-Geber auf einer
	# zweiten Reihe (z=-9) hinter der bestehenden "Handelsstraße" (z=-5,
	# x=8..24) platziert, damit sie nicht mit shop/bank/auction/villager
	# überlappen, aber trotzdem in Laufnähe zum Spawnpunkt bleiben.
	var miner_h: float = 0.0
	if is_instance_valid(_terrain):
		miner_h = _terrain.get_height_at(8.0, -9.0)
	_entity_orchestrator.spawn_entity("miner_npc", Vector3(8.0, miner_h, -9.0))

	var herbalist_h: float = 0.0
	if is_instance_valid(_terrain):
		herbalist_h = _terrain.get_height_at(12.0, -9.0)
	_entity_orchestrator.spawn_entity("herbalist_npc", Vector3(12.0, herbalist_h, -9.0))

	# Wunsch "Quests ausbauen, aber nicht nur kill/deliver" — Wei und Babatunde
	# auf derselben zweiten Reihe (z=-9) wie Mira/Senna, einen Schritt weiter
	# (x=16, x=20), damit sie nicht mit den bestehenden NPCs überlappen.
	var wei_h: float = 0.0
	if is_instance_valid(_terrain):
		wei_h = _terrain.get_height_at(16.0, -9.0)
	_entity_orchestrator.spawn_entity("wudang_master_npc", Vector3(16.0, wei_h, -9.0))

	var babatunde_h: float = 0.0
	if is_instance_valid(_terrain):
		babatunde_h = _terrain.get_height_at(20.0, -9.0)
	_entity_orchestrator.spawn_entity("ancestor_spirit_npc", Vector3(20.0, babatunde_h, -9.0))

	# Wunsch "ein wirklicher Quest mit Pfiff" — Talia auf derselben Reihe
	# (z=-9), einen Schritt weiter (x=24), analog zu Wei/Babatunde oben.
	var talia_h: float = 0.0
	if is_instance_valid(_terrain):
		talia_h = _terrain.get_height_at(24.0, -9.0)
	_entity_orchestrator.spawn_entity("guard_npc", Vector3(24.0, talia_h, -9.0))

	# ADR-051 Stufe 3 Demo: Rasmus, eine Reihe weiter (x=28, z=-9).
	var rasmus_h: float = 0.0
	if is_instance_valid(_terrain):
		rasmus_h = _terrain.get_height_at(28.0, -9.0)
	_entity_orchestrator.spawn_entity("village_elder_npc", Vector3(28.0, rasmus_h, -9.0))

	# Nest-NPCs (docs/nests.md) — dritte Reihe (z=-13) hinter Mira/Senna/Wei/... (z=-9),
	# x=8..28 im selben Raster, damit nichts überlappt.
	var myrmex_ant_h: float = 0.0
	if is_instance_valid(_terrain):
		myrmex_ant_h = _terrain.get_height_at(8.0, -13.0)
	_entity_orchestrator.spawn_entity("myrmex_npc", Vector3(8.0, myrmex_ant_h, -13.0))
	var rudo_builder_h: float = 0.0
	if is_instance_valid(_terrain):
		rudo_builder_h = _terrain.get_height_at(12.0, -13.0)
	_entity_orchestrator.spawn_entity("rudo_builder_npc", Vector3(12.0, rudo_builder_h, -13.0))
	var lucius_surveyor_h: float = 0.0
	if is_instance_valid(_terrain):
		lucius_surveyor_h = _terrain.get_height_at(16.0, -13.0)
	_entity_orchestrator.spawn_entity("surveyor_npc", Vector3(16.0, lucius_surveyor_h, -13.0))
	var gerlinde_zeidler_h: float = 0.0
	if is_instance_valid(_terrain):
		gerlinde_zeidler_h = _terrain.get_height_at(20.0, -13.0)
	_entity_orchestrator.spawn_entity("zeidler_npc", Vector3(20.0, gerlinde_zeidler_h, -13.0))
	var lian_paper_h: float = 0.0
	if is_instance_valid(_terrain):
		lian_paper_h = _terrain.get_height_at(24.0, -13.0)
	_entity_orchestrator.spawn_entity("papermaker_npc", Vector3(24.0, lian_paper_h, -13.0))
	var sigrun_oracle_h: float = 0.0
	if is_instance_valid(_terrain):
		sigrun_oracle_h = _terrain.get_height_at(28.0, -13.0)
	_entity_orchestrator.spawn_entity("hornet_oracle_npc", Vector3(28.0, sigrun_oracle_h, -13.0))

	# Farming (Wunsch "Samen pflanzen + ernten") — drei Ackerbeete in der
	# Nähe des Spawnpunkts, auf der dem NPC-"Handelsstraße" gegenüberliegenden
	# Seite (negatives x) damit sie nicht mit shop/bank/villager überlappen.
	for i in range(3):
		var plot_x := -6.0 - float(i) * 1.5
		var plot_z := 3.0
		var plot_h: float = 0.0
		if is_instance_valid(_terrain):
			plot_h = _terrain.get_height_at(plot_x, plot_z)
		_entity_orchestrator.spawn_entity("farm_plot", Vector3(plot_x, plot_h, plot_z))

	# Kräutergarten (herbalism) + Blumengarten (gardening): je eine Reihe FarmPlots hinter den
	# Karottenbeeten (z=3), crop_id aus PlantCatalog. Später (geplant) ersetzt ein baubares Beet mit
	# freier Samenwahl diese festen Felder — siehe docs/herbalism-and-gardening.md.
	var herb_ids: Array[String] = []
	var flower_ids: Array[String] = []
	for plant_id in PlantCatalog.ids():
		if PlantCatalog.get_plant(plant_id)["skill"] == PlantCatalog.SKILL_HERBALISM:
			herb_ids.append(plant_id)
		else:
			flower_ids.append(plant_id)
	var garden_rows: Array = [[herb_ids, 6.5], [flower_ids, 10.0]]
	for row: Array in garden_rows:
		var row_ids: Array[String] = row[0]
		for i in range(row_ids.size()):
			var gx: float = -6.0 - float(i) * 1.5
			var gz: float = row[1]
			var gh: float = 0.0
			if is_instance_valid(_terrain):
				gh = _terrain.get_height_at(gx, gz)
			_entity_orchestrator.spawn_entity("farm_plot", Vector3(gx, gh, gz), {"crop_id": row_ids[i]})

	# Försterei (Wunsch "Försterei-Skill: Setzlinge kaufen + pflanzen", für
	# alle Baumarten ausgebaut) — Förster Holgar auf der "Handelsstraße" (z=-5)
	# hinter Villager (x=24), plus je ein Baumschul-Plot (FarmPlot mit
	# crop_id="<art>_sapling", siehe FarmPlot.gd Klassenkommentar "Försterei-
	# Erweiterung") pro Baumart direkt daneben, damit man Setzling kaufen und
	# pflanzen in einem Zug erledigen kann, ohne quer über die Karte zu laufen.
	var forester_h: float = 0.0
	if is_instance_valid(_terrain):
		forester_h = _terrain.get_height_at(28.0, -5.0)
	_entity_orchestrator.spawn_entity("forester_npc", Vector3(28.0, forester_h, -5.0))

	var nursery_crops: Array[String] = [
		"oak_sapling", "maple_sapling", "pine_sapling", "willow_sapling"
	]
	for i in range(nursery_crops.size()):
		var nursery_x := 30.0 + float(i) * 1.5
		var nursery_z := -3.0
		var nursery_h: float = 0.0
		if is_instance_valid(_terrain):
			nursery_h = _terrain.get_height_at(nursery_x, nursery_z)
		_entity_orchestrator.spawn_entity(
			"farm_plot", Vector3(nursery_x, nursery_h, nursery_z), {"crop_id": nursery_crops[i]}
		)

	# Wunsch "alle Tiere in Glaskästen am Spawn, mit Schild davor": der Zoo liegt südlich vom
	# Spawn (siehe ZooLayout.ZOO_RECT). Die Freihaltezone dafür steht in ChunkEntitySpawner, damit
	# dort keine Bäume/Tiere/Props hineinwachsen.
	ZooPlacer.place(_entity_orchestrator, _terrain)

	_enemy_spawner.spawn_enemies()

	# Player via EntityOrchestrator spawnen — erhält on_spawn(config, ctx) wie alle Entities.
	# spawn_position via config damit Player.on_spawn() die korrekte Startposition kennt.
	# peer_id: lokale Peer-ID des Spielers → EntityOrchestrator setzt set_multiplayer_authority().
	var player_y: float = 3.0
	if is_instance_valid(_terrain):
		player_y = _terrain.get_height_at(0.0, 0.0) + 2.0
	var player_spawn := Vector3(0.0, player_y, 0.0)
	# Player-Spawn: BUG-FIX (nur Spawn-Chunk lädt, Welt "endet" nach ~64m) —
	# vorher lief dieser Aufruf direkt über _entity_orchestrator.spawn_entity(),
	# was WorldService.spawn_entity() (und damit dessen
	# _chunk_manager.add_player()-Aufruf) komplett umging. ChunkManager._tracked_players
	# blieb dadurch für die gesamte Session leer → on_tick() gab bei jedem Frame sofort
	# zurück (_tracked_players.is_empty()) und außer dem synchron in
	# ChunkManager.initialize() geladenen Chunk (0,0) wurde nie ein weiterer Chunk
	# in die Load-Queue eingereiht.
	# KEIN Fallback mehr auf den direkten Pfad: _spawn_player_cb ist Pflicht-Dep
	# (siehe _init()) — wenn das mal falsch verdrahtet wird, soll das hier laut
	# krachen statt still auf den kaputten alten Pfad zurückzufallen.
	# ADR-010 Round 55: spawn_local_player=false ist der einzige legitime Grund,
	# _spawn_player_cb NICHT aufzurufen — Tier 3, der Host spielt nicht mit.
	if spawn_local_player:
		_spawn_player_cb.call(player_spawn, peer_id)
	else:
		AppLogger.log_info(
			"Kein lokales Player-Entity gespawnt (Tier 3 — Dedizierter Server, peer %d bleibt reine Autorität)." % peer_id,
			LOG_CAT
		)

	# BUGFIX (2026-09-20, "Pets nach Neuladen buggy/laufen nicht mehr"):
	# _pet_restorer.restore() lief bisher HIER VOR dem Player-Spawn oben.
	# PetComponent._find_owner() sucht aber schon in on_spawn() (also
	# synchron während restore()) nach einem Node in Gruppe "player" — gab es
	# den noch nicht, blieb _player_ref dauerhaft null (aktualisiert wird es
	# danach nur noch über player_died/player_respawned-Signale, die beim
	# normalen Login nie feuern). Das Pet stand dadurch nach jedem Neuladen
	# regungslos herum. Fix: erst NACH dem Player-Spawn restaurieren.
	_pet_restorer.restore(world_root)

	AppLogger.log_end("WorldSpawner.spawn_all()", t, LOG_CAT)
	AppLogger.log_info(
		"Spawning: %d Bäume, %d Erze. Aktiv: %d." % [
			trees_spawned, ores_spawned, _entity_orchestrator.get_entity_count()
		], LOG_CAT
	)

## Erzeugt neue Welt-Positionen. Wenn WorldGenerationService verfügbar ist, läuft
## das immer über generate_world_async() + await — kein synchroner Zweitpfad.
## Ohne WorldGenerationService (z.B. isolierte Unit-Tests von WorldSpawner selbst)
## bleiben die Hardcode-Defaults als expliziter DI-Fallback bestehen (siehe
## _make_spawner_no_worldgen() in test_world_spawner.gd) — das ist ein "Service
## fehlt komplett"-Fallback, kein Duplikat der Generierungslogik.
func _generate_positions() -> void:
	# Fix P1: world_seed aus WorldData nutzen statt Time.get_unix_time_from_system()
	# → deterministisch und konsistent mit ChunkManager. Muss VOR der Verzweigung
	# passieren, damit auch der Hardcode-Fallback-Pfad einen gültigen Seed setzt.
	if _data.world_seed == 0:
		# WorldSeedUtil.resolve() (Wunsch "ist world_seed vielleicht immer 0?"): dieselbe
		# einzige Formel wie WorldService.configure()/on_world_scene_ready() statt einer
		# dritten, unabhängigen Kopie — verhindert, dass dieser Pfad (falls er je greift)
		# einen ANDEREN Seed erzeugt als Terrain/Wetter bereits verwenden.
		_data.world_seed = WorldSeedUtil.resolve(_data.world_seed)
		AppLogger.log_warn(
			"world_seed war 0 — neuer Seed für Positionen: %d." % _data.world_seed, LOG_CAT
		)

	if is_instance_valid(_world_gen):
		AppLogger.log_info("Kein Save — generiere via WorldGenerationService (async).", LOG_CAT)
		var height_cb := Callable()
		if is_instance_valid(_terrain):
			height_cb = _terrain.get_height_at
		_world_gen.generate_world_async(_data.world_seed, _data, height_cb)
		var result: WorldData = await _world_gen.generation_complete
		if result != _data:
			# generate_world_async() erstellt bei data==null ein neues WorldData —
			# wir übergeben _data nie als null, aber defensiv absichern falls sich
			# das mal ändert: Ergebnis muss dieselbe Instanz sein wie _data.
			AppLogger.log_error(
				"WorldGenerationService.generation_complete lieferte eine andere WorldData-Instanz zurück.",
				LOG_CAT
			)
	else:
		AppLogger.log_warn("WorldGenerationService fehlt — nutze Hardcode-Defaults.", LOG_CAT)
		# Typisierte Defaults: gemischte Baumtypen demonstrieren das Datenschema.
		_data.add_typed_tree("oak_tree",    Vector3(5,  0, 5))
		_data.add_typed_tree("willow_tree", Vector3(-6, 0, 4))
		_data.add_typed_tree("maple_tree",  Vector3(8,  0, -3))
		_data.add_typed_ore("iron_ore",     Vector3(-4, 0, 6))
		_data.add_typed_ore("copper_ore",   Vector3(6,  0, -8))
