extends ServiceNode
# justified: add_child(_entity_orchestrator); queue_free(ChunkManager); on_world_scene_ready(Node3D).
class_name WorldService

## WorldService — Lifecycle + öffentliche API für die Spielwelt.
##
## Delegiert Verantwortlichkeiten an spezialisierte Klassen:
##   WorldSpawner          → Entities, Tiere, Wasser, Pets, Chunks spawnen
##   WorldSaveHandler      → Save/Restore-Logik (v28)
##   WorldEntityRegistry   → Entity-Definitionen registrieren (v28)
##   WorldTimeService      → Tageszeit verwalten
##   WeatherService        → Wetter verwalten (ADR-041)
##   WorldFactory          → statische Geometrie erstellen
##   EntityOrchestrator    → Entity-Pooling + UUID-Verwaltung
##
## Abhängigkeiten: ["savesystem", "world_gen"]

const LOG_CAT := "World"
const SAVE_KEY := "world_state"

var data:     WorldData
var factory:  WorldFactory
var factory3d: Factory3D

var _save_system:    SaveSystem
var _world_gen:      WorldGenerationService
var _ticker:         ServiceTicker = null
var _respawn:        RespawnService = null
var _ambient_spawner: AmbientSpawnService = null
var _conditional_encounters: ConditionalEncounterService = null
var _enemy_culling: EnemyCullingService = null
var _game_manager:   GameManager   = null
var _session_manager: SessionManager = null
var _entity_orchestrator: EntityOrchestrator
var _spawner:  WorldSpawner
var _time:     WorldTimeService
## ADR-041: Wetter — Sibling zu _time, siehe WeatherService-Klassenkommentar
## für die Design-Entscheidung (deterministischer Wurf statt RPC-Broadcast).
var _weather:  WeatherService
var _save_handler: WorldSaveHandler
var _chunk_manager: ChunkManager  # Stored so on_cleanup() can shut it down properly
## Optik-Fortsetzung von _weather (ADR-041) — Regen/Schnee/Wind, siehe
## WeatherVfx-Klassenkommentar. Reine Node-Referenz zum Aufräumen, keine
## Wahrheit: _weather.current_weather bleibt die einzige Quelle.
var _weather_vfx: WeatherVfx = null

## Siehe AmbientForestVfx-Klassenkommentar. Reine Node-Referenz zum Aufräumen,
## wie _weather_vfx — Wahrheit (Biom) bleibt bei TerrainField.
var _ambient_forest_vfx: AmbientForestVfx = null

## Siehe DayNightCycle-Klassenkommentar. Reine Node-Referenz zum Aufräumen —
## Wahrheit (Uhrzeit) bleibt bei _time (WorldTimeService).
var _day_night_cycle: DayNightCycle = null

## Für WeatherVfx (Nebel/Sonnenhelligkeit je Wetter) — nachgeschlagen in
## on_world_scene_ready(), siehe dortigen Kommentar. Reine Node-/Resource-
## Referenzen, kein eigener Zustand hier.
var _world_environment: Environment = null
var _sun_light: DirectionalLight3D = null

## Gelände: DIE Wahrheit für Höhe/Wasser/Klima (Config + world_seed + Spieler-Änderungen).
## Wird in on_world_scene_ready() angelegt und an alle weitergereicht, die Höhen brauchen.
var _terrain: TerrainField
## Graben/Aufschütten und Bauen (Hilfsklassen ohne eigenen Zustand außer der Ansicht).
var _terrain_editor: WorldTerrainEditor
## Bruchteil-Guthaben je Spieler beim Ebnen (in Items, 0 ≤ x < 1) — siehe request_terrain_plane().
var _plane_credit: Dictionary = {}
var _dig_handler: WorldDigHandler
var _build_handler: WorldBuildHandler
## true nur in Solo-Sitzungen (siehe on_world_scene_ready()). Steuert, ob Umbauten wirken/sichtbar sind.
var _edits_active: bool = false
var _bus:           IEventBus

## ADR-020: NetworkBridge — für request_entity_interaction() (Nicht-Autorität
## leitet an die Autorität weiter statt lokal zu wirken). NICHT als configure()-Dep
## bezogen (das wäre ein Zyklus mit NetworkBridges eigenem "world"-Dep, siehe
## BootstrapConfig.tres), sondern über denselben Phase-C8-Late-Inject-Mechanismus
## wie Inventory/Quest/SkillSystem/Equipment (siehe inject_network_bridge() unten).
var _network: NetworkBridge = null

## Werden in configure() aufgelöst und per set_entity_services() an EntityOrchestrator weitergereicht.
var _ent_skill:     SkillSystem         = null
var _ent_inventory: InventorySystem     = null
## FEATURE (Wunsch "Bauitems können auch aus der Bank gezogen werden"): _can_afford_build()/
## _pay_build() greifen bei fehlendem Inventar-Bestand zusätzlich auf die Bank zurück (siehe
## dortiger Kommentar) — optional (get_optional()), Bauen bleibt ohne BankService weiterhin
## rein inventarbasiert funktionsfähig (z.B. in Tests ohne vollen Service-Graph).
var _ent_bank: BankService              = null
var _ent_stat_mod:  StatModifierService = null
var _ent_combat:    CombatSystem        = null
## ADR-051 Stufe 3: für EntityContext.get_quest_service() (DialogueTreeController).
var _ent_quest:     QuestService        = null
var _ent_equipment: EquipmentService    = null
var _ent_interact:  InteractionExecutor = null
var _ent_player_states: PlayerStateService = null
var _ent_data:      DataService         = null
## Für EntityContext.get_currency() — EnemyNPC._die() (Goblin-/Skelett-Gold-Drops).
var _ent_currency:  CurrencyService     = null
## ADR-035: für EntityContext.get_trade_service() — Player._on_trade_requested().
var _ent_trade:     TradeService        = null
## ADR-036: für EntityContext.get_pvp_death_loss() — Player._on_player_died().
var _ent_pvp_death_loss: PvPDeathLossService = null
## ADR-036: für EntityContext.get_aura() — Player._on_thank_requested().
var _ent_aura: AuraService = null
## ADR-037: für EntityContext.get_death_loot() — Player._on_player_died() (PvE-Zweig).
var _ent_death_loot: DeathLootService = null
## ADR-039: für EntityContext.get_pickpocket() — Player._on_pickpocket_requested().
var _ent_pickpocket: PickpocketService = null
## Für EntityContext.get_settings() — TouchInput (feste Joystick-Position).
var _ent_settings: SettingsService = null

## ADR-030: ZoneService — kein EntityContext-Dep (kein Entity braucht es
## direkt), nur zum Verdrahten der zone_triggers-Gruppe (siehe _wire_zone_triggers()).
var _zone_service: ZoneService = null

## Computed properties — always current, never one tick stale.
var day_time: float:
	get: return _time.day_time if is_instance_valid(_time) else 0.0
var day_count: int:
	get: return _time.day_count if is_instance_valid(_time) else 0
var current_weather: String:
	get: return _weather.current_weather if is_instance_valid(_weather) else WeatherService.DEFAULT_WEATHER

# ─────────────────────────────────────────────
# Service-Lifecycle
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_save_system     = deps.get_optional(ServiceKeys.SAVE_SYSTEM)    as SaveSystem
	_world_gen       = deps.get_optional(ServiceKeys.WORLD_GEN)      as WorldGenerationService
	_ticker          = deps.get_optional(ServiceKeys.TICKER)         as ServiceTicker
	_respawn         = deps.get_optional(ServiceKeys.RESPAWN)        as RespawnService
	_ambient_spawner = deps.get_optional(ServiceKeys.AMBIENT_SPAWNER) as AmbientSpawnService
	_conditional_encounters = deps.get_optional(ServiceKeys.CONDITIONAL_ENCOUNTERS) as ConditionalEncounterService
	_enemy_culling = deps.get_optional(ServiceKeys.ENEMY_CULLING) as EnemyCullingService
	_ent_quest         = deps.get_optional(ServiceKeys.QUEST) as QuestService
	_game_manager    = deps.get_optional(ServiceKeys.GAME_MANAGER)   as GameManager
	_session_manager = deps.get_optional(ServiceKeys.SESSION_MANAGER) as SessionManager
	# BUG-24: war fälschlich .require() — als einzige der ~15 Deps hier,
	# im Widerspruch zum dokumentierten Vertrag oben ("configure() ohne
	# optionale Deps → kein Crash, null-Guards greifen") und zu
	# test_configure_without_deps_does_not_crash(). Alle Nutzungsstellen
	# unten sind bereits (oder werden hiermit) null-safe gemacht.
	_bus             = deps.get_optional(ServiceKeys.EVENT_BUS)      as IEventBus

	_ent_skill          = deps.get_optional(ServiceKeys.SKILL_SYSTEM)         as SkillSystem
	_ent_inventory      = deps.get_optional(ServiceKeys.INVENTORY)             as InventorySystem
	_ent_bank           = deps.get_optional(ServiceKeys.BANK)                  as BankService
	_ent_stat_mod       = deps.get_optional(ServiceKeys.STAT_MODIFIERS)        as StatModifierService
	_ent_combat         = deps.get_optional(ServiceKeys.COMBAT)                as CombatSystem
	_ent_equipment      = deps.get_optional(ServiceKeys.EQUIPMENT)             as EquipmentService
	_ent_interact       = deps.get_optional(ServiceKeys.INTERACTION)  as InteractionExecutor
	_ent_player_states  = deps.get_optional(ServiceKeys.PLAYER_STATES)         as PlayerStateService
	_ent_data           = deps.get_optional(ServiceKeys.DATA)                  as DataService
	_ent_currency       = deps.get_optional(ServiceKeys.CURRENCY)              as CurrencyService
	_ent_trade          = deps.get_optional(ServiceKeys.TRADE)                 as TradeService
	_ent_pvp_death_loss = deps.get_optional(ServiceKeys.PVP_DEATH_LOSS)        as PvPDeathLossService
	_ent_aura           = deps.get_optional(ServiceKeys.AURA)                  as AuraService
	_ent_death_loot     = deps.get_optional(ServiceKeys.DEATH_LOOT)            as DeathLootService
	# ADR-037: DeathLootService braucht WorldService zum Gravestone-Spawnen,
	# kann es aber nicht als eigene Dep deklarieren (Bootstrap-Zyklus — siehe
	# DeathLootService.gd Klassenkommentar). Stattdessen direkte Injection
	# hier, unmittelbar nachdem beide Seiten (self als WorldService,
	# _ent_death_loot als aufgelöste Dep) existieren.
	if is_instance_valid(_ent_death_loot):
		_ent_death_loot.inject_world(self)
	_ent_pickpocket     = deps.get_optional(ServiceKeys.PICKPOCKET)          as PickpocketService
	# Für TouchInput.inject_settings() (EntityContext.get_settings()) — feste
	# Joystick-Position/-Modus. Rein client-lokale UI-Präferenz, siehe
	# SettingsService-Klassenkommentar; optional wie jede andere Entity-Dep hier
	# (Server-/Test-Kontexte ohne SettingsService bleiben unverändert lauffähig).
	_ent_settings       = deps.get_optional(ServiceKeys.SETTINGS_SERVICE)    as SettingsService
	# ADR-020: opportunistisch — in Produktion kommt NetworkBridge erst über
	# inject_network_bridge() (Phase C8, siehe dort für den Zyklus-Grund),
	# aber falls ein Test/Kontext sie bereits hier bereitstellt, nicht ignorieren.
	_network            = deps.get_optional(ServiceKeys.NETWORK_BRIDGE)        as NetworkBridge
	_zone_service       = deps.get_optional(ServiceKeys.ZONE_SERVICE)          as ZoneService

	data      = WorldData.new()
	factory   = WorldFactory.new()
	factory3d = Factory3D.new()
	_time     = WorldTimeService.new()
	_time.set_event_bus(_bus)
	_weather  = WeatherService.new()
	_weather.set_event_bus(_bus)

	_entity_orchestrator      = EntityOrchestrator.new()
	_entity_orchestrator.name = "EntityOrchestrator"
	add_child(_entity_orchestrator)
	_entity_orchestrator.set_event_bus(_bus)
	WorldEntityRegistry.register_all(_entity_orchestrator)
	# factory3d stammt aus WorldService selbst (World-intern, kein dep nötig).
	# respawn, player_states, data (DataService) kommen aus den oben aufgelösten Deps.
	_entity_orchestrator.set_entity_services(
		_ent_skill, _ent_inventory, factory3d,
		_respawn, _ent_data, _ent_stat_mod,
		_ent_combat, _ent_equipment, self,
		_ent_interact, _ent_player_states, _network, _ent_currency, _ent_trade,
		_ent_pvp_death_loss, _ent_aura, _ent_death_loot, _ent_pickpocket,
		_ent_settings, _ambient_spawner, _ent_quest
	)
	_save_handler = WorldSaveHandler.new(data, _time, _weather)

	if is_instance_valid(_save_system):
		# C-02 (Round 68): nur die Autorität persistiert world_state — dieselbe
		# Guard-Konvention wie InventorySystem/SkillSystem/QuestService/
		# EquipmentService (deren on_*_confirmed()-Methoden ebenfalls nur auf der
		# Autorität schreiben). world_state (Bäume/Erze/Tageszeit/Pets) ist
		# geteilter Weltzustand, den ein beitretender Client nie besitzt — ihn
		# trotzdem unter dem eigenen player_id-Save mitzuschreiben würde beim
		# nächsten Solo-Start dieses Spielers eine Welt wiederbeleben, die ihm nie
		# gehörte. `not is_instance_valid(_network)` zählt bewusst als Autorität
		# (derselbe Default wie überall sonst in dieser Klasse, z. B.
		# request_entity_interaction()) — NetworkBridge kann an diesem Punkt in
		# configure() noch nicht injiziert sein (Late-Inject, s. inject_network_bridge()
		# unten); Tier 1 (Solo) bleibt so unverändert: register+restore wie bisher.
		if not is_instance_valid(_network) or _network.is_server():
			_save_system.register_save_provider(self)
		# restore_world() bleibt UNCONDITIONAL: auch ein nicht-autoritativer Client
		# braucht einen lokalen Startzustand, bevor der Server-Sync
		# (SaveSystem.apply_remote_state(), NetworkBridge._rpc_receive_initial_state())
		# eintrifft — der wird danach ohnehin überschrieben, s. dort.
		var saved := _save_system.get_state_for(SAVE_KEY)
		if not saved.is_empty():
			_save_handler.restore_world(saved)
			# day_time and day_count are now computed properties — no copy needed

	# world_seed muss stehen, bevor on_world_scene_ready() das TerrainField anlegt — alle
	# Chunks, Spawner und das Bauen leiten ihre Höhen aus genau diesem Seed ab.
	# Muss NACH restore_world() laufen: sonst ist data.world_seed hier immer noch
	# 0 (frische WorldData), ein gespeicherter Seed würde nie ankommen und jede
	# geladene Welt bekäme statt des persistierten Seeds einen neuen Zufallsseed.
	#
	# BUGFIX (2026-09-14, "zwei Welten"): vorher wurde hier bei einer frischen
	# WorldData (world_seed == 0) IMMER aus der lokalen Systemzeit neu gewürfelt
	# — Host und Client generierten dadurch unabhängig voneinander ein komplett
	# anderes Terrain/Layout, obwohl sie verbunden waren (Server hat nie einen
	# Seed an den Client übertragen). SessionManager reserviert den Seed jetzt
	# beim Hosten und schickt ihn per Join-Handshake mit — hier zuerst danach
	# fragen, bevor lokal neu gewürfelt wird. Tier 1 (Solo) unverändert: dort
	# liefert get_world_seed() 0, also greift weiterhin der Zeit-Fallback.
	if data.world_seed == 0 and is_instance_valid(_session_manager):
		var network_seed := _session_manager.get_world_seed()
		if network_seed != 0:
			data.world_seed = network_seed
			AppLogger.log_info(
				"world_seed von SessionManager übernommen (Netzwerk-Sync): %d." % network_seed,
				LOG_CAT
			)
	# WorldSeedUtil.resolve() (Wunsch "ist world_seed vielleicht immer 0?"): einzige Quelle für
	# die Zeit-Fallback-Formel, siehe dortiger Klassenkommentar — vorher hier dupliziert.
	data.world_seed = WorldSeedUtil.resolve(data.world_seed)

	# ADR-041: erster Wetterwurf für den aktuellen (ggf. wiederhergestellten)
	# day_count — muss NACH data.world_seed final gesetzt UND NACH
	# _weather.restore() (innerhalb restore_world() oben) laufen, sonst würde
	# ein geladenes _last_rolled_day den Wurf für Tag 1 fälschlich überspringen
	# oder ein noch-0-Seed einen anderen Wurf als beim nächsten Boot ergeben.
	_weather.roll_for_day(_time.day_count, data.world_seed)

	if not is_instance_valid(_world_gen):
		AppLogger.log_warn("WorldGenerationService fehlt.", LOG_CAT)

	AppLogger.log_info("WorldService konfiguriert.", LOG_CAT)

## Phase S8.6 Late-Inject — NetworkBridge wird nach vollem Session-Boot injiziert
## um den zirkulären Dep (NetworkBridge ↔ WorldService) aufzulösen (ADR-020,
## identisches Muster zu Inventory/Quest/SkillSystem/Equipment).
## ADR-021 (R-5): reicht zusätzlich an EntityOrchestrator weiter, damit ab jetzt
## gespawnte Entities (QuestNPC, QuestCustomTrigger) get_network_bridge() im
## EntityContext bekommen — vorher war _entity_network_bridge in Produktion
## bei set_entity_services() (Phase 4) noch null (siehe dortiger Kommentar).
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	if is_instance_valid(_entity_orchestrator):
		_entity_orchestrator.set_network_bridge(network)
	# ADR-030: zone_triggers, die bereits vor diesem Late-Inject in der Gruppe
	# stehen (z.B. on_ready() lief schon), bekommen den NetworkBridge hier
	# nachgereicht — _wire_zone_triggers() in on_ready() lief zu diesem
	# Zeitpunkt noch ohne _network.
	for trigger in get_tree().get_nodes_in_group("zone_triggers"):
		if trigger is ZoneTriggerVolume:
			trigger.inject_network_bridge(network)
	# BUGFIX (2026-09-15, "Sterben soll auch synced werden"): erst hier
	# verfügbar (Late-Inject, siehe Klassenkommentar oben) — Gegenstück zu
	# EnemyNPC._die()'s broadcast_to_all_peers("entity_despawned", …).
	if is_instance_valid(network):
		network.broadcast_event_received.connect(_on_broadcast_event_received)

func on_ready() -> void:
	if is_instance_valid(_ticker):
		_ticker.register_service(self)

	if is_instance_valid(_bus):
		_bus.world().entity_despawn_requested.connect(_on_entity_despawn_requested)
		_bus.world().terrain_edit_requested.connect(_on_terrain_edit_requested)
		_bus.world().grass_cut_requested.connect(_on_grass_cut_requested)
		_bus.world().terrain_plane_requested.connect(_on_terrain_plane_requested)
		_bus.world().build_place_requested.connect(_on_build_place_requested)
		_bus.world().ladder_place_requested.connect(_on_ladder_place_requested)
		_bus.world().ladder_remove_requested.connect(_on_ladder_remove_requested)
		_bus.world().build_remove_requested.connect(_on_build_remove_requested)
		_bus.world().build_house_place_requested.connect(_on_build_house_place_requested)
		_bus.persistence().save_pre_flush.connect(_on_save_pre_flush)
		# ADR-018-Rest: SessionManager emittiert peer_cleanup_requested nur noch
		# über EventBus.networking() — kein direkter Connect auf die Service-
		# Instanz mehr (war der letzte Locator-artige Direkt-Connect zwischen
		# zwei Services, siehe SessionManager.gd Klassenkommentar).
		_bus.networking().peer_cleanup_requested.connect(_on_peer_cleanup_requested)
	else:
		AppLogger.log_warn("EventBus fehlt — Despawn-/Save-Flush-/Peer-Cleanup-Signale nicht verbunden.", LOG_CAT)

	_wire_zone_triggers()

	var respawn := _respawn
	if is_instance_valid(respawn):
		# Bäume — aufsteigend nach Fäll-Schwierigkeit / XP
		respawn.register_config("willow_tree", 180.0)  # 3 min — schnell (15 XP)
		respawn.register_config("oak_tree",    300.0)  # 5 min — standard (25 XP)
		respawn.register_config("maple_tree",  480.0)  # 8 min — langsam (60 XP)
		# Förster-Wunsch ("für alle Baumarten ausbauen"): pine_tree respawnte bis
		# hierhin nie (kein register_config()) — fiel bisher nicht auf, weil
		# Tannen ausschließlich im Winter-Biom vorkamen. Jetzt relevant, weil
		# ein per Försterei gepflanzter Tannen-Setzling denselben natürlichen
		# pine_tree-Typ spawnt (siehe FarmPlot._spawn_grown_tree()) — ohne
		# Respawn-Config würde jede gepflanzte Tanne nach dem Fällen für immer
		# verschwinden, alle anderen Baumarten aber respawnen.
		respawn.register_config("pine_tree",   300.0)  # 5 min — wie Eiche (25 XP)
		# Erze — aufsteigend nach Mining-Level
		respawn.register_config("copper_ore",  420.0)  # 7 min — Einsteiger (20 XP)
		respawn.register_config("iron_ore",    600.0)  # 10 min — fortgeschritten (40 XP)
		# Hain-Skills — ohne register_config() wäre jede Interaktion einmalig (der Skill hätte
		# nach den paar Objekten der Welt keine XP-Quelle mehr, siehe RespawnService._on_entity_despawned).
		# Zeiten nach XP/Seltenheit gestaffelt, analog zu Bäumen/Erzen oben.
		respawn.register_config("wild_beehive",  360.0)  # 6 min  — Imkerei (25 XP)
		respawn.register_config("charcoal_kiln", 360.0)  # 6 min  — Köhlerei (20 XP)
		# Nester (Insektenkunde/Graben) — Respawn nach XP gestaffelt, siehe docs/nests.md.
		respawn.register_config("mole_hill",     240.0)  # 4 min  — Graben (15 XP)
		respawn.register_config("ant_hill",      360.0)  # 6 min  — Insektenkunde (20 XP)
		respawn.register_config("termite_mound", 420.0)  # 7 min  — Insektenkunde (25 XP)
		respawn.register_config("wasp_nest",     420.0)  # 7 min  — Insektenkunde (25 XP)
		respawn.register_config("hornet_nest",   540.0)  # 9 min  — Insektenkunde (35 XP)
		respawn.register_config("sulfur_crust",  420.0)  # 7 min  — Alchemie (20 XP)
		respawn.register_config("fulgurite",     600.0)  # 10 min — Sturmkunde (30 XP)
		# Kräuter/wilde Blumen (herbalism/gardening): schnell nachwachsend, siehe WildPlant.PLANT_RESPAWN_SEC
		for plant_id: String in PlantCatalog.wild_ids():
			respawn.register_config(PlantCatalog.entity_type(plant_id), WildPlant.PLANT_RESPAWN_SEC)
		# Sträucher (Pflücken/Roden): siehe BushCatalog.RESPAWN_SEC
		for bush_id: String in BushCatalog.ids():
			respawn.register_config(BushCatalog.entity_type(bush_id), BushCatalog.RESPAWN_SEC)
		respawn.register_config("meteorite",     900.0)  # 15 min — Sternkunde (40 XP), selten
		# BUGFIX (2026-09-20, "Gegner respawnen nicht"): fehlte komplett — ohne
		# eine register_config()-Zeile pro Gegnertyp bricht
		# RespawnService._on_entity_despawned() sofort ab
		# ("if not _configs.has(type_id): return"), der besiegte Gegner wurde
		# also nie in die Respawn-Queue eingereiht. type_ids müssen exakt
		# WorldEntityRegistry.KNOWN_ENEMY_TYPES entsprechen.
		respawn.register_config("goblin",      240.0)  # 4 min
		respawn.register_config("skeleton",    300.0)  # 5 min
		respawn.set_spawn_callback(func(t: String, p: Vector3, pid: int = 1) -> Node3D: return _respawn_spawn(t, p, pid))
		respawn.set_remove_callback(func(t: String, p: Vector3) -> void: data.unmark_harvested(t, p))

	# Wunsch "zu wenig Gegner spawnen, Friedhöfe als Skelett-Spawner": siehe
	# AmbientSpawnService-Klassenkommentar für die Abgrenzung zu 'respawn'
	# oben — hier KEINE type_id→cooldown-Configs nötig (kein register_config()-
	# Aufruf), der Dienst ist rein punktbasiert über register_point().
	if is_instance_valid(_ambient_spawner):
		_ambient_spawner.set_spawn_callback(func(t: String, p: Vector3) -> Node3D: return spawn_entity(t, p))

	# Wunsch "Special Bedingungen" (nur bei bestimmtem Wetter/Biom/Nacht):
	# siehe ConditionalEncounterService-Klassenkommentar für die Abgrenzung
	# zu 'ambient_spawner' direkt darüber. _terrain für Höhe/Biom direkt
	# übergeben (kein ServiceNode, siehe dortiger Kommentar "kein 'world'-
	# Dep" — reines Datenobjekt, kein zirkulärer DI-Graph).
	if is_instance_valid(_conditional_encounters):
		_conditional_encounters.set_callbacks(
			func(t: String, p: Vector3) -> Node3D: return spawn_entity(t, p),
			func(x: float, z: float) -> String: return _terrain.get_biome_id_at(x, z) if is_instance_valid(_terrain) else "",
			func(x: float, z: float) -> float: return _terrain.get_height_at(x, z) if is_instance_valid(_terrain) else 0.0,
			func() -> String: return current_weather,
			func() -> bool: return _time.is_night() if is_instance_valid(_time) else false
		)

	# Wunsch "spawning optimieren, despawnen nicht korrekt": siehe
	# EnemyCullingService-Klassenkommentar — räumt Gegner auf, die weder
	# ChunkEntitySpawner noch sonst irgendwer je wieder abräumen würde.
	# unload_entity() direkt gebunden (kein Lambda-Wrapper nötig, Signatur
	# passt 1:1) — bewusst NICHT despawn_entity(): kein RespawnService-
	# Respawn für etwas, das gerade WEIL es unbeobachtet ist aufgeräumt wird.
	if is_instance_valid(_enemy_culling) and is_instance_valid(_entity_orchestrator):
		_enemy_culling.set_unload_callback(_entity_orchestrator.unload_entity)

	AppLogger.log_info("WorldService bereit.", LOG_CAT)

## Warms up the MeshCache inside factory3d.
## Called by ServiceOrchestrator Phase S8.8 — encapsulates factory3d internals
## so the orchestrator never touches WorldService fields directly.
func warmup_mesh_cache() -> void:
	if not is_instance_valid(factory3d):
		AppLogger.log_warn("warmup_mesh_cache: factory3d nicht verfügbar — übersprungen.", LOG_CAT)
		return
	if factory3d.cache == null:
		factory3d.cache = MeshCache.new()
	factory3d.cache.build()
	AppLogger.log_info("MeshCache gebaut.", LOG_CAT)

func on_cleanup() -> void:
	if is_instance_valid(_bus):
		if _bus.world().terrain_edit_requested.is_connected(_on_terrain_edit_requested):
			_bus.world().terrain_edit_requested.disconnect(_on_terrain_edit_requested)
		if _bus.world().grass_cut_requested.is_connected(_on_grass_cut_requested):
			_bus.world().grass_cut_requested.disconnect(_on_grass_cut_requested)
		if _bus.world().terrain_plane_requested.is_connected(_on_terrain_plane_requested):
			_bus.world().terrain_plane_requested.disconnect(_on_terrain_plane_requested)
		if _bus.world().ladder_place_requested.is_connected(_on_ladder_place_requested):
			_bus.world().ladder_place_requested.disconnect(_on_ladder_place_requested)
		if _bus.world().ladder_remove_requested.is_connected(_on_ladder_remove_requested):
			_bus.world().ladder_remove_requested.disconnect(_on_ladder_remove_requested)
		if _bus.world().build_place_requested.is_connected(_on_build_place_requested):
			_bus.world().build_place_requested.disconnect(_on_build_place_requested)
		if _bus.world().build_remove_requested.is_connected(_on_build_remove_requested):
			_bus.world().build_remove_requested.disconnect(_on_build_remove_requested)
		if _bus.world().build_house_place_requested.is_connected(_on_build_house_place_requested):
			_bus.world().build_house_place_requested.disconnect(_on_build_house_place_requested)
		if _bus.persistence().save_pre_flush.is_connected(_on_save_pre_flush):
			_bus.persistence().save_pre_flush.disconnect(_on_save_pre_flush)
		# G-03: Peer-Cleanup-Signal trennen (jetzt über EventBus, siehe on_ready()).
		if _bus.networking().peer_cleanup_requested.is_connected(_on_peer_cleanup_requested):
			_bus.networking().peer_cleanup_requested.disconnect(_on_peer_cleanup_requested)
	if is_instance_valid(_chunk_manager):
		_chunk_manager.queue_free()
		_chunk_manager = null
	if is_instance_valid(_weather_vfx):
		# weather_changed-Connect löst sich automatisch (Godot trennt Signale
		# zu freigegebenen Objekten selbst) — kein manuelles disconnect nötig.
		_weather_vfx.queue_free()
		_weather_vfx = null
	if is_instance_valid(_ambient_forest_vfx):
		_ambient_forest_vfx.queue_free()
		_ambient_forest_vfx = null
	if is_instance_valid(_day_night_cycle):
		# setting_changed-Connect löst sich automatisch, wie oben bei
		# weather_changed — kein manuelles disconnect nötig.
		_day_night_cycle.queue_free()
		_day_night_cycle = null
	if is_instance_valid(_entity_orchestrator) and _entity_orchestrator.get_entity_count() > 0:
		_entity_orchestrator.on_world_unloaded()

func on_tick(delta: float) -> void:
	if is_instance_valid(_game_manager) and _game_manager.is_playing():
		var day_before := _time.day_count
		_time.tick(delta)
		# day_time / day_count are computed properties — no copy needed
		if _time.day_count != day_before and is_instance_valid(_weather):
			var weather_before := _weather.current_weather
			_weather.roll_for_day(_time.day_count, data.world_seed)
			# Rein lokale Anzeige (wie QuestCustomTrigger.hint_text, Round 73) —
			# jeder Peer zeigt seinen eigenen deterministischen Wurf, kein
			# zusätzlicher Netzwerk-Pfad nötig (siehe WeatherService-Kommentar).
			# Nur bei tatsächlicher Änderung — WeatherService.roll_for_day() ist
			# ein No-Op, wenn der Wurf zufällig dasselbe Wetter ergibt.
			if is_instance_valid(_bus) and _weather.current_weather != weather_before:
				_bus.ui().emit_notification_requested("Das Wetter ändert sich: %s" % _weather.current_weather)

# ─────────────────────────────────────────────
# Welt-Initialisierung
# ─────────────────────────────────────────────

func on_world_scene_ready(world_root: Node3D) -> void:
	var t := AppLogger.log_begin("on_world_scene_ready()", LOG_CAT)

	if _entity_orchestrator.get_entity_count() > 0:
		_entity_orchestrator.on_world_unloaded()
		if is_instance_valid(_bus):
			_bus.world().emit_world_scene_unloaded()

	# Statische Geometrie
	var generated := factory.create_world()
	for child in generated.get_children():
		generated.remove_child(child)
		world_root.add_child(child)
	generated.queue_free()

	# Referenzen für WeatherVfx (Nebel/Sonnenhelligkeit je Wetter, siehe dortigen
	# Klassenkommentar) — beide Nodes kommen unverändert aus
	# WorldFactory._add_environment() mit, nur hier einmal nachgeschlagen statt
	# den ganzen Baum bei jedem Wetterwechsel erneut zu durchsuchen.
	var world_environment_node := world_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_world_environment = world_environment_node.environment if is_instance_valid(world_environment_node) else null
	_sun_light = world_root.get_node_or_null("Sun") as DirectionalLight3D

	# Gelände: EINE Wahrheit für Höhe/Wasser/Klima — vor allem anlegen, was Höhen braucht
	# (Zonen, Spawner, Chunks, Bauen). data.world_seed ist seit configure() gesetzt und
	# zwischen Peers synchronisiert; data.terrain_edits ist die (ggf. geladene) Schicht der
	# Spieler-Änderungen — dieselbe Instanz, die WorldSaveHandler speichert.
	# BUGFIX (Wunsch "ist world_seed vielleicht immer 0?"): dieser Zweig LOGGTE bisher nur eine
	# Warnung ("nutzt den Default-Seed") und übergab TerrainField danach trotzdem weiterhin die
	# rohe 0 — reiner Logging-Bug, kein tatsächlicher Fallback (data.world_seed blieb 0). Sollte
	# dieser Fall dank configure() (siehe dortiger WorldSeedUtil.resolve()-Aufruf, läuft vor
	# on_world_scene_ready(), siehe Kommentar oben "world_seed muss stehen, bevor...") ohnehin
	# nie eintreten, ist dies hier das letzte Sicherheitsnetz — und jetzt eines, das wirklich
	# greift: schreibt denselben, von WorldSeedUtil aufgelösten Wert tatsächlich zurück.
	if data.world_seed == 0:
		data.world_seed = WorldSeedUtil.resolve(data.world_seed)
		AppLogger.log_warn(
			"world_seed war an dieser Stelle noch 0 — WorldService.configure() hätte das vorher auflösen müssen. Neu aufgelöst: %d." % data.world_seed,
			LOG_CAT
		)
	_terrain = TerrainField.new(TerrainConfig.new(), data.world_seed)
	# Umbauten (Graben/Bauen) sind vorerst SOLO-ONLY: ohne Replikation würden Host und Clients
	# unterschiedliche Welten sehen. In einer Mehrspieler-Sitzung bleibt die Edit-Schicht daher
	# unangewendet (die Daten bleiben im Spielstand erhalten), siehe _edits_enabled().
	_edits_active = _is_solo_session()
	if _edits_active:
		_terrain.set_edit_layer(data.terrain_edits)
		_terrain.set_material_layer(data.terrain_materials)

	# Round 74: PvP-Zone "im Wüsten-Biom" (Anfrage) — sucht zur Laufzeit die
	# erste Wüsten-Koordinate über TerrainField.get_biome_id_at() statt
	# einer geratenen Fixkoordinate (Biome sind prozedural, siehe
	# DesertPvpZonePlacer-Klassenkommentar). Läuft auf JEDEM Peer (kein
	# is_server()-Guard nötig) — der world_seed ist synchronisiert, also liefert die
	# Funktion überall denselben Ort. _zone_service/_network können hier noch null sein (Late-
	# Inject S8.6 für _network kommt erst danach) — place() injiziert direkt,
	# unabhängig von der "zone_triggers"-Gruppen-Nachreichung.
	DesertPvpZonePlacer.place(world_root, _terrain, _zone_service, _network)

	# ADR-032: Safe-Zone um den Spawnpunkt — ohne mindestens eine "safe"-
	# getaggte Zone ist das Safe-Zone-Vulnerabilitäts-Fenster (PvPService)
	# komplett inert (nichts zum Betreten). Gleicher Aufrufkontext/Timing
	# wie DesertPvpZonePlacer direkt darüber.
	SpawnSafeZonePlacer.place(world_root, _terrain, _zone_service, _network)

	# Terrain-Höhen-Callback: wird jetzt direkt an generate_world()/generate_world_async()
	# übergeben — kein persistentes set_height_callback() mehr (Architekturplan 1.5).

	_entity_orchestrator.initialize(world_root)

	# ChunkManager: stored on the service so on_cleanup() can shut it down properly.
	# Deterministic seed: read from WorldData so every session, server and client
	# generate the same world. Set once at world creation, never from the clock.
	if is_instance_valid(_chunk_manager):
		_chunk_manager.queue_free()
	_chunk_manager = ChunkManager.new()
	_chunk_manager.name = "ChunkManager"
	world_root.add_child(_chunk_manager)
	# Graben/Bauen: Handler + Chunk-Hooks VOR initialize() — der Spawn-Chunk wird dort
	# synchron geladen und soll schon gemeldet werden (Bauteile seiner Fläche erscheinen).
	_setup_world_editing()
	_chunk_manager.initialize(
		world_root, _terrain,
		func(type_id: String, pos: Vector3, pid: int = 1) -> Node3D: return spawn_entity(type_id, pos, {}, pid),
		_unload_entity_node, _is_object_harvested
	)

	# BUG-FIX: ChunkManager wurde nie beim ServiceTicker registriert und
	# WorldService.on_tick() ruft _chunk_manager.on_tick() auch nicht auf —
	# _sync_chunks() lief dadurch NIE, außer dem Spawn-Chunk wurde kein
	# einziger Chunk je geladen (auch keine Chunk-Bäume/-Tiere).
	if is_instance_valid(_ticker):
		_ticker.register_service(_chunk_manager)

	# WorldSpawner mit aktuellen Referenzen neu erstellen
	_spawner = WorldSpawner.new(
		_entity_orchestrator,
		_terrain,
		_world_gen,
		data,
		func(pos: Vector3, pid: int) -> Node3D:
			# BUGFIX (2026-09-16, "Charakter-Wechsel → Crash beim anderen Peer"):
			# player_id (Charakter-UUID) statt bloßer peer_id für die
			# Namensvergabe durchreichen — siehe EntityOrchestrator.spawn_entity().
			var pid_str := _save_system.get_active_player_id() if is_instance_valid(_save_system) else ""
			return spawn_entity("player", pos, {spawn_position = pos, player_id = pid_str}, pid)
	)
	var local_peer: int = _session_manager.get_local_peer_id() \
		if is_instance_valid(_session_manager) else 1
	# ADR-015: EntityOrchestrator braucht dies für jeden EntityContext, nicht
	# nur für den einen spawn_entity("player", ...)-Aufruf unten.
	_entity_orchestrator.set_local_peer_id(local_peer)
	# ADR-015: EntityOrchestrator braucht dies für jeden EntityContext, nicht
	# nur für den lokalen Player-Spawn unten — sonst bleibt ctx.get_local_peer_id()
	# für alle nicht-Player-Entities beim Default 1 stehen.
	_entity_orchestrator.set_local_peer_id(local_peer)

	# F-1: MultiplayerSpawner — repliziert vom Server gespawnte Entities an alle Clients.
	# Muss vor spawn_all() eingerichtet sein damit der Spawner bereits aktiv ist wenn
	# die ersten Entities hinzugefügt werden.
	# Nur auf Server aufsetzen — Clients empfangen Spawn-Events automatisch.
	if is_instance_valid(_session_manager) and _session_manager.is_server() \
			and _session_manager.has_active_peer():
		_setup_multiplayer_spawner(world_root)

	# ADR-010 Round 55: Tier 3 (Dedizierter Server) spawnt kein Player-Entity
	# für den Host-Prozess selbst — der Host ist dort reine Autorität, kein
	# spielender Client. Tier 1/2 unverändert (spawn_local_player bleibt true).
	var spawn_local_player := not (
		is_instance_valid(_session_manager) and _session_manager.is_dedicated_server()
	)
	await _spawner.spawn_all(world_root, local_peer, spawn_local_player)

	# BUGFIX (2026-09-14, "zwei Welten" Teil 2): world_seed sorgt jetzt für
	# identisches Terrain — aber ohne diesen Schritt spawnt jeder Peer weiterhin
	# nur sein EIGENES Player-Entity (siehe spawn_all()/_spawn_player_cb oben)
	# und niemand erfährt je vom Player-Entity eines ANDEREN Peers. Server und
	# Client melden ihr frisch gespawntes lokales Player-Entity daher hier an
	# NetworkBridge — die Autorität registriert es und informiert alle bereits
	# aktiven Peers gegenseitig (siehe NetworkBridge.report_local_player_spawned()).
	# Tier 1 (Solo) und Tier 3 (Host ohne eigenes Player-Entity): no-op dort.
	if spawn_local_player and is_instance_valid(_network):
		var local_player_node := get_player_by_id(local_peer)
		if is_instance_valid(local_player_node):
			_network.report_local_player_spawned(local_player_node.global_position)
		else:
			AppLogger.log_warn(
				"Lokales Player-Entity nach spawn_all() nicht gefunden (peer %d) — Mitspieler-Sichtbarkeit für diesen Peer nicht gemeldet." % local_peer,
				LOG_CAT
			)

	# Wetter-Optik (ADR-041 "künftige Systeme können aufsetzen"): folgt dem
	# lokalen Spieler, hört auf _weather über weather_changed. Nur bei
	# spawn_local_player — auf einem kopflosen dedizierten Server (Tier 3)
	# gibt es weder einen Spieler zum Folgen noch etwas zu rendern.
	if is_instance_valid(_weather_vfx):
		_weather_vfx.queue_free()
	_weather_vfx = WeatherVfx.new()
	_weather_vfx.name = "WeatherVfx"
	world_root.add_child(_weather_vfx)
	_weather_vfx.configure(_bus, data.world_seed, spawn_local_player, _world_environment)
	if spawn_local_player:
		var vfx_target := get_player_by_id(local_peer)
		if is_instance_valid(vfx_target):
			_weather_vfx.follow(vfx_target)
	if is_instance_valid(_weather):
		_weather_vfx.set_weather(_weather.current_weather)

	# Ambient-Waldoptik (siehe AmbientForestVfx-Klassenkommentar): treibendes
	# Laub, rein biomabhängig statt wettergesteuert. Gleiches
	# spawn_local_player-Gate wie _weather_vfx — dedizierter Server (Tier 3)
	# hat weder einen Spieler zum Folgen noch etwas zu rendern.
	if is_instance_valid(_ambient_forest_vfx):
		_ambient_forest_vfx.queue_free()
	_ambient_forest_vfx = AmbientForestVfx.new()
	_ambient_forest_vfx.name = "AmbientForestVfx"
	world_root.add_child(_ambient_forest_vfx)
	_ambient_forest_vfx.configure(
		data.world_seed, _terrain, spawn_local_player, _time,
		_network, _network.get_player_id_for_peer(local_peer) if is_instance_valid(_network) else ""
	)
	if spawn_local_player:
		var forest_vfx_target := get_player_by_id(local_peer)
		if is_instance_valid(forest_vfx_target):
			_ambient_forest_vfx.follow(forest_vfx_target)

	# Tag/Nacht (siehe DayNightCycle-Klassenkommentar): braucht KEIN follow()
	# (Sonne hängt nicht am Spieler) — läuft trotzdem nur bei spawn_local_player,
	# ein dedizierter Server hat nichts zu rendern, das von Sonnenstand/
	# Himmelsfarbe profitieren würde. Nach _weather_vfx verdrahtet, weil sie
	# dessen get_sun_factor() braucht (siehe dortigen Kommentar zu "ein
	# Schreiber pro Property").
	if is_instance_valid(_day_night_cycle):
		_day_night_cycle.queue_free()
	_day_night_cycle = DayNightCycle.new()
	_day_night_cycle.name = "DayNightCycle"
	world_root.add_child(_day_night_cycle)
	_day_night_cycle.configure(
		_time, _sun_light, _world_environment, _weather_vfx, _ent_settings, spawn_local_player
	)

	if is_instance_valid(_bus):
		_bus.world().emit_world_scene_ready(world_root)

	AppLogger.log_end("on_world_scene_ready()", t, LOG_CAT)
	AppLogger.log_info("Welt bereit. Entities: %d." % _entity_orchestrator.get_entity_count(), LOG_CAT)

# ─────────────────────────────────────────────
# Gelände & Bauen (Umgraben, Wände, Böden)
# ─────────────────────────────────────────────
##
## ARCHITEKTUR: UI/Entities emittieren nur Wünsche über den EventBus (terrain_edit_requested,
## build_place_requested, build_remove_requested). Hier laufen ALLE Prüfungen zusammen
## (Solo-Guard, Reichweite, Material, Regeln); die Logik selbst steckt in den testbaren
## Hilfsklassen WorldTerrainEditor/WorldBuildHandler. Höhen kommen aus dem TerrainField —
## keine Physik-Raycasts.
##
## SOLO-ONLY (vorerst): Ohne Replikation würden Host und Clients verschiedene Welten sehen.
## In Mehrspieler-Sitzungen sind Umbauten deshalb ausgeschaltet (und unsichtbar), der Spielstand
## behält die Daten. Erweiterungspunkt für Koop: hier ein Broadcast der Records/Deltas
## (NetworkBridge.broadcast_to_all_peers) + Snapshot beim Beitritt.

const ITEM_DIRT: String = "dirt"
const TOOL_SHOVEL: String = "tool_shovel"
## Bodenmaterial-System (2026-09-26, "natürlich Erde/Sand je nach Biom +
## Kiesschicht, Sand bleibt Sand"): welches Item beim Aufschütten verbraucht
## wird, wenn der Aufrufer kein material_id explizit vorgibt (siehe
## request_terrain_edit()) — Prioritätsreihenfolge, erstes Item mit
## Bestand ≥1 gewinnt. Bewusst konservativ: Erde zuletzt, damit ein Spieler,
## der extra Sand/Kies mitgebracht hat, den auch tatsächlich verbaut statt
## dass die generische Erde immer zuerst weggeht.
const FILL_MATERIAL_PRIORITY: Array[String] = ["sand", "gravel", "dirt"]
## XP pro erfolgreichem Grabvorgang (SkillDefinition "digging", data/skills/digging.tres).
## Grobe Kalibrierung an Mining (40 XP / 4s Interaktion ≈ 10 XP/s): Graben dauert
## GroundToolController.DURATION = 1.4s → 14 XP wären tempo-äquivalent, absichtlich etwas
## niedriger angesetzt (10), weil Graben anders als Erzabbau kein Werkzeug-Tier/Zielsuche
## braucht und sonst zu schnell zum höchsten Skill der Welt würde. Nur für MODE_DIG, nicht
## für MODE_FILL — Zuschütten ist kein Fortschritt in der Fähigkeit "Erde bearbeiten",
## sondern verbraucht nur wieder, was gegraben wurde.
const DIG_XP: int = 10

func get_terrain() -> TerrainField:
	return _terrain

## Bugfix 2026-09-27 ("bepflanzte Felder nicht persistent") — für FarmPlot.gd.
func get_farm_plots() -> FarmPlotRegistry:
	return data.farm_plots

## Für rein lokale Client-Optik-/Beobachtungs-Zwecke (z.B. SunGazeWatcher —
## "schaut die Kamera gerade Richtung Sonne?"), die die WorldFactory-Sonne
## selbst brauchen, nicht nur deren Wetter-/Tag-Nacht-Effekte. Dieselbe
## Node-Referenz, die DayNightCycle/WeatherVfx bereits intern nutzen (siehe
## on_world_scene_ready()) — kein zweiter Sonnenknoten, nur ein weiterer
## Leser.
func get_sun_light() -> DirectionalLight3D:
	return _sun_light

## Admin/Debug (siehe AdminMenuCommands._cmd_weather()): direktes Setzen des
## Wetters, unabhängig vom deterministischen Tages-Wurf — siehe
## WeatherService.force_weather()-Kommentar für Scope/Grenzen (nicht
## netzwerksynchronisiert, nur für lokalen Solo/Host-Admin-Gebrauch gedacht).
## false = unbekannter Wetter-Typ ODER _weather (noch) nicht verfügbar
## (z.B. Welt noch nicht fertig geladen). Zum LESEN des aktuellen Wetters
## gibt es bereits die current_weather-Property oben — kein zweiter Getter
## nötig, nur dieser Setter ist neu.
func admin_set_weather(new_weather: String) -> bool:
	if not is_instance_valid(_weather):
		return false
	return _weather.force_weather(new_weather)

## Für die Fehlermeldung/Anzeige im Admin-Menü — dieselbe Liste, die
## WeatherService intern für den Tages-Wurf benutzt.
func admin_get_weather_types() -> Array[String]:
	return WeatherService.WEATHER_TYPES

## Admin/Debug (siehe AdminMenuCommands._cmd_time()): setzt die Tageszeit
## direkt, unabhängig vom normalen kontinuierlichen Ablauf (WorldTimeService.
## tick()). fposmod() statt fmod() — eine negative Stunde (z.B. aus einem
## Tippfehler) soll sinnvoll auf [0, 24) umlaufen statt einen negativen
## day_time zu erzeugen (fmod() in GDScript kann negativ bleiben, fposmod()
## nicht). false = _time (noch) nicht verfügbar (Welt noch nicht fertig
## geladen) — hour selbst wird nie als "ungültig" abgelehnt, jede
## Fließkommazahl ist ein gültiger Zeitpunkt.
func admin_set_time_of_day(hour: float) -> bool:
	if not is_instance_valid(_time):
		return false
	_time.day_time = fposmod(hour, 24.0)
	return true

## Admin/Debug (siehe AdminMenuCommands._cmd_tick()): setzt die
## Zeitgeschwindigkeit (Spielstunden pro Realsekunde) direkt — reines
## Debug-Werkzeug zum schnellen Durchspulen (Tag/Nacht-Wechsel, Wetter-
## Rollover, seit Kurzem auch Baum-Wachstumsstadien über Spieltage hinweg
## testen). Wie admin_set_weather(): nicht netzwerksynchronisiert, nur für
## lokalen Solo/Host-Admin-Gebrauch gedacht (siehe dortiger Kommentar).
## Negative Werte werden auf 0 geklemmt (Zeit anhalten) statt rückwärts
## laufen zu lassen — day_time < 0 wäre ein nie getesteter Zustand.
func admin_set_time_speed(speed: float) -> bool:
	if not is_instance_valid(_time):
		return false
	_time.time_speed = max(speed, 0.0)
	return true

## Für die Anzeige im Admin-Menü (aktuelle Geschwindigkeit vor dem Ändern).
func admin_get_time_speed() -> float:
	return _time.time_speed if is_instance_valid(_time) else WorldTimeService.DEFAULT_TIME_SPEED

## Vorschau für den Baumodus (Geist). Verändert nichts. Rückgabe siehe WorldBuildHandler.preview().
func preview_build(player_id: String, piece_id: String, target: Vector3, rot_steps: int, storey: int = 0) -> Dictionary:
	if not _edits_active or _build_handler == null:
		return {"ok": false, "reason": "coop_unsupported", "key": "", "y": 0.0, "yaw": 0.0,
			"center": Vector2.ZERO, "affordable": false, "storey": storey}
	return _build_handler.preview(player_id, piece_id, target, rot_steps, _player_position(player_id), storey)

## Vorschau für den Grab-/Füll-Geist (TerrainEditGhost, siehe GroundToolController) — analog
## preview_build(). Verändert nichts. Dieselbe Reichweiten-/Solo-Vorprüfung wie
## request_terrain_edit() (_edit_gate), damit der Geist z.B. schon rot wird, wenn ein Bauwerk
## im Weg ist, statt erst nach der fehlgeschlagenen Interaktion.
func preview_terrain_edit(player_id: String, mode: String, target: Vector3) -> Dictionary:
	var blocked: Dictionary = {"ok": false, "center": Vector2.ZERO,
		"radius": WorldTerrainEditor.BRUSH_RADIUS, "core_radius": WorldTerrainEditor.CORE_RADIUS}
	if not _edits_active or _terrain_editor == null:
		blocked["reason"] = "coop_unsupported"
		return blocked
	var gate: Dictionary = _edit_gate(player_id, target, WorldTerrainEditor.REACH)
	if not gate["ok"]:
		blocked["reason"] = gate["reason"]
		return blocked
	return _terrain_editor.preview(mode, target)

## Bugfix 2026-09-26 ("überall nur Erde", "Sand aus der Wüste im Wald ablegen
## und es bleibt Sand"): vorher IMMER ITEM_DIRT, egal in welchem Biom/wie tief
## gegraben wurde. Jetzt: Graben liefert das Material, das laut
## TerrainField.get_material_at() TATSÄCHLICH an dieser Stelle liegt (Override
## eines zuvor abgelegten Materials > Kies-Unterboden ab einer gewissen Tiefe >
## natürliches Oberflächenmaterial des Bioms) — abgefragt VOR der Höhenänderung,
## damit "was war hier, bevor ich es weggegraben habe" beantwortet wird, nicht
## "was liegt jetzt an der neuen, tieferen Stelle". Aufschütten verbraucht ein
## Material gemäß FILL_MATERIAL_PRIORITY (oder ein explizit vorgegebenes) und
## legt GENAU DAS an den betroffenen Gitterpunkten dauerhaft ab (Override) —
## das ist der Kern von "Sand bleibt Sand, auch fernab der Wüste".
func request_terrain_edit(player_id: String, mode: String, target: Vector3, material_id: String = "") -> Dictionary:
	var gate: Dictionary = _edit_gate(player_id, target, WorldTerrainEditor.REACH)
	if not gate["ok"]:
		return _notify_fail(gate)

	var center: Vector2 = TerrainEditLayer.lattice_to_world(TerrainEditLayer.world_to_lattice(target.x, target.z))

	if mode == WorldTerrainEditor.MODE_FILL:
		if material_id.is_empty():
			material_id = _resolve_fill_material(player_id)
		if material_id.is_empty() or (is_instance_valid(_ent_inventory) and not _ent_inventory.has_item(material_id, player_id, 1)):
			return _notify_fail({"ok": false, "reason": "no_material"})
	elif mode == WorldTerrainEditor.MODE_DIG:
		# VOR der Höhenänderung lesen (siehe Kommentar oben) — das ist das Material,
		# das der Spieler gleich tatsächlich ausgräbt.
		material_id = _terrain.get_material_at(center.x, center.y)
		if is_instance_valid(_ent_inventory) and not _can_carry(player_id, material_id):
			return _notify_fail({"ok": false, "reason": "inventory_full"})

	var result: Dictionary = _terrain_editor.edit(mode, target)
	if not result["ok"]:
		return _notify_fail(result)

	var changed: Array[Vector2i] = result.get("changed", [])
	var materials: TerrainMaterialLayer = _terrain.get_material_layer()
	if is_instance_valid(_ent_inventory):
		if mode == WorldTerrainEditor.MODE_DIG:
			_ent_inventory.request_add_item(material_id, player_id, 1)
			# Das Material an dieser Stelle ist jetzt weg — ein evtl. dort liegender
			# Override wird entfernt, damit erneutes Graben wieder die (jetzt tiefere)
			# natürliche Antwort liefert, statt das längst abgetragene Material erneut
			# zu liefern.
			if is_instance_valid(materials) and not changed.is_empty():
				materials.clear_overrides(changed)
		else:
			_ent_inventory.remove_item(material_id, player_id, 1)
			# Genau DAS abgelegte Material merken (Kern des Bugfixes) — dauerhaft,
			# über TerrainMaterialLayer/WorldSaveHandler gespeichert.
			if is_instance_valid(materials) and not changed.is_empty():
				materials.set_overrides(changed, material_id)
	if mode == WorldTerrainEditor.MODE_DIG and is_instance_valid(_ent_skill):
		_ent_skill.request_add_xp("digging", DIG_XP, player_id)
	_after_terrain_edit(mode, result)
	return result

## Welches Material beim Aufschütten verbraucht wird, wenn der Aufrufer keins
## explizit vorgibt — erstes Item aus FILL_MATERIAL_PRIORITY, von dem der
## Spieler mindestens 1 besitzt. "" wenn er von keinem der bekannten
## Bodenmaterialien etwas trägt.
func _resolve_fill_material(player_id: String) -> String:
	if not is_instance_valid(_ent_inventory):
		return ITEM_DIRT  # Ohne Inventar-Service (Tests) unverändertes Alt-Verhalten.
	for candidate in FILL_MATERIAL_PRIORITY:
		if _ent_inventory.has_item(candidate, player_id, 1):
			return candidate
	return ""

## Vorschau für den Ebnen-Geist (TerrainEditGhost, siehe GroundToolController) — analog
## preview_terrain_edit(), aber mit Ebene. Verändert nichts.
func preview_terrain_plane(player_id: String, target: Vector3, plane_y: float) -> Dictionary:
	var blocked: Dictionary = {"ok": false, "center": Vector2.ZERO,
		"radius": WorldTerrainEditor.BRUSH_RADIUS, "core_radius": WorldTerrainEditor.CORE_RADIUS}
	if not _edits_active or _terrain_editor == null:
		blocked["reason"] = "coop_unsupported"
		return blocked
	var gate: Dictionary = _edit_gate(player_id, target, WorldTerrainEditor.REACH)
	if not gate["ok"]:
		blocked["reason"] = gate["reason"]
		return blocked
	return _terrain_editor.preview_plane(target, plane_y)

## Ebnen: Gelände um `target` schrittweise auf die waagerechte Ebene plane_y ziehen
## (direction: TerrainPlanePlanner.DIR_*). Reichweite/Solo/Bauwerks-Sperre wie beim Graben.
##
## MATERIAL: Beim Ebnen wandert Erde INNERHALB der Fläche von hohen zu tiefen Stellen — nur der
## Überschuss/Fehlbetrag geht ins Inventar bzw. wird verbraucht. Verrechnet wird in der Einheit
## einer vollen normalen Grab-/Füllaktion (TerrainPlanePlanner.unit_volume): 1 Item pro Einheit,
## Ebnen ist also nie ergiebiger als Graben. Bruchteile merkt sich _plane_credit je Spieler
## (0 ≤ Guthaben < 1 Item; Fehlbeträge werden in ganzen Items im Voraus bezahlt, der Rest
## wandert ins Guthaben) — nur für diese Sitzung, ein Verlust beim Beenden ist < 1 Item.
func request_terrain_plane(
	player_id: String, target: Vector3, plane_y: float,
	direction: String = TerrainPlanePlanner.DIR_BOTH
) -> Dictionary:
	var gate: Dictionary = _edit_gate(player_id, target, WorldTerrainEditor.REACH)
	if not gate["ok"]:
		return _notify_fail(gate)
	if is_nan(plane_y):
		return _notify_fail({"ok": false, "reason": "no_plane"})

	var plan: Dictionary = _terrain_editor.plan_plane(target, plane_y, direction)
	if not plan["ok"]:
		return _notify_fail(plan)

	var center: Vector2 = plan["center"]
	var unit: float = TerrainPlanePlanner.unit_volume(
		WorldTerrainEditor.BRUSH_RADIUS, WorldTerrainEditor.CORE_RADIUS, WorldTerrainEditor.DIG_STEP_ABS)
	var total: float = float(_plane_credit.get(player_id, 0.0)) \
		+ (float(plan["lowered"]) - float(plan["raised"])) / unit
	var need: int = maxi(0, ceili(-total - 0.0001))
	var gain: int = maxi(0, floori(total + 0.0001))
	var has_inventory: bool = is_instance_valid(_ent_inventory)

	var dug_material: String = _terrain.get_material_at(center.x, center.y)   # VOR der Änderung
	var fill_material: String = dug_material
	if has_inventory:
		if need > 0:
			fill_material = _resolve_fill_material_count(player_id, need)
			if fill_material.is_empty():
				return _notify_fail({"ok": false, "reason": "no_material"})
		if gain > 0 and not _can_carry(player_id, dug_material):
			return _notify_fail({"ok": false, "reason": "inventory_full"})

	var result: Dictionary = _terrain_editor.apply_plane_plan(plan)
	if not result["ok"]:
		return _notify_fail(result)

	_plane_credit[player_id] = maxf(0.0, total + float(need) - float(gain))
	var materials: TerrainMaterialLayer = _terrain.get_material_layer()
	if is_instance_valid(materials):
		materials.clear_overrides(result["lowered_points"])
		materials.set_overrides(result["raised_points"], fill_material)
	if has_inventory:
		if need > 0:
			_ent_inventory.remove_item(fill_material, player_id, need)
		if gain > 0:
			_ent_inventory.request_add_item(dug_material, player_id, gain)
	if float(result["lowered"]) > 0.0 and is_instance_valid(_ent_skill):
		_ent_skill.request_add_xp("digging", DIG_XP, player_id)
	# Funde: wie Graben, wenn netto abgetragen wurde, sonst nur nachziehen.
	_after_terrain_edit(
		WorldTerrainEditor.MODE_DIG if float(result["lowered"]) > float(result["raised"])
		else WorldTerrainEditor.MODE_FILL, result)
	return result

## Wie _resolve_fill_material(), aber das Material muss in MINDESTENS `count` Stück vorhanden
## sein (Ebnen kann mehrere Items auf einmal brauchen). "" wenn keins reicht.
func _resolve_fill_material_count(player_id: String, count: int) -> String:
	if not is_instance_valid(_ent_inventory):
		return ITEM_DIRT
	for candidate in FILL_MATERIAL_PRIORITY:
		if _ent_inventory.has_item(candidate, player_id, count):
			return candidate
	return ""

## Funde nachziehen (Boden hat sich geändert) und beim Graben ggf. einen neuen Fund melden.
func _after_terrain_edit(mode: String, result: Dictionary) -> void:
	if _dig_handler == null:
		return
	var center: Vector2 = result.get("center", Vector2.ZERO)
	if mode != WorldTerrainEditor.MODE_DIG:
		_dig_handler.reseat_finds(center)
		return
	var layer: TerrainEditLayer = _terrain.get_edit_layer()
	var depth: float = -layer.get_delta_at(center.x, center.y) if layer != null else 0.0
	var outcome: Dictionary = _dig_handler.after_dig(center, depth)
	var kind: String = String(outcome.get("found", ""))
	if not kind.is_empty():
		_notify_text("Beim Graben entdeckt: %s!" % DigFindTable.get_label(kind))

## Leiter an der Wand vor dem Spieler aufstellen. Rückgabe siehe WorldDigHandler.place_ladder().
func request_ladder_place(player_id: String, origin: Vector3, facing: Vector3) -> Dictionary:
	if not _edits_active or _dig_handler == null:
		return _notify_fail({"ok": false, "reason": "coop_unsupported"})
	if player_id.is_empty():
		return _notify_fail({"ok": false, "reason": "no_player"})
	var pos: Vector3 = _player_position(player_id)
	if is_nan(pos.x):
		pos = origin
	var result: Dictionary = _dig_handler.place_ladder(player_id, pos, facing)
	if not bool(result["ok"]):
		return _notify_fail(result, player_id)
	_notify_text("Leiter aufgestellt (%.0f m)." % float(result["length"]))
	return result

func request_ladder_remove(player_id: String, key: String) -> Dictionary:
	if not _edits_active or _dig_handler == null:
		return _notify_fail({"ok": false, "reason": "coop_unsupported"})
	var result: Dictionary = _dig_handler.remove_ladder(player_id, key, _player_position(player_id))
	if not bool(result["ok"]):
		_notify_fail(result)
	return result

## Ein Fund wurde geborgen (DigFind) — Record löschen.
func remove_dig_find(key: String) -> void:
	if _dig_handler != null:
		_dig_handler.remove_find(key)

## Leiter-Registry für das Klettern (PlayerLadder). null in Mehrspieler-Sitzungen: Leitern
## sind wie alle Umbauten vorerst Solo-only.
func get_ladder_registry() -> LadderRegistry:
	return data.ladders if _edits_active else null

func request_build_place(player_id: String, piece_id: String, target: Vector3, rot_steps: int, storey: int = 0) -> Dictionary:
	var gate: Dictionary = _edit_gate(player_id, target, WorldBuildHandler.REACH)
	if not gate["ok"]:
		return _notify_fail(gate)
	var result: Dictionary = _build_handler.place(player_id, piece_id, target, rot_steps, _player_position(player_id), storey)
	if not result["ok"]:
		_notify_fail(result, player_id)
	return result

func request_build_remove(player_id: String, key: String) -> Dictionary:
	if not _edits_active or _build_handler == null:
		return _notify_fail({"ok": false, "reason": "coop_unsupported"})
	var result: Dictionary = _build_handler.remove(player_id, key, _player_position(player_id))
	if not result["ok"]:
		_notify_fail(result)
	return result

## Vorschau für ein GANZES Haus (Baumodus-Geist). Verändert nichts.
## Rückgabe siehe WorldBuildHandler.preview_house().
func preview_house_build(player_id: String, template_id: String, target: Vector3, rot_steps: int, storey: int = 0) -> Dictionary:
	if not _edits_active or _build_handler == null:
		return {"ok": false, "reason": "coop_unsupported", "pieces": [], "total_cost": {}, "affordable": false}
	return _build_handler.preview_house(player_id, template_id, target, rot_steps, _player_position(player_id), storey)

## Reine Geometrie für den Hausgeist (siehe WorldBuildHandler.house_ghost_pieces()) — KEINE
## Regelprüfung, verändert nichts. Baubarkeit/Kosten/Farbe kommen separat aus
## preview_house_build(); diese Methode sagt nur, wo/wie jedes Teil aussähe.
func house_ghost_pieces(template_id: String, target: Vector3, rot_steps: int, storey: int = 0) -> Array[Dictionary]:
	if not _edits_active or _build_handler == null:
		return []
	return _build_handler.house_ghost_pieces(template_id, target, rot_steps, storey)

func request_build_house(player_id: String, template_id: String, target: Vector3, rot_steps: int, storey: int = 0) -> Dictionary:
	var gate: Dictionary = _edit_gate(player_id, target, WorldBuildHandler.REACH)
	if not gate["ok"]:
		return _notify_fail(gate)
	var result: Dictionary = _build_handler.place_house(player_id, template_id, target, rot_steps, _player_position(player_id), storey)
	if not result["ok"]:
		_notify_fail(result, player_id)
	return result

func _on_terrain_edit_requested(player_id: String, mode: String, target: Vector3) -> void:
	request_terrain_edit(player_id, mode, target)

func _on_grass_cut_requested(player_id: String, target: Vector3) -> void:
	request_grass_cut(player_id, target)

## Sense: mäht Gras und Blumen in MOW_RADIUS um `target` und gibt Heu/Wildblumen. Gleiche Tore wie
## das Graben (_edit_gate: nur Solo, Reichweite). Das Gras ist reine Deko ohne Netzwerk-Sync,
## deshalb im Koop bewusst nicht verfügbar ("coop_unsupported").
const MOW_RADIUS: float = 2.4
const MOW_REACH: float = 5.0
const ITEM_HAY: String = "hay"
const ITEM_WILDFLOWER: String = "wildflower"
func request_grass_cut(player_id: String, target: Vector3) -> Dictionary:
	var gate: Dictionary = _edit_gate(player_id, target, MOW_REACH)
	if not gate["ok"]:
		return _notify_fail(gate)
	if not is_instance_valid(_chunk_manager):
		return {"ok": false, "reason": "no_world"}
	if is_instance_valid(_ent_inventory) and not _can_carry(player_id, ITEM_HAY):
		return _notify_fail({"ok": false, "reason": "inventory_full"})
	var stats: Dictionary = _chunk_manager.cut_vegetation(Vector2(target.x, target.z), MOW_RADIUS)
	var grass: int = int(stats.get("grass", 0))
	var flowers: int = int(stats.get("flowers", 0))
	if grass + flowers <= 0:
		_notify_text("Hier gibt es nichts zu mähen.")
		return {"ok": false, "reason": "no_grass"}
	var hay: int = clampi(ceili(float(grass) / 5.0), 0, 8)
	var blossoms: int = clampi(ceili(float(flowers) / 2.0), 0, 5)
	if is_instance_valid(_ent_inventory):
		if hay > 0:
			_ent_inventory.request_add_item(ITEM_HAY, player_id, hay)
		if blossoms > 0 and _can_carry(player_id, ITEM_WILDFLOWER):
			_ent_inventory.request_add_item(ITEM_WILDFLOWER, player_id, blossoms)
	return {"ok": true, "reason": "", "hay": hay, "wildflowers": blossoms}

func _on_terrain_plane_requested(player_id: String, target: Vector3, plane_y: float, direction: String) -> void:
	request_terrain_plane(player_id, target, plane_y, direction)

func _on_ladder_place_requested(player_id: String, origin: Vector3, facing: Vector3) -> void:
	request_ladder_place(player_id, origin, facing)

func _on_ladder_remove_requested(player_id: String, key: String) -> void:
	request_ladder_remove(player_id, key)

func _on_build_place_requested(player_id: String, piece_id: String, target: Vector3, rot_steps: int, storey: int) -> void:
	request_build_place(player_id, piece_id, target, rot_steps, storey)

func _on_build_remove_requested(player_id: String, key: String) -> void:
	request_build_remove(player_id, key)

func _on_build_house_place_requested(player_id: String, template_id: String, target: Vector3, rot_steps: int, storey: int) -> void:
	request_build_house(player_id, template_id, target, rot_steps, storey)

## Legt Editor + Bau-Handler an und hängt die Chunk-Hooks ein. Vor ChunkManager.initialize()
## aufrufen (der Spawn-Chunk wird dort synchron geladen und soll bereits gemeldet werden).
func _setup_world_editing() -> void:
	_terrain_editor = WorldTerrainEditor.new(data.terrain_edits, data.build_registry, _refresh_terrain_view)
	_terrain_editor.set_height_fn(_terrain.get_height_at)
	_build_handler = WorldBuildHandler.new(
		data.build_registry, _terrain_editor,
		_get_build_piece_def, _terrain.get_height_at,
		_spawn_build_view, _despawn_build_view,
		_terrain.get_config().chunk_size, _terrain.get_water_level_at
	)
	_build_handler.set_inventory_ops(_can_afford_build, _pay_build, _refund_build)
	_build_handler.set_house_defs(_get_house_template_def)
	_dig_handler = WorldDigHandler.new(
		data.ladders, data.dig_finds, _terrain.get_height_at,
		_spawn_build_view, _despawn_build_view, _terrain.get_config().chunk_size
	)
	_dig_handler.set_inventory_ops(_can_afford_build, _pay_build, _refund_build)
	# Ansichten der Bauteile, Leitern und Funde nur in Solo-Sitzungen (siehe Abschnittskommentar).
	if _edits_active:
		_chunk_manager.set_chunk_callbacks(_on_chunk_views_loaded, _on_chunk_views_unloaded)

func _on_chunk_views_loaded(coord: Vector2i) -> void:
	_build_handler.on_chunk_loaded(coord)
	_dig_handler.on_chunk_loaded(coord)

func _on_chunk_views_unloaded(coord: Vector2i) -> void:
	_build_handler.on_chunk_unloaded(coord)
	_dig_handler.on_chunk_unloaded(coord)

func _refresh_terrain_view(points: Array) -> void:
	if is_instance_valid(_chunk_manager):
		var typed: Array[Vector2i] = []
		for p in points:
			typed.append(p)
		_chunk_manager.refresh_terrain_points(typed)

## Gemeinsame Vorprüfung: Solo, Spielerposition bekannt, Ziel in Reichweite.
func _edit_gate(player_id: String, target: Vector3, reach: float) -> Dictionary:
	if not _edits_active or _terrain_editor == null or _build_handler == null:
		return {"ok": false, "reason": "coop_unsupported"}
	if player_id.is_empty():
		return {"ok": false, "reason": "no_player"}
	var pos: Vector3 = _player_position(player_id)
	if not is_nan(pos.x) and Vector2(pos.x, pos.z).distance_to(Vector2(target.x, target.z)) > reach:
		return {"ok": false, "reason": "too_far"}
	return {"ok": true, "reason": ""}

## Position des Spielers (Solo: der lokale Spieler). NAN-Vektor, wenn nicht ermittelbar.
func _player_position(_player_id: String) -> Vector3:
	var local_peer: int = _session_manager.get_local_peer_id() if is_instance_valid(_session_manager) else 1
	var player := get_player_by_id(local_peer)
	if not is_instance_valid(player):
		return Vector3(NAN, NAN, NAN)
	return player.global_position

func _can_carry(player_id: String, item_id: String) -> bool:
	return _ent_inventory.has_item(item_id, player_id, 1) or _ent_inventory.get_free_slots(player_id) > 0

func _get_build_piece_def(piece_id: String) -> Variant:
	return _ent_data.get_build_piece(piece_id) if is_instance_valid(_ent_data) else null

func _get_house_template_def(template_id: String) -> Variant:
	return _ent_data.get_house_template(template_id) if is_instance_valid(_ent_data) else null

func _spawn_build_view(type_id: String, pos: Vector3, cfg: Dictionary) -> Node3D:
	return spawn_entity(type_id, pos, cfg)

func _despawn_build_view(node: Node3D) -> void:
	_unload_entity_node(node)

## Gibt eine Entity frei, OHNE sie als abgeerntet/despawnt im Spielsinn zu behandeln (Chunk-
## Entladen, Bauteil-Ansicht). Siehe EntityOrchestrator.unload_entity().
func _unload_entity_node(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var uuid: String = resolve_entity_uuid(node)
	if uuid.is_empty() or not is_instance_valid(_entity_orchestrator):
		node.queue_free()
	else:
		_entity_orchestrator.unload_entity(uuid)

func _is_object_harvested(type_id: String, pos: Vector3) -> bool:
	return data.is_harvested_by_type(type_id, pos)

## FEATURE (Wunsch "Bauitems können auch aus der Bank gezogen werden"): Bestand
## zählt jetzt Inventar UND Bank zusammen — ein Spieler mit 40 Holz im
## Rucksack und 60 in der Bank kann ein Bauteil für 100 Holz bauen, ohne
## vorher manuell etwas abzuheben. Reihenfolge beim tatsächlichen Bezahlen
## (_pay_build()): erst Inventar, dann Bank — siehe dortiger Kommentar.
func _can_afford_build(player_id: String, cost: Dictionary) -> bool:
	if not is_instance_valid(_ent_inventory):
		return false
	for item_id: String in cost.keys():
		if _available_build_material(player_id, item_id) < int(cost[item_id]):
			return false
	return true

## Inventar-Bestand + (falls BankService verfügbar) Bank-Bestand desselben Items.
func _available_build_material(player_id: String, item_id: String) -> int:
	var have: int = 0
	var inv_inst: ItemInstance = _ent_inventory.get_item_instance(player_id, item_id)
	if is_instance_valid(inv_inst):
		have += inv_inst.quantity
	if is_instance_valid(_ent_bank):
		var bank_inst: ItemInstance = _ent_bank.get_bank_item_instance(player_id, item_id)
		if is_instance_valid(bank_inst):
			have += bank_inst.quantity
	return have

## Zieht zuerst so viel wie möglich aus dem Inventar, den Rest (falls das Inventar
## nicht reicht) aus der Bank — über BankService.remove_item_for_listing(), demselben
## "raus aus der Bank, OHNE über den Umweg Inventar zu gehen"-Primitiv, das auch das
## Auktionshaus-Escrow nutzt (siehe dortiger Klassenkommentar). Bei einem (eigentlich
## durch _can_afford_build() vorher ausgeschlossenen, aber sicherheitshalber trotzdem
## behandelten) Fehlschlag mitten in einer Multi-Item-Kostenliste: bereits abgezogene
## Items dieser einen Bauaktion werden zurückgebucht, statt den Spieler halb zu
## bezahlen zu lassen (gleiches Rollback-Muster wie place_house() bei einem
## fehlgeschlagenen Teil).
func _pay_build(player_id: String, cost: Dictionary) -> bool:
	if not _can_afford_build(player_id, cost):
		return false
	var paid: Dictionary = {}
	for item_id: String in cost.keys():
		var needed: int = int(cost[item_id])
		var inv_inst: ItemInstance = _ent_inventory.get_item_instance(player_id, item_id)
		var inv_have: int = inv_inst.quantity if is_instance_valid(inv_inst) else 0
		var from_inventory: int = mini(needed, inv_have)
		if from_inventory > 0 and not _ent_inventory.remove_item(item_id, player_id, from_inventory):
			_rollback_build_payment(player_id, paid)
			return false
		var from_bank: int = needed - from_inventory
		if from_bank > 0:
			if not is_instance_valid(_ent_bank) or not _ent_bank.remove_item_for_listing(player_id, item_id, from_bank):
				# Inventar-Teil dieses EINEN Items sofort zurückbuchen, dann Gesamt-Rollback.
				if from_inventory > 0:
					_ent_inventory.request_add_item(item_id, player_id, from_inventory)
				_rollback_build_payment(player_id, paid)
				return false
		paid[item_id] = needed
	return true

func _rollback_build_payment(player_id: String, paid: Dictionary) -> void:
	if not paid.is_empty():
		_refund_build(player_id, paid)

func _refund_build(player_id: String, items: Dictionary) -> void:
	if not is_instance_valid(_ent_inventory):
		return
	for item_id: String in items.keys():
		_ent_inventory.request_add_item(item_id, player_id, int(items[item_id]))

## Meldet einen abgelehnten Wunsch als Benachrichtigung und reicht das Ergebnis durch.
## Die Reason-Codes sind zwischen Bauen und Graben eindeutig (gemeinsame: too_far,
## coop_unsupported) — erst die Bau-Texte, dann die Gelände-Texte.
## player_id: nur nötig, wenn result bei reason "no_materials" ein "cost"-Dictionary trägt
## (siehe WorldBuildHandler._fail() / WorldDigHandler.place_ladder()) — sonst irrelevant, leer
## lassen. Bei den übrigen Fehlergründen unverändert der generische Text.
func _notify_fail(result: Dictionary, player_id: String = "") -> Dictionary:
	var reason: String = String(result.get("reason", ""))
	if reason == "no_materials" and result.has("cost") and not player_id.is_empty():
		_notify_text(_missing_materials_text(player_id, result["cost"] as Dictionary))
	else:
		_notify_text(_reason_text(reason))
	return result

## Baut aus einem Kosten-Dictionary (item_id -> benötigte Menge) eine konkrete Meldung wie
## "Dir fehlen Materialien: 3× Leiter". Zeigt nur Items, von denen der Spieler tatsächlich zu
## wenig hat (nicht die vollen Kosten) — damit man z.B. bei 2 vorhandenen und 5 benötigten
## Leitern sofort sieht: "noch 3× Leiter". Fällt ohne Inventar-Zugriff auf den generischen
## Text zurück, statt eine falsche/leere Meldung zu zeigen.
func _missing_materials_text(player_id: String, cost: Dictionary) -> String:
	if not is_instance_valid(_ent_inventory):
		return BuildPlacementRules.reason_text("no_materials")
	var parts: Array[String] = []
	for item_id: String in cost.keys():
		var needed: int = int(cost[item_id])
		# Inventar + Bank zusammen (siehe _available_build_material()) — sonst würde
		# hier fälschlich "fehlt" stehen, obwohl die Bank-Bestände den Rest decken.
		var have: int = _available_build_material(player_id, item_id)
		var missing: int = needed - have
		if missing <= 0:
			continue
		var def: ItemDefinition = _ent_inventory.get_item_info(item_id)
		var label: String = def.display_name if def != null else item_id
		parts.append("%d× %s" % [missing, label])
	if parts.is_empty():
		return BuildPlacementRules.reason_text("no_materials")
	return "Dir fehlen Materialien: %s" % ", ".join(parts)

static func _reason_text(reason: String) -> String:
	var build_text: String = BuildPlacementRules.reason_text(reason)
	if build_text != BuildPlacementRules.reason_text(""):
		return build_text
	var dig_text: String = WorldDigHandler.reason_text(reason)
	if dig_text != WorldDigHandler.reason_text(""):
		return dig_text
	return WorldTerrainEditor.reason_text(reason)

func _notify_text(text: String) -> void:
	if is_instance_valid(_bus):
		_bus.ui().emit_notification_requested(text)

## Öffentlich: läuft gerade ein Solo-Spiel (kein aktiver Netzwerk-Peer)? Reiten & Co. sind
## Solo-Features (kein Koop-Abgleich für Zusatz-Tempo, siehe PlayerMount).
func is_solo_world() -> bool:
	return _is_solo_session()

func _is_solo_session() -> bool:
	return not (is_instance_valid(_session_manager) and _session_manager.has_active_peer())

# ─────────────────────────────────────────────
# Multiplayer (Sprint E)
# ─────────────────────────────────────────────

## F-1: Richtet einen MultiplayerSpawner für die Spielwelt ein.
## Läuft nur auf dem Server (Host/Tier 2-3) vor spawn_all().
##
## Verwendet spawn_function/despawn_function statt add_spawnable_scene(),
## weil das Projekt GDScript.new()-basiertes Instanziieren nutzt (keine .tscn-Wrapper).
## add_spawnable_scene() akzeptiert nur .tscn-Pfade und würde zur Laufzeit fehlschlagen.
##
## Godot ruft spawn_function(data) auf dem Client auf wenn der Server einen Node
## unter spawn_path hinzufügt. data ist ein frei wählbarer Variant — wir übergeben
## den registrierten script_path als String, der via path_map zu type_id aufgelöst wird.
func _setup_multiplayer_spawner(world_root: Node3D) -> void:
	var ms := MultiplayerSpawner.new()
	ms.name = "WorldMultiplayerSpawner"
	ms.spawn_path = NodePath("..")   # world_root selbst ist Spawn-Root

	# Path → TypeId-Map aus der EntityRegistry aufbauen.
	# Ermöglicht spawn_function() den richtigen type_id zu ermitteln
	# ohne den EntityOrchestrator direkt in der Closure zu referenzieren.
	var path_map: Dictionary = _entity_orchestrator.get_registry().get_path_to_type_map()
	var registry_ref := _entity_orchestrator.get_registry()  # Closure-Capture

	ms.spawn_function = func(data: Variant) -> Node:
		# data ist der script_path-String (vom Server beim Spawn übermittelt).
		var type_id: String = path_map.get(str(data), "")
		if type_id.is_empty():
			AppLogger.log_error(
				"MultiplayerSpawner.spawn_function: Unbekannter Pfad '%s'." % str(data),
				LOG_CAT
			)
			return null
		# Nur instanziieren — kein add_child, kein on_spawn, kein UUID-Tracking.
		# Der MultiplayerSpawner übernimmt add_child in world_root selbst.
		# State-Sync läuft via MultiplayerSynchronizer (Sprint E).
		return registry_ref.instantiate(type_id)

	# BUGFIX (2026-09-14): 'despawn_function' existiert NICHT als Property
	# auf MultiplayerSpawner (Godot 4) — die Zuweisung schlug bei JEDEM
	# Welt-Boot fehl: "Invalid assignment of property or key
	# 'despawn_function' ... on a base object of type 'MultiplayerSpawner'".
	# MultiplayerSpawner despawnt automatisch, sobald der Server-seitige
	# Node freigegeben wird — kein manueller Hook nötig. Für zusätzliche
	# Client-seitige Aufräumarbeiten existiert stattdessen das Signal
	# 'despawned(node)', keine zuweisbare Callable-Property.
	ms.despawned.connect(func(node: Node) -> void:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	)

	world_root.add_child(ms)
	AppLogger.log_info(
		"MultiplayerSpawner eingerichtet (%d Typen, Custom Spawn/Despawn)." % path_map.size(),
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return _save_handler.get_save_data()

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func get_formatted_time() -> String:
	return _time.get_formatted_time()

## peer_id: Multiplayer-Autorität des gespawnten Nodes.
## Default 1 = Server-Autorität (Bäume, Erze, Gegner, Tiere).
## Für Player-Respawn die echte peer_id des Clients übergeben.
func spawn_entity(type_id: String, position: Vector3, config: Dictionary = {}, peer_id: int = 1) -> Node3D:
	if not is_instance_valid(_entity_orchestrator):
		return null
	var entity := _entity_orchestrator.spawn_entity(type_id, position, config, peer_id)
	# G-02: Player-Nodes beim ChunkManager registrieren damit alle Spieler Chunks laden.
	if is_instance_valid(entity) and type_id == "player" and is_instance_valid(_chunk_manager):
		_chunk_manager.add_player(entity)
	return entity

## RespawnService.set_spawn_callback()-Ziel (Wunsch "Bäume ... über Spieltage hinweg wachsen"):
## anders als der frühere Callback (immer config={}) wird hier der aktuelle Tag als
## "planted_day" mitgegeben UND dauerhaft in WorldData vermerkt (mark_planted() — überlebt
## Save/Load, siehe WorldSaveHandler). HarvestableEntity legt `config` als `_spawn_config` ab,
## bevor _build_visuals() läuft (siehe dortiger Kommentar) — OakTree/WillowTree/MapleTree/
## PineTree lesen `_spawn_config.get("planted_day", -1)` und wählen darüber ihr Wachstums-
## stadium: ein originaler Weltbaum (nie über diesen Callback gespawnt) hat NIE einen
## planted_day-Eintrag und bleibt bei der statischen Positions-Varietät aus TreeGrowthStage.gd.
## Nur für Bäume relevant, aber für alle respawnenden Typen gesetzt (Erz/Gegner/... ignorieren
## den Konfig-Schlüssel einfach — kein type_id-Filter nötig).
func _respawn_spawn(type_id: String, position: Vector3, peer_id: int) -> Node3D:
	data.mark_planted(type_id, position, day_count)
	return spawn_entity(type_id, position, {"planted_day": day_count}, peer_id)

func despawn_entity(uuid: String) -> void:
	if not is_instance_valid(_entity_orchestrator):
		return
	# G-02: Player-Node aus Chunk-Tracking entfernen bevor er despawnt wird.
	if is_instance_valid(_chunk_manager):
		var entity := _entity_orchestrator.get_entity(uuid)
		if is_instance_valid(entity) and entity.is_in_group("player"):
			_chunk_manager.remove_player(entity)
	_entity_orchestrator.despawn_entity(uuid)

## BUGFIX (2026-09-15, "Sterben soll auch synced werden"): Despawn per
## deterministischem Node-Namen statt uuid — für Aufrufer, die (wie ein
## Netzwerk-Broadcast von einem ANDEREN Peer) nur den Namen kennen können,
## nie die lokale (pro Peer zufällige) uuid. Siehe EntityOrchestrator.get_entity_uuid_by_name().
func despawn_entity_by_name(entity_name: String) -> void:
	if not is_instance_valid(_entity_orchestrator):
		return
	var uuid := _entity_orchestrator.get_entity_uuid_by_name(entity_name)
	if uuid.is_empty():
		AppLogger.log_warn(
			"despawn_entity_by_name('%s'): kein lokales Entity mit diesem Namen gefunden." % entity_name,
			LOG_CAT
		)
		return
	despawn_entity(uuid)

## BUGFIX (2026-09-16, "Charakter-Wechsel ohne Trennung"): MUSS von
## ServiceOrchestrator._on_state_changed() aufgerufen werden, BEVOR die
## CharacterScope (und damit dieses WorldService/NetworkBridge) zerstört wird
## — meldet das eigene Player-Entity als despawnt an alle anderen Peers, analog
## zu EnemyNPC._die(). Ohne das blieb bei jedem "zurück zum Hauptmenü" (Charakter
## wechseln OHNE echte Netzwerktrennung — die Verbindung bleibt bestehen, nur
## Charakter/Session wechseln) auf allen anderen Peers eine Spieler-Leiche
## stehen: deren MultiplayerSynchronizer bekam nie wieder Updates (das Node war
## ja auf der sendenden Seite bereits zerstört), UND weil peer_id gleich blieb,
## kollidierte der Name mit dem NEUEN Charakter (siehe zusätzlich die
## player_id-statt-peer_id-Namensvergabe in EntityOrchestrator.spawn_entity(),
## die diese Kollision von vornherein verhindert — dieser Broadcast hier räumt
## zusätzlich bei den ANDEREN Peers auf, die den alten Node sonst nie loswerden).
func report_local_player_leaving() -> void:
	if not is_instance_valid(_network) or not is_instance_valid(_session_manager):
		return
	var local_peer := _session_manager.get_local_peer_id()
	var local_node := get_player_by_id(local_peer)
	if not is_instance_valid(local_node):
		return
	_network.broadcast_to_all_peers("entity_despawned", {"name": local_node.name})
	AppLogger.log_info(
		"report_local_player_leaving(): '%s' als despawnt an alle Peers gemeldet." % local_node.name,
		LOG_CAT
	)
## BUGFIX (2026-09-15, "Sterben soll auch synced werden"): Gegenstück zu
## EnemyNPC._die()'s broadcast_to_all_peers("entity_despawned", {"name": …}).
## Läuft NUR auf Nicht-Autoritäts-Peers (die Autorität hat ihr eigenes Entity
## bereits lokal über _die()/queue_free() entfernt, siehe dortiger Kommentar —
## broadcast_to_all_peers() schickt ohnehin nie an den Absender selbst zurück).
## Erweiterbar für künftige "kind"-Werte über denselben Kanal (ADR-042) — bisher
## der einzige Konsument von broadcast_event_received() in WorldService.
func _on_broadcast_event_received(kind: String, payload: Dictionary) -> void:
	if kind != "entity_despawned":
		return
	var entity_name: String = payload.get("name", "")
	if entity_name.is_empty():
		AppLogger.log_warn("_on_broadcast_event_received('entity_despawned'): 'name' fehlt im Payload.", LOG_CAT)
		return
	despawn_entity_by_name(entity_name)

## BUGFIX (2026-09-15, "Guest kann nichts abbauen"): robuste uuid-Auflösung für
## Aufrufer außerhalb von EntityOrchestrator (aktuell: InteractableComponent._handle_completion()).
## parent.get_meta("entity_uuid", "") lieferte im Feld-Test beim Guest einen
## leeren String für eine ganz normal gespawnte HarvestableEntity, obwohl
## EntityOrchestrator.spawn_entity() das Meta unconditional VOR add_child()
## setzt — die exakte Ursache konnte ohne laufende Godot-Instanz nicht
## zweifelsfrei reproduziert/verifiziert werden. Diese Fallback-Auflösung über
## den deterministischen Node-Namen (siehe get_entity_uuid_by_name(), bereits
## für den Despawn-Broadcast eingeführt) schließt die Lücke unabhängig von der
## genauen Ursache: liefert der direkte Meta-Read nichts, wird derselbe Weg wie
## beim namensbasierten Despawn genutzt, bevor endgültig aufgegeben wird.
## FEATURE (2026-09-17, "Pets cross-peer sichtbar"): schlanker Existenz-Check
## für NetworkBridge._rpc_spawn_remote_pet()'s Idempotenz-Guard — ob überhaupt
## EIN Entity mit diesem Namen lokal existiert, ohne dessen uuid zu brauchen.
func has_entity_named(entity_name: String) -> bool:
	if not is_instance_valid(_entity_orchestrator):
		return false
	return not _entity_orchestrator.get_entity_uuid_by_name(entity_name).is_empty()

func resolve_entity_uuid(entity_node: Node3D) -> String:
	if not is_instance_valid(entity_node):
		return ""
	var uuid: String = entity_node.get_meta("entity_uuid", "")
	if not uuid.is_empty():
		return uuid
	if is_instance_valid(_entity_orchestrator):
		uuid = _entity_orchestrator.get_entity_uuid_by_name(entity_node.name)
		if not uuid.is_empty():
			AppLogger.log_info(
				"resolve_entity_uuid('%s'): Meta leer, über Namensauflösung gefunden." % entity_node.name,
				LOG_CAT
			)
	if uuid.is_empty():
		# DIAGNOSE (2026-09-16, "Guest kann immer noch nichts abbauen"): beide
		# Auflösungswege sind jetzt zweimal in Folge gescheitert — bevor ich
		# einen dritten blinden Fix baue, hier alle Fakten, die beim nächsten
		# Auftreten zeigen sollten, WARUM: hat entity_node überhaupt EIN Meta-Key,
		# steckt es (unter IRGENDEINEM Namen) in _entities, wie groß ist
		# _entities zu diesem Zeitpunkt.
		var meta_keys: Array[String] = []
		for k in entity_node.get_meta_list():
			meta_keys.append(str(k))
		var found_by_identity := false
		var entities_count := 0
		if is_instance_valid(_entity_orchestrator):
			entities_count = _entity_orchestrator.get_entity_count()
			found_by_identity = _entity_orchestrator.has_entity_instance(entity_node)
		AppLogger.log_warn(
			"resolve_entity_uuid('%s') KOMPLETT gescheitert. meta_keys=%s | in _entities via Objekt-Identität=%s | _entities.size()=%d" % [
				entity_node.name, meta_keys, found_by_identity, entities_count
			],
			LOG_CAT
		)
	return uuid

func get_entity_debug_info() -> Dictionary:
	if not is_instance_valid(_entity_orchestrator):
		return {}
	return _entity_orchestrator.get_debug_info()

## ADR-027: Fassade auf EntityOrchestrator.find_player_by_id() — der eine
## kanonische "Player-Node für peer_id"-Lookup, aufrufbar von Services ohne
## IEntityContext/IUIContext (z. B. EquipmentService via inject_world_service()).
func get_player_by_id(peer_id: int) -> Node3D:
	if not is_instance_valid(_entity_orchestrator):
		return null
	return _entity_orchestrator.find_player_by_id(peer_id)

## ADR-027: löst den PlayerVisuals-Kindnode von peer_id auf. Ersetzt die
## bisher doppelt vorhandene Kind-Lookup-Logik aus
## InventoryUIController._find_local_player_visuals() und
## EquipmentUIController's Äquivalent — beide riefen zuvor ctx.get_local_player()
## (nur der LOKALE Peer) auf und suchten dann selbst den PlayerVisuals-Child.
## Hier für einen BELIEBIGEN peer_id, damit die Equip-Autorität (die auf
## Tier 2/3 nicht der aufrufende Peer ist) die Visuals des ZIEL-Spielers
## auflösen kann, nicht die des Aufrufers.
func get_player_visuals(peer_id: int) -> PlayerVisuals:
	var player_node := get_player_by_id(peer_id)
	if not is_instance_valid(player_node):
		return null
	var pv := player_node.get_node_or_null("PlayerVisuals") as PlayerVisuals
	if is_instance_valid(pv):
		return pv
	for child in player_node.get_children():
		if child is PlayerVisuals:
			return child as PlayerVisuals
	return null

## ADR-025: autoritäts-seitiger Einstiegspunkt für Bewegungs-Input, aufgerufen
## ausschließlich von NetworkBridge._rpc_submit_movement_input() (peer_id dort
## bereits fälschungssicher aus multiplayer.get_remote_sender_id() aufgelöst,
## nie aus dem Payload). Löst den Ziel-Player-Node über dieselbe Fassade wie
## jeder andere peer_id-Lookup auf (get_player_by_id() → EntityOrchestrator.
## find_player_by_id()) und reicht den Snapshot durch — keine eigene Logik hier,
## damit es nur EINE Stelle gibt, die "peer_id → Node" auflöst.
func route_movement_input(peer_id: int, input_snapshot: Dictionary) -> void:
	var player_node := get_player_by_id(peer_id)
	if not is_instance_valid(player_node):
		# Race zwischen Despawn/Disconnect und einem noch unterwegs befindlichen
		# unreliable Input-Paket — erwartbar, kein Fehlerfall, deshalb kein log_warn
		# (würde bei jedem Disconnect spammen, s. NetworkContract.gd "UNRELIABLE").
		return
	# has_method()+call() statt direktem typisiertem Aufruf — player_node ist als
	# Node3D typisiert (get_player_by_id()s Rückgabetyp), derselbe Grund wie beim
	# `_on_interacted`-Aufruf oben in resolve_and_dispatch_interaction().
	if player_node.has_method("receive_authoritative_input"):
		player_node.call("receive_authoritative_input", input_snapshot)

func _on_entity_despawn_requested(uuid: String) -> void:
	despawn_entity(uuid)

## ADR-030: verdrahtet alle ZoneTriggerVolume-Nodes, die zum Zeitpunkt von
## on_ready() bereits in der Welt-Szene stehen (Level-Design-platziert, nicht
## über EntityOrchestrator gespawnt — dieselbe Kategorie wie QuestCustomTrigger).
## _network ist an dieser Stelle typischerweise noch nicht gesetzt (Late-Inject
## S8.6 kommt danach) — inject_network_bridge() holt das nach, siehe dort.
## Nodes, die ERST NACH on_ready() zur Welt hinzugefügt werden, sind bewusst
## nicht abgedeckt (kein Rescan-Mechanismus) — wie WorldSpawner-gespawnte
## Trees etc. ohnehin über eigene Pfade laufen, nicht über zone_triggers.
func _wire_zone_triggers() -> void:
	if not is_instance_valid(_zone_service):
		return
	for trigger in get_tree().get_nodes_in_group("zone_triggers"):
		if trigger is ZoneTriggerVolume:
			trigger.inject_zone_service(_zone_service)
			if is_instance_valid(_network):
				trigger.inject_network_bridge(_network)

# ─────────────────────────────────────────────
# ADR-020: Interaktions-Ergebnisse werden auf der Autorität ausgeführt
# ─────────────────────────────────────────────

## Fallback-Reichweite falls eine Entity keine InteractableComponent (mehr) hat —
## sollte im Normalfall nie greifen (jede interagierbare Entity hat eine), rein
## defensiv gegen einen Despawn-Race zwischen Client-Interaktion und RPC-Ankunft.
const _FALLBACK_INTERACTION_RANGE := 5.0
## Toleranz zusätzlich zum tatsächlichen Interaktions-Radius — deckt Rundung/
## Interpolation ab, kein zusätzlicher Cheat-Spielraum (bewegt sich nicht mit
## einem client-gemeldeten Wert, sondern ist eine feste, servereigene Konstante).
const _INTERACTION_RANGE_MARGIN := 1.5

## Aufgerufen von InteractableComponent._handle_completion() für JEDE Entity mit
## _on_interacted()-Hook (Harvestables, Tiere, Gegner), NUR wenn diese Entity aus
## Sicht des ausführenden Peers nicht die Netzwerk-Autorität ist.
##
## WICHTIG (Cheat-Vektor geschlossen): peer_id kommt hier NIE vom Client selbst —
## auf Tier 2/3 setzt NetworkBridge ihn aus multiplayer.get_remote_sender_id()
## (fälschungssicher, Godot-verwaltet), auf Tier 1 ist es ohnehin immer der lokale
## Spieler. Ebenso wenig wird eine Reichweite vom Client entgegengenommen — siehe
## resolve_and_dispatch_interaction().
## Bugfix 2026-09-26: [param actor_uuid] siehe EntityOrchestrator.resolve_for_player()
## und NetworkBridge.send_entity_interaction() — optional, leer = unverändertes
## Verhalten (Reichweite ab dem Spieler selbst).
func request_entity_interaction(entity_uuid: String, action_id: String, peer_id: int, actor_uuid: String = "") -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_entity_interaction(entity_uuid, action_id, actor_uuid)
		return
	# Kein Peer (Tier 1) oder wir sind bereits die Autorität: direkt auflösen.
	# Sollte über den is_multiplayer_authority()-Guard im Aufrufer eigentlich nie
	# der reguläre Pfad sein (dann läuft der lokale interacted-Emit bereits mit
	# echter Wirkung) — rein defensive Deckung, kein Doppel-Wirkungs-Risiko, weil
	# resolve_and_dispatch_interaction() denselben _on_interacted()-Hook aufruft,
	# den auch der lokale Emit aufgerufen hätte.
	resolve_and_dispatch_interaction(entity_uuid, action_id, peer_id, actor_uuid)

## Autoritäts-seitiger Einstiegspunkt (ADR-023 + ADR-020): löst entity_uuid über
## EntityOrchestrator.resolve_for_player() auf — inkl. Plausibilitäts-Check, ob
## peer_id überhaupt in Reichweite ist — und ruft bei Erfolg den Interaktions-
## Hook der Entity auf. Die max_range dafür kommt von der Entity selbst
## (InteractableComponent.detection_radius, servereigener State), niemals vom
## Client — ein modifizierter Client könnte sonst eine beliebig große Reichweite
## mitschicken und die Plausibilitätsprüfung wertlos machen.
## Bugfix 2026-09-26: [param actor_uuid] siehe EntityOrchestrator.resolve_for_player().
func resolve_and_dispatch_interaction(entity_uuid: String, action_id: String, peer_id: int, actor_uuid: String = "") -> void:
	if not is_instance_valid(_entity_orchestrator):
		AppLogger.log_warn("resolve_and_dispatch_interaction(): kein EntityOrchestrator.", LOG_CAT)
		return

	var probe := _entity_orchestrator.get_entity(entity_uuid)
	if not is_instance_valid(probe):
		AppLogger.log_warn(
			"resolve_and_dispatch_interaction('%s'): unbekannte/bereits despawnte Entity." % entity_uuid,
			LOG_CAT
		)
		return

	var max_range := _max_interaction_range_for(probe, action_id)
	var entity := _entity_orchestrator.resolve_for_player(entity_uuid, peer_id, max_range, actor_uuid)
	if not is_instance_valid(entity):
		return  # resolve_for_player() loggt bereits den genauen Ablehnungsgrund

	if entity.has_method("_on_interacted"):
		entity._on_interacted(action_id, peer_id)
	else:
		AppLogger.log_warn(
			"resolve_and_dispatch_interaction('%s'): Entity hat keinen _on_interacted()-Hook." % entity_uuid,
			LOG_CAT
		)

## Liest den tatsächlichen Interaktions-Radius aus der InteractableComponent der
## Entity (gesetzt in InteractableComponent._ready() als Meta "interactable_components",
## Liste seit ADR-035 — ein Node kann mehrere Interaktionen tragen, z.B. Player:
## "attack_player" + "trade_request", jede mit potenziell eigenem detection_radius)
## statt einen globalen Wert zu raten — jede Interaktionsart hat ihren eigenen,
## typischerweise über @export data.detection_radius definierten Radius.
## action_id wählt die zur tatsächlich angeforderten Aktion passende Komponente
## aus der Liste — ohne das würde bei mehreren Komponenten pro Node einfach
## irgendeine (z.B. die erste) das Reichweiten-Limit für ALLE Aktionen setzen.
func _max_interaction_range_for(entity: Node, action_id: String) -> float:
	var comps: Array = entity.get_meta("interactable_components", [])
	var base_id := action_id.trim_suffix("_inspect")
	for comp in comps:
		if is_instance_valid(comp) and (comp as InteractableComponent).data.id == base_id:
			return (comp as InteractableComponent).detection_radius + _INTERACTION_RANGE_MARGIN
	# Kein exakter Treffer (z.B. "<id>_inspect"-Aktionen, die dieselbe Komponente
	# wie ihre Basis-Aktion nutzen, siehe InteractableComponent.get_actions()) —
	# größte verfügbare Reichweite unter den Komponenten dieser Entity als
	# plausibler Fallback, bevor auf den globalen Fallback-Wert zurückgefallen wird.
	var best := -1.0
	for comp in comps:
		if is_instance_valid(comp):
			best = max(best, (comp as InteractableComponent).detection_radius)
	if best >= 0.0:
		return best + _INTERACTION_RANGE_MARGIN
	AppLogger.log_warn(
		"_max_interaction_range_for('%s'): keine InteractableComponent gefunden — Fallback-Reichweite %.1f." \
		% [entity.name, _FALLBACK_INTERACTION_RANGE],
		LOG_CAT
	)
	return _FALLBACK_INTERACTION_RANGE

## G-03: Wird von SessionManager.peer_cleanup_requested ausgelöst wenn ein Peer die Verbindung trennt.
## Entfernt alle Player-Nodes dieses Peers aus dem ChunkManager-Tracking.
## Der eigentliche Node-Despawn läuft separat über EntityOrchestrator (uuid-basiert).
func _on_peer_cleanup_requested(peer_id: int) -> void:
	if not is_instance_valid(_chunk_manager):
		return
	if not is_instance_valid(_entity_orchestrator):
		return
	# Alle Player-Nodes mit diesem owner_peer_id aus dem Tracking entfernen.
	# Meta statt multiplayer_authority: "wem gehört das Node" und "wer ist
	# Netzwerk-Autorität" sind zwei verschiedene Fragen (ADR-025), siehe TODO
	# "BLOCKER für ADR-025/026-Umsetzung".
	var player_nodes := _entity_orchestrator.get_entities_in_group("player")
	for player in player_nodes:
		if is_instance_valid(player) and player.get_meta("owner_peer_id", 1) == peer_id:
			_chunk_manager.remove_player(player)
			AppLogger.log_info(
				"Peer %d: Player-Node aus Chunk-Tracking entfernt." % peer_id, LOG_CAT
			)

## Pre-Flush-Handler: Sichert Pet-Daten bevor SaveSystem auf Disk schreibt.
## Wird über EventBus.persistence.save_pre_flush ausgelöst (nicht direkt von GameSaveService).
func _on_save_pre_flush() -> void:
	collect_and_store_pet_data()
	collect_and_store_player_health()

# ─────────────────────────────────────────────
# Öffentliche API — WorldData-Delegation
# Externe Aufrufer nutzen diese Wrapper statt direktem Datenzugriff.
# ─────────────────────────────────────────────

## Generischer Harvest-Marker für alle HarvestableEntity-Subklassen.
## type_id = EntityRegistry-Key (z.B. "oak_tree", "iron_ore", "copper_ore").
## Delegiert auf WorldData.make_key() → einheitliches Schema an allen drei
## Stellen: mark / unmark / is_harvested_by_type.
func mark_harvested(type_id: String, pos: Vector3) -> void:
	data.mark_harvested(WorldData.make_key(type_id, pos))

## Speichert Pet-Zustand vor dem Abspeichern.
func store_pet_save_data(pet_data: Array[Dictionary]) -> void:
	data.set_meta("saved_pets", pet_data)

## Scannt alle aktiven Pets und sichert deren Zustand via store_pet_save_data().
## Aufgerufen von _on_save_pre_flush() — nicht mehr direkt von GameSaveService.
func collect_and_store_pet_data() -> void:
	var pet_data: Array[Dictionary] = []
	for pet in get_tree().get_nodes_in_group("pets"):
		if pet is PetComponent:
			pet_data.append(pet.get_save_state())
	store_pet_save_data(pet_data)
	AppLogger.log_debug("Pets gesammelt und gespeichert: %d" % pet_data.size(), LOG_CAT)

## BUG-C-FIX (HP wird nicht gespeichert): scannt alle aktiven Player-Nodes und
## sichert current_health/max_health ihrer HealthComponent in
## data.player_health, keyed by player_id (stabile Charakter-UUID — siehe
## WorldData.player_health-Kommentar). Analog zu collect_and_store_pet_data(),
## aufgerufen von _on_save_pre_flush().
func collect_and_store_player_health() -> void:
	var count := 0
	for p in get_tree().get_nodes_in_group("player"):
		if not (p is Player) or not is_instance_valid(p.health):
			continue
		var player_id := _network.get_player_id_for_peer(p.get_owner_peer_id()) \
			if is_instance_valid(_network) else ""
		if player_id.is_empty():
			AppLogger.log_warn(
				"collect_and_store_player_health(): keine player_id für Peer %d — HP nicht gespeichert."
				% p.get_owner_peer_id(),
				LOG_CAT
			)
			continue
		data.player_health[player_id] = {
			"current": p.health.current_health,
			"max":     p.health.max_health,
		}
		count += 1
	AppLogger.log_debug("Spieler-HP gesammelt und gespeichert: %d" % count, LOG_CAT)

## FEATURE (Pet-Menü, Wunsch "Pets auf Ressourcen sammeln usw. verteilen"):
## reiner Lese-Zugriff für UI-Panels (siehe PetPanelController) — NUR die
## eigenen Pets eines Spielers (peer_id), analog zu get_player_by_id(). Gleiche
## Gruppen-Quelle wie collect_and_store_pet_data() (Gruppe "pets"), hier aber
## gefiltert statt gesammelt zurückgegeben. Bewusst über
## PetComponent.get_owner_peer_id() statt is_multiplayer_authority() gefiltert
## — "wem gehört das Pet" und "wer ist Netzwerk-Autorität darüber" sind
## dieselben zwei getrennten Fragen wie beim Player-Node (siehe
## IUIContext.get_local_player()-Kommentar), hier fallen sie für Pets zwar
## tatsächlich zusammen (Pets sind client-autoritativ, Autorität = Besitzer),
## aber das Panel soll explizit nach Besitzer filtern, nicht implizit über
## eine Autoritäts-Prüfung, die zufällig denselben Wert hat.
func get_pets_for_peer(peer_id: int) -> Array[PetComponent]:
	var result: Array[PetComponent] = []
	for pet in get_tree().get_nodes_in_group("pets"):
		if pet is PetComponent and (pet as PetComponent).get_owner_peer_id() == peer_id:
			result.append(pet as PetComponent)
	return result
