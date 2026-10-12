extends Node
class_name EntityOrchestrator

## EntityOrchestrator — Entity-Lifecycle, Gruppe-Management, UUID-Tracking.
##
## LEBT ALS CHILD VON WorldService (nicht als Autoload).
##
## Verantwortung (koordiniert, delegiert Details):
##   - spawn_entity() / despawn_entity() — öffentliche API
##   - UUID-basiertes Tracking: _entities { uuid: Node3D }
##   - Delegiert Pooling  → EntityPool
##   - Delegiert Definition/Instanziierung → EntityRegistry
##   - on_world_unloaded() für sauberes Cleanup

const LOG_CAT := "EntityOrchestrator"

var _world_root: Node3D = null
var _entities:   Dictionary = {}   # { uuid: Node3D }
var _pool:       EntityPool
var _registry:   EntityRegistry
var _bus:        IEventBus   # injiziert von WorldService nach add_child()

## BUGFIX (2026-09-26, "Telemetrie meldet ständig verwaiste Nodes"): unsichtbarer Container
## für gepoolte (inaktive) Entities — siehe EntityPool._park_container-Kommentar. Kind von
## EntityOrchestrator selbst, kein eigener SceneTree-Sonderfall nötig.
## BUGFIX (2026-09-27, "Bäume/NPCs despawnen visuell nicht mehr, Interaktion hängt"): war
## bis hierhin ein einfacher `Node` — dadurch zwar aus der Telemetrie-Orphan-Zählung raus,
## aber NICHT unsichtbar/inaktiv: ein reines `Node` hat gar kein `visible`, und Node3D-Kinder
## ohne Node3D-Vorfahren rendern einfach an ihrer letzten globalen Position weiter. Bäume/NPCs
## blieben nach dem "Despawn" (jetzt: Park statt Free) sichtbar UND weiter interaktiv (Area3D-
## Erkennung/Gruppen liefen unverändert), jeder erneute Klick löste despawn_entity() auf die
## bereits gelöschte alte UUID aus → "UUID nicht in aktiven Entities"-Warnungen im Log, Objekt
## verschwand nie. Fix: Node3D + in _ready() explizit unsichtbar/prozess-deaktiviert — beides
## Property-Vererbung, beim Zurück-Reparenten unter _world_root in spawn_entity() (sichtbar/
## aktiv) springt beides automatisch wieder an, ohne dass EntityPool/HarvestableEntity/
## EnemyNPC etwas davon wissen müssen.
var _pool_container: Node3D = null

## via set_entity_services() nachdem alle Session-Deps bekannt sind.
## Injizierte Entity-Services — gesetzt von WorldService.configure() via set_entity_services().
var _entity_skill_system:         SkillSystem          = null
var _entity_inventory:            InventorySystem      = null
var _entity_factory3d:            Factory3D            = null
var _entity_respawn:              RespawnService       = null
var _entity_data:                 DataService          = null
var _entity_stat_modifiers:       StatModifierService  = null
var _entity_combat:               CombatSystem         = null
var _entity_equipment:            EquipmentService     = null
var _entity_world:                WorldService         = null
var _entity_interaction_executor: InteractionExecutor = null
var _entity_player_states:        PlayerStateService   = null
## ADR-021 (R-5): für EntityContext.get_network_bridge() (QuestNPC,
## QuestCustomTrigger — report_domain_event()). In Produktion meist erst über
## set_network_bridge() (Late-Inject, siehe dort) gesetzt, nicht über
## set_entity_services() — NetworkBridge kommt bei WorldService selbst erst
## über inject_network_bridge() (Phase C8, Zyklus-Grund siehe dort).
var _entity_network_bridge:       NetworkBridge        = null
## ADR-033/Gold-Drops: für EntityContext.get_currency() (EnemyNPC._die()).
var _entity_currency:             CurrencyService      = null
## ADR-035: für EntityContext.get_trade_service() (Player._on_trade_requested()).
var _entity_trade:                TradeService         = null
## ADR-036: für EntityContext.get_pvp_death_loss() (Player._on_player_died()).
var _entity_pvp_death_loss:       PvPDeathLossService  = null
## ADR-036: für EntityContext.get_aura() (Player._on_thank_requested()).
var _entity_aura:                 AuraService          = null
## ADR-037: für EntityContext.get_death_loot() (Player._on_player_died(), PvE-Zweig).
var _entity_death_loot:           DeathLootService     = null
## ADR-039: für EntityContext.get_pickpocket() (Player._on_pickpocket_requested()).
var _entity_pickpocket:           PickpocketService    = null
## Für EntityContext.get_settings() (TouchInput: feste Joystick-Position, siehe
## joystick_pos_x/y in SettingsService.DEFAULTS).
var _entity_settings:             SettingsService       = null
## Für EntityContext.get_ambient_spawner() — Gravestone.gd (natürlich) und
## BuildPiece.gd (Spieler-Spawner-Grabstein, siehe dortiger Kommentar) melden
## sich hier an/ab, damit AmbientSpawnService periodisch Skelette in der Nähe
## nachspawnt. Siehe AmbientSpawnService-Klassenkommentar für das volle Design.
var _entity_ambient_spawner:     AmbientSpawnService = null
## ADR-051 Stufe 3: für EntityContext.get_quest_service() (DialogueTreeController).
var _entity_quest_service:        QuestService         = null

## ADR-015: peer_id DIESES laufenden Prozesses — separat von peer_id/owner_peer_id
## pro Entity. Gesetzt von WorldService sobald SessionManager es kennt (siehe
## on_world_scene_ready()), an jeden neuen EntityContext weitergereicht.
var _local_peer_id: int = 1
## FIX (2026-10-12): One-Shot-Guard für die Nicht-Autoritäts-Warnung in
## _generate_uuid() — siehe dort. Verhindert Log-Spam bei hunderten lokalen
## Chunk-Entity-Spawns auf Clients.
var _warned_local_uuid: bool = false
var _stats:      Dictionary = {
	"total_spawned":  0,
	"total_despawned": 0,
}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	_pool     = EntityPool.new(10)  # Default: 10 pro Typ
	_registry = EntityRegistry.new()

	# BUGFIX (2026-09-26, "Telemetrie meldet ständig verwaiste Nodes"): EntityPool.release()
	# entparent gepoolte (inaktive) Entities bisher komplett (nur `.pop_back()`/`.append()`
	# in einem RefCounted-Array, kein SceneTree-Parent) — Godots Performance-Monitor zählt
	# das per Definition als "verwaiste Node", siehe TelemetryService.record_memory_snapshot().
	# Nicht falsch-positiv im Sinn von "kaputt", aber trotzdem der eigentliche Anti-Pattern,
	# den der Zähler aufdecken soll — bei ~30 Typen mit Pool-Limits bis 20 erklärt das die im
	# Log beobachteten mehreren hundert bis über tausend "verwaisten" Nodes vollständig
	# (Größenordnung + Auf-und-Ab exakt passend zu Pool-Füllstand beim Chunk-Laden/-Entladen).
	# Fix: gepoolte Entities hängen jetzt in diesem unsichtbaren, inaktiven Container statt
	# komplett entparent zu werden — normale (nur unsichtbare) Kindnodes, keine Orphans mehr.
	_pool_container = Node3D.new()
	_pool_container.name = "EntityPoolContainer"
	# Siehe Feldkommentar oben — ohne diese beiden Zeilen ist der Container
	# zwar aus der Orphan-Node-Zählung raus, aber Kinder rendern/interagieren
	# trotzdem normal weiter, obwohl sie "despawnt" sein sollen.
	_pool_container.visible = false
	_pool_container.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_pool_container)
	_pool.set_park_container(_pool_container)

	# Pro-Typ-Limits: häufige Welt-Objekte größerer Pool, seltene Enemies kleiner.
	# Trees/Ores spawnen in hoher Dichte über mehrere Chunks gleichzeitig —
	# ein zu kleiner Pool erzwingt unnötige queue_free() + Neuinstanziierung.
	_pool.set_max_size_for("oak_tree",    20)
	_pool.set_max_size_for("willow_tree", 20)
	_pool.set_max_size_for("maple_tree",  20)
	_pool.set_max_size_for("iron_ore",    15)
	_pool.set_max_size_for("copper_ore",  15)
	# Enemies: seltener + größer im Memory → kleiner Pool als Default
	_pool.set_max_size_for("goblin",      6)
	_pool.set_max_size_for("skeleton",    6)
	# Special-Bedingungs-Gegner (Wunsch "Special Bedingungen") — bewusst
	# knapper Cap als goblin/skeleton: ConditionalEncounterService.ENCOUNTERS
	# deckelt ohnehin schon "max_nearby" pro Spieler, dieser Pool-Cap ist nur
	# das globale Server-weite Sicherheitsnetz (mehrere Spieler an
	# verschiedenen Orten könnten sonst theoretisch viele gleichzeitig halten).
	_pool.set_max_size_for("werewolf",    4)
	_pool.set_max_size_for("fog_wraith",  4)
	# Pets: eigene Identität pro Instanz (Name/Farbe/Besitzer) — Pooling würde
	# diese beim Wiederverwenden vermischen. 0 = nie pool-releasen, immer queue_free().
	_pool.set_max_size_for("pet", 0)
	# Bauteil-Ansichten: Geometrie hängt an der Definition und wird pro Chunk neu erzeugt — nie poolen.
	_pool.set_max_size_for("build_piece", 0)
	# Leiter-Ansichten: Geometrie ist pro Leiter einmalig — nie poolen.
	_pool.set_max_size_for("ladder", 0)

	AppLogger.log_info("EntityOrchestrator bereit.", LOG_CAT)

## Wird von WorldService.configure() aufgerufen nachdem EntityOrchestrator
## als Child hinzugefügt wurde. Muss vor initialize() gesetzt sein.
func set_event_bus(bus: IEventBus) -> void:
	_bus = bus

## ADR-015: von WorldService gesetzt, sobald SessionManager.get_local_peer_id()
## bekannt ist (siehe WorldService.on_world_scene_ready()). Vor dem ersten
## Aufruf ist der Default (1) korrekt für Tier 1 / Solo.
func set_local_peer_id(peer_id: int) -> void:
	_local_peer_id = peer_id

## Wird von WorldService.configure() aufgerufen sobald die Session-Deps bekannt sind.
## Nach diesem Aufruf nutzt spawn_entity() EntityContext.from_deps() — kein Services-Locator.
func set_entity_services(
	skill_system: SkillSystem,
	inventory: InventorySystem,
	factory3d: Factory3D,
	respawn: RespawnService,
	data: DataService,
	stat_modifiers: StatModifierService,
	combat: CombatSystem,
	equipment: EquipmentService,
	world: WorldService,
	interaction_executor: InteractionExecutor,
	player_states: PlayerStateService = null,
	network_bridge: NetworkBridge = null,
	currency: CurrencyService = null,
	trade: TradeService = null,
	pvp_death_loss: PvPDeathLossService = null,
	aura: AuraService = null,
	death_loot: DeathLootService = null,
	pickpocket: PickpocketService = null,
	settings: SettingsService = null,
	ambient_spawner: AmbientSpawnService = null,
	quest_service: QuestService = null
) -> void:
	_entity_skill_system         = skill_system
	_entity_inventory            = inventory
	_entity_factory3d            = factory3d
	_entity_respawn              = respawn
	_entity_data                 = data
	_entity_stat_modifiers       = stat_modifiers
	_entity_combat               = combat
	_entity_equipment            = equipment
	_entity_world                = world
	_entity_interaction_executor = interaction_executor
	_entity_player_states        = player_states
	if is_instance_valid(network_bridge):
		_entity_network_bridge = network_bridge
	_entity_currency = currency
	_entity_trade     = trade
	_entity_pvp_death_loss = pvp_death_loss
	_entity_aura = aura
	_entity_death_loot = death_loot
	_entity_pickpocket = pickpocket
	_entity_settings = settings
	_entity_ambient_spawner = ambient_spawner
	_entity_quest_service = quest_service
	AppLogger.log_debug("Entity-Services injiziert (inkl. PlayerStateService).", LOG_CAT)

## ADR-021 (R-5): analog zu set_local_peer_id() — NetworkBridge kommt bei
## WorldService erst über inject_network_bridge() (Phase S8.6/C8), lange nach
## set_entity_services() (Phase 4/configure()). WorldService ruft das hier auf,
## sobald es selbst injiziert wird, damit künftig gespawnte Entities (QuestNPC,
## QuestCustomTrigger) get_network_bridge() im EntityContext bekommen. Bereits
## gespawnte Entities behalten ihren zum Spawn-Zeitpunkt gültigen Context —
## das ist für die Spieldauer unkritisch, weil report_domain_event() vor der
## ersten echten Netzwerkverbindung (Tier 1) ohnehin nur lokal wirkt.
func set_network_bridge(network_bridge: NetworkBridge) -> void:
	_entity_network_bridge = network_bridge

## Initialisiert für eine neue Welt-Szene. Idempotent.
func initialize(world_root: Node3D) -> void:
	if not is_instance_valid(world_root):
		AppLogger.log_error("initialize() fehlgeschlagen: world_root ist null.", LOG_CAT)
		return

	if _world_root != null:
		AppLogger.log_warn(
			"initialize() erneut aufgerufen — vorheriger world_root '%s' wird ersetzt."
			% (_world_root.name if is_instance_valid(_world_root) else "<freigegeben>"),
			LOG_CAT
		)
		_entities.clear()

	_world_root = world_root
	AppLogger.log_info(
		"Initialisiert für World '%s'. Definitionen: %d."
		% [world_root.name, _registry.get_keys().size()],
		LOG_CAT
	)

## Aufgerufen bevor die Welt-Szene entladen wird.
func on_world_unloaded() -> void:
	var count := _entities.size()
	AppLogger.log_info("World-Unload: %d aktive Entities werden bereinigt." % count, LOG_CAT)

	for uuid in _entities.keys():
		var entity := _entities[uuid] as Node3D
		if is_instance_valid(entity):
			var type_id: String = entity.get_meta("entity_type", "")
			AppLogger.log_debug("on_despawn() → '%s' (uuid: %s)" % [type_id, uuid], LOG_CAT)
			if entity.has_method("on_despawn"):
				entity.on_despawn()
			# BUG-B-FIX: on_despawn() räumt nur den Entity-internen State auf,
			# entfernt den Node aber nicht aus dem SceneTree. Ohne dieses
			# remove_child()/queue_free() blieb der alte Node (insb. Pets) im
			# Baum hängen, während PetRestorer.restore() beim nächsten Laden
			# an derselben Position eine NEUE Instanz spawnt — die
			# überlappenden Collider führten zur physischen "Launch"-Trennung.
			# Betrifft vor allem den Hot-Reload-Pfad (siehe
			# WorldService.on_world_scene_ready(), get_entity_count() > 0),
			# bei dem World.tscn NICHT über change_scene_to_file neu geladen
			# wird und die alten Nodes daher nicht automatisch mit der Szene
			# gefreed werden.
			if entity.is_inside_tree():
				var parent := entity.get_parent()
				if parent:
					parent.remove_child(entity)
			entity.queue_free()
		else:
			AppLogger.log_debug("Entity '%s' bereits freigegeben." % uuid, LOG_CAT)

	_entities.clear()
	_world_root = null

	var pool_freed := _pool.flush()
	AppLogger.log_info(
		"EntityOrchestrator zurückgesetzt. Aktive: 0, Pool freigegeben: %d." % pool_freed,
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Öffentliche API — Definitionen
# ─────────────────────────────────────────────

## Registriert eine Entity-Definition. Muss vor spawn_entity() aufgerufen werden.
func register_definition(type_id: String, script_path: String, group: String = "") -> void:
	_registry.register(type_id, script_path, group)

# ─────────────────────────────────────────────
# Öffentliche API — Spawn / Despawn
# ─────────────────────────────────────────────

## Instanziiert eine Entity anhand type_id an position.
## config: optionale Konfiguration die an on_spawn() übergeben wird.
## peer_id: Besitzer-Peer der Entity (BUG-3: Default 1 = lokaler Spieler).
## Gibt die Entity zurück oder null bei Fehler.
func spawn_entity(type_id: String, position: Vector3, config: Dictionary = {}, peer_id: int = 1) -> Node3D:
	if not is_instance_valid(_world_root):
		AppLogger.log_error(
			"spawn_entity('%s') fehlgeschlagen: Kein world_root. initialize() aufgerufen?"
			% type_id,
			LOG_CAT
		)
		return null

	# Pool zuerst, dann frisch instanziieren
	var entity: Node3D = _pool.acquire(type_id)
	if not is_instance_valid(entity):
		entity = _registry.instantiate(type_id)
	if not is_instance_valid(entity):
		AppLogger.log_error("spawn_entity('%s'): Instanziierung fehlgeschlagen." % type_id, LOG_CAT)
		return null

	entity.position = position

	# BUGFIX (2026-09-15, "Goblins syncen nicht"): deterministischer,
	# inhaltsbasierter Node-Name statt Godots automatisch vergebenem
	# "@ClassName@123"/"TypeName2" usw. — der Grund für
	# "Node not found: World/Goblin_1031/MultiplayerSync": jeder Peer spawnt
	# Bäume/Erze/Tiere/NPCs unabhängig lokal (aus demselben, jetzt zwischen
	# Host/Client synchronisierten world_seed — siehe SessionManager.get_world_seed()),
	# aber Godots automatische Namensvergabe hängt vom internen, PRO PROZESS
	# unterschiedlichen Node-Zähler ab. MultiplayerSynchronizer sucht sein
	# Gegenstück beim anderen Peer aber rein über den NodePath — ohne
	# identischen Namen findet es nie das richtige (oder gar kein) Node.
	# Ein aus der Position abgeleiteter Name ist auf beiden Peers IDENTISCH,
	# unabhängig von Spawn-Reihenfolge/-Timing — wichtig für ChunkManager,
	# der Chunks je nach Spielerposition lädt, nicht synchron zwischen Peers.
	# Ausnahme "player": Position ist durch Bewegung nicht stabil — peer_id
	# ist die einzige über beide Peers hinweg garantiert identische Kennung.
	if type_id == "player":
		# BUGFIX (2026-09-16, "Charakter-Wechsel → Crash beim anderen Peer"):
		# peer_id ALLEIN ist als Name ungeeignet, sobald ein Peer die Welt
		# verlässt und mit einem NEUEN Charakter zurückkommt, OHNE die
		# Netzwerkverbindung zu trennen (z.B. "zurück zum Hauptmenü" →
		# neuer Charakter) — peer_id bleibt dabei gleich (derselbe ENet-Peer),
		# der neue Player-Node würde also wieder "Player_1" heißen wie der
		# alte, gerade zerstörte. Godots eigener Replikations-Cache
		# (SceneCacheInterface) verwechselt dann alten und neuen Node auf
		# demselben Pfad — das war die Ursache für den endlosen
		# "Node not found: .../MultiplayerSync"-Fehler beim anderen Peer bis
		# zum Absturz. config.player_id (die Charakter-UUID, siehe
		# WorldService-Closure für _spawn_player_cb und
		# NetworkBridge._rpc_spawn_remote_player()) ist pro Charakter/Session
		# garantiert neu — Fallback auf peer_id nur falls player_id (noch)
		# nicht bekannt ist (z.B. in Tests).
		var player_id: String = config.get("player_id", "")
		entity.name = "Player_%s" % player_id if not player_id.is_empty() else "Player_%d" % peer_id
	elif type_id == "pet":
		# FEATURE (2026-09-17, "Pets cross-peer sichtbar"): Pets bewegen sich
		# (folgen ihrem Besitzer) — die generische positions-basierte Namensvergabe
		# unten würde zwar beim SPAWN noch übereinstimmen (alle Peers bekommen
		# dieselbe pos aus demselben Broadcast-Payload, siehe
		# NetworkBridge.report_pet_spawned()), ist aber unnötig fragil (Floating-
		# Point-Rundung) und weniger lesbar als beim Player-Pendant. Gleiches
		# Muster wie dort: owner_player_id (Charakter-UUID des Besitzers, nicht
		# dessen peer_id — siehe Player-Namens-Kommentar oben für die Begründung,
		# warum peer_id bei Charakter-Wechsel ohne Trennung kollidieren kann)
		# ist pro Pet-Instanz stabil und über alle Peers identisch.
		var owner_player_id: String = config.get("owner_player_id", "")
		entity.name = "Pet_%s" % owner_player_id if not owner_player_id.is_empty() else "Pet_%d" % peer_id
	else:
		entity.name = "%s_%d_%d_%d" % [
			type_id,
			int(round(position.x * 100.0)),
			int(round(position.y * 100.0)),
			int(round(position.z * 100.0)),
		]

	var uuid := _generate_uuid()
	entity.set_meta("entity_uuid", uuid)
	entity.set_meta("entity_type", type_id)
	# ADR-025-Vorarbeit: "wem gehört diese Entity" wird ab hier NICHT mehr über
	# multiplayer_authority beantwortet (die z. B. für Player künftig einheitlich
	# beim Server liegen soll, ADR-025), sondern über dieses Meta — unabhängig
	# davon, wer gerade Netzwerk-Autorität über das Node hat. Ersetzt die bisher
	# fünf Stellen, die "wem gehört das" über Authority-Abgleich beantwortet
	# hatten (siehe TODO "BLOCKER für ADR-025/026-Umsetzung").
	entity.set_meta("owner_peer_id", peer_id)
	# Für EnemyCullingService (Grace Period nach Spawn) — bewusst generisch
	# auf JEDER Entity gesetzt, nicht nur Gegnern: "wie lange existiert das
	# schon" ist eine naheliegende Frage für künftige Systeme, keine
	# Gegner-spezifische Sonderlogik hier im Orchestrator nötig.
	entity.set_meta("spawned_at", Time.get_unix_time_from_system())

	_world_root.add_child(entity)  # ← _ready() feuert hier


	# ADR-025 (abgelöst: E-1/"Authority auf den richtigen Peer setzen"): Player-Nodes
	# bekamen hier früher die Netzwerk-Autorität des besitzenden Clients zugewiesen
	# (client-autoritatives Movement). Seit ADR-025 gilt für Player-Nodes dieselbe
	# Regel wie für jede andere Entity (EnemyNPC/Tiere/Harvestables): Autorität = 1
	# (Server), gesetzt in der Entity's eigener _ready() (Player.gd macht das jetzt
	# genau wie EnemyNPC/AnimalBase/HarvestableEntity). Kein Override mehr nötig —
	# und keiner mehr erlaubt: ein Override hier würde Player.gd's eigene
	# set_multiplayer_authority(1) aus _ready() wieder zurückdrehen und den
	# ADR-025-Kern (Server simuliert autoritativ) unterlaufen. "Wem gehört die
	# Entity" bleibt weiterhin ausschließlich über das "owner_peer_id"-Meta oben
	# beantwortet — diese Frage war der einzige Grund für den früheren Override.
	_entities[uuid] = entity

	if entity.has_method("on_spawn"):
		var ctx := EntityContext.from_deps(
			_entity_skill_system, _entity_inventory, _entity_factory3d,
			_entity_respawn, _entity_data, _entity_stat_modifiers,
			_entity_combat, _entity_equipment, _entity_world,
			_entity_interaction_executor, peer_id, _bus, _local_peer_id,
			_entity_network_bridge, _entity_currency, _entity_trade,
			_entity_pvp_death_loss, _entity_aura, _entity_death_loot, _entity_pickpocket,
			_entity_settings, _entity_ambient_spawner, _entity_quest_service
		)
		# type_id in config injizieren damit Entities wie EnemyNPC ihren
		# EntityRegistry-Key kennen (z.B. für enemy_killed-Signal).
		# Aufrufende können type_id in config überschreiben falls nötig.
		if not config.has("type_id"):
			config["type_id"] = type_id
		entity.on_spawn(config, ctx)

	# Inject PlayerStateService direkt in Entities die es unterstützen (z.B. TouchInput via Player).
	# Separate Injection nach on_spawn() da Player erst dort seinen input-Node aufbaut.
	if entity.has_method("inject_player_states") and is_instance_valid(_entity_player_states):
		entity.inject_player_states(_entity_player_states)

	# FEATURE (2026-09-17, "Pets cross-peer sichtbar"): NACH on_spawn(), damit
	# entity.name (deterministisch, siehe oben) und die volle config feststehen.
	# _is_replica_spawn: von NetworkBridge._rpc_spawn_remote_pet() gesetzt, wenn
	# DIESER spawn_entity()-Aufruf selbst schon die Kopie EINES Broadcasts ist —
	# sonst würde jede empfangene Pet-Kopie sofort wieder einen eigenen Report
	# auslösen (Echo-Schleife, kein Endlos-Loop dank Idempotenz-Check auf der
	# Empfängerseite, aber unnötiger Traffic). peer_id ist hier bewusst NICHT
	# das Kriterium: _on_interacted() läuft auf der AUTORITÄT, auch wenn ein
	# ANDERER Spieler (nicht der lokale) das Tier gefangen hat — die Autorität
	# muss trotzdem melden, unabhängig davon, wem das Pet gehört.
	if type_id == "pet" and not config.get("_is_replica_spawn", false) and is_instance_valid(_entity_network_bridge):
		_entity_network_bridge.report_pet_spawned(entity.name, peer_id, position, config)

	_stats["total_spawned"] += 1
	_bus.world().emit_entity_spawned(type_id, entity, position)

	AppLogger.log_info(
		"Entity gespawnt: type='%s' uuid='%s' pos=%s" % [type_id, uuid, str(position)],
		LOG_CAT
	)
	return entity

## Despawnt eine Entity anhand UUID. Gibt sie in den Pool zurück wenn möglich.
## Gibt eine Entity frei, OHNE dass sie im SPIELsinn "verschwunden" ist (Chunk wird entladen,
## Ansicht eines Bauteils wird abgebaut). Unterschied zu despawn_entity():
##   - ruft on_unload() (falls vorhanden), sonst on_despawn() — HarvestableEntity.on_despawn()
##     würde das Objekt als ABGEERNTET markieren (Baum bliebe für immer weg), on_unload() nicht;
##   - emittiert KEIN entity_despawned — RespawnService würde darauf einen Respawn einplanen
##     und die Entity beim nächsten Laden doppelt entstehen lassen;
##   - zählt nicht als total_despawned.
## Gepoolt/freigegeben wird wie beim normalen Despawn.
func unload_entity(uuid: String) -> void:
	if uuid.is_empty() or not _entities.has(uuid):
		return
	var entity := _entities[uuid] as Node3D
	_entities.erase(uuid)
	if not is_instance_valid(entity):
		return
	var type_id: String = entity.get_meta("entity_type", "")
	if entity.has_method("on_unload"):
		entity.on_unload()
	elif entity.has_method("on_despawn"):
		entity.on_despawn()
	if not _pool.release(type_id, entity):
		entity.queue_free()

func despawn_entity(uuid: String) -> void:
	if uuid.is_empty():
		AppLogger.log_warn("despawn_entity(): UUID ist leer!", LOG_CAT)
		return

	if not _entities.has(uuid):
		AppLogger.log_warn("despawn_entity('%s'): UUID nicht in aktiven Entities." % uuid, LOG_CAT)
		return

	var entity := _entities[uuid] as Node3D
	var type_id: String = entity.get_meta("entity_type", "") if is_instance_valid(entity) else ""

	_entities.erase(uuid)
	_stats["total_despawned"] += 1

	if not is_instance_valid(entity):
		AppLogger.log_debug("Entity '%s' war bereits freigegeben." % uuid, LOG_CAT)
		_bus.world().emit_entity_despawned(type_id, uuid, Vector3.ZERO)
		return

	var entity_pos := entity.global_position

	if entity.has_method("on_despawn"):
		entity.on_despawn()

	if _pool.release(type_id, entity):
		AppLogger.log_debug("Entity '%s' (%s) → Pool zurückgegeben." % [uuid, type_id], LOG_CAT)
	else:
		entity.queue_free()
		AppLogger.log_debug("Entity '%s' (%s) → queue_free()." % [uuid, type_id], LOG_CAT)

	_bus.world().emit_entity_despawned(type_id, uuid, entity_pos)

# ─────────────────────────────────────────────
# Öffentliche API — Abfragen
# ─────────────────────────────────────────────

## Gibt die interne EntityRegistry zurück.
## Wird von WorldService._setup_multiplayer_spawner() genutzt
## um die Path→TypeId-Map für Custom-Spawn-Signale zu bauen.
func get_registry() -> EntityRegistry:
	return _registry

func get_entities_in_group(group: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for uuid in _entities:
		var entity := _entities[uuid] as Node3D
		if is_instance_valid(entity) and entity.is_in_group(group):
			result.append(entity)
	return result

func get_entity_count() -> int:
	return _entities.size()

func get_entity(uuid: String) -> Node3D:
	return _entities.get(uuid)

## BUGFIX (2026-09-15, "Sterben soll auch synced werden"): Gegenstück zu
## get_entity() für den Fall, dass ein anderer Peer nur den DETERMINISTISCHEN
## Node-Namen kennt (siehe spawn_entity()-Kommentar zur Namensvergabe), nicht
## die lokale (pro Peer zufällige) uuid — z.B. NetworkBridge.broadcast_to_all_peers()
## via "entity_despawned" (WorldService._on_broadcast_event_received()). Lineare
## Suche ist hier bewusst in Kauf genommen: kommt nur bei Netzwerk-Events vor,
## nicht im Hot-Path.
func get_entity_uuid_by_name(entity_name: String) -> String:
	for uuid in _entities:
		var entity := _entities[uuid] as Node3D
		if is_instance_valid(entity) and entity.name == entity_name:
			return uuid
	return ""

## DIAGNOSE (2026-09-16, "Guest kann immer noch nichts abbauen"): Objekt-Identitäts-
## Suche statt Namens-Vergleich — falls get_entity_uuid_by_name() leer liefert,
## zeigt das hier, ob das Node ÜBERHAUPT (unter irgendeinem Namen) in _entities
## steckt, oder ob es dort komplett fehlt (dann liegt das Problem VOR der
## Registrierung, nicht bei der Namensauflösung).
func has_entity_instance(entity_node: Node3D) -> bool:
	for uuid in _entities:
		if _entities[uuid] == entity_node:
			return true
	return false

## ADR-023: einziger kanonischer Weg, wie ein Netzwerk-Request eine konkrete
## Server-Entity referenziert. Löst `uuid` auf UND prüft Plausibilität —
## Aufrufer (z. B. ein InteractionResolver) bricht bei `null` ohne Wirkung ab.
##
## Gibt null zurück wenn:
##   - keine Entity mit dieser uuid (aktuell) existiert
##   - kein Player-Node mit owner_peer_id == peer_id gefunden wird
##   - die Distanz zwischen Player und Entity max_range überschreitet
##
## max_range ist bewusst kein globaler Default, sondern wird pro Interaktionsart
## vom Aufrufer übergeben (siehe NetworkContract.gd) — ein großzügiger
## Kompatibilitäts-Fallback wäre derselbe Fehler wie ein stiller peer_id=1-
## Default, nur in Distanz-Form.
##
## WICHTIG: dies ist ein Plausibilitätsfilter, kein Movement-Anti-Cheat.
## `player.global_position` ist client-reported (Movement-Autorität liegt beim
## besitzenden Peer, replizert per MultiplayerSynchronizer) — ein modifizierter
## Client könnte weiterhin eine falsche eigene Position melden. Siehe ADR-023,
## Abschnitt "Negativ/Risiken", und ADR-024/025 für die tatsächliche
## Movement-Validierung.
## Bugfix 2026-09-26 ("Pets können Ressourcen manchmal nicht abbauen/sammeln"):
## [param actor_uuid] misst die Reichweite optional ab einer ANDEREN, bereits im
## EntityOrchestrator registrierten Entity statt zwingend ab dem Player-Node von
## peer_id — z.B. dem Pet selbst, das die Aktion tatsächlich ausführt (siehe
## PetAbilityComponent._complete_harvest()/_do_attack()). VORHER wurde
## IMMER die Distanz Besitzer-Spieler↔Ziel geprüft, obwohl das tatsächlich
## handelnde Pet (SEARCH_RADIUS 7m um seine EIGENE Position, siehe dortiger
## Klassenkommentar) durchaus weiter vom Besitzer als max_range entfernt sein
## kann, während es trotzdem direkt neben dem Ziel steht — resolve_for_player()
## lehnte die Aktion dann fälschlich als "außerhalb Reichweite" ab (Log-Warn,
## kein Crash, aber eben nie ein Ergebnis). Leer (Default) = unverändertes
## Verhalten für jede normale Spieler-Interaktion.
## Sicherheitsäquivalent zu max_range selbst (siehe dortiger Kommentar): auch
## actor_uuid zeigt auf eine servereigene, bereits registrierte Entity mit
## ihrer eigenen (bei Pets: replizierten) Position — NIE eine roh vom Client
## übertragene Position/Distanz, sonst wäre die Prüfung wertlos.
func resolve_for_player(uuid: String, peer_id: int, max_range: float, actor_uuid: String = "") -> Node3D:
	var entity := get_entity(uuid)
	if not is_instance_valid(entity):
		AppLogger.log_warn(
			"resolve_for_player('%s'): keine Entity mit dieser UUID (unbekannt oder bereits despawnt)."
			% uuid,
			LOG_CAT
		)
		return null

	var actor: Node3D = null
	var actor_label := "peer_id=%d" % peer_id
	if not actor_uuid.is_empty():
		actor = get_entity(actor_uuid)
		if is_instance_valid(actor):
			actor_label = "actor_uuid=%s (Besitzer peer_id=%d)" % [actor_uuid, peer_id]
		else:
			AppLogger.log_warn(
				"resolve_for_player('%s'): actor_uuid='%s' nicht gefunden — falle auf Spieler-Position zurück."
				% [uuid, actor_uuid],
				LOG_CAT
			)

	if not is_instance_valid(actor):
		actor = find_player_by_id(peer_id)
		if not is_instance_valid(actor):
			AppLogger.log_warn(
				"resolve_for_player('%s'): kein Player-Node für peer_id=%d gefunden."
				% [uuid, peer_id],
				LOG_CAT
			)
			return null

	var distance := actor.global_position.distance_to(entity.global_position)
	if distance > max_range:
		AppLogger.log_warn(
			"resolve_for_player('%s'): %s außerhalb Reichweite (%.1f > max %.1f)."
			% [uuid, actor_label, distance, max_range],
			LOG_CAT
		)
		return null

	# DIAGNOSE (2026-10-01, "Pet baut nur ab, wenn ich es nah hinlotse"): bisher
	# wurde hier nur der ABLEHNUNGS-Fall geloggt — ob eine erfolgreiche
	# Interaktion tatsächlich ab dem Pet (actor_uuid) oder (weil actor_uuid
	# fehlte/ungültig war) ab dem BESITZER gemessen wurde, war unsichtbar.
	# actor_label unterscheidet das bereits oben, hier nur noch sichtbar machen.
	AppLogger.log_debug(
		"resolve_for_player('%s'): OK — %s, Distanz=%.2f <= max %.2f."
		% [uuid, actor_label, distance, max_range],
		LOG_CAT
	)
	return entity

## ADR-027: öffentlicher, kanonischer "Player-Node für peer_id"-Lookup —
## ersetzt die vormals private Kopie. Nutzt dasselbe Muster wie
## IEntityContext.get_local_player() / PetComponent._find_owner(), aber für
## einen BELIEBIGEN peer_id statt nur den lokalen Peer. Aufrufbar von
## außerhalb (z. B. WorldService.get_player_by_id()), damit Services wie
## EquipmentService, die keinen IEntityContext/IUIContext haben, denselben
## Lookup nutzen können statt ihn ein sechstes Mal zu duplizieren.
func find_player_by_id(peer_id: int) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if p is Node3D and p.get_meta("owner_peer_id", 1) == peer_id:
			return p as Node3D
	return null

func get_debug_info() -> Dictionary:
	return {
		"world_root":       _world_root.name if is_instance_valid(_world_root) else "<null>",
		"active_entities":  _entities.size(),
		"definitions":      _registry.get_keys(),
		# BUGFIX (2026-09-26, "Telemetrie meldet ständig verwaiste Nodes"): Limits statt nur
		# Größe (get_sizes_with_limits() statt get_sizes()) — für die Diagnoseansicht (Terminal-
		# Befehl `pool`, AdminPanelUI) ist "17 von 20" aussagekräftiger als nur "17", gerade um
		# zu zeigen, dass ein hoher Wert regulär durch die Pool-Limits gedeckelt ist und nicht
		# unbegrenzt weiterwächst (siehe _ready()-Kommentar zum _pool_container-Fix).
		"pool_sizes":       _pool.get_sizes_with_limits(),
		"pool_hits":        _pool.pool_hits,
		"pool_misses":      _pool.pool_misses,
		"stats":            _stats.duplicate(),
	}

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _generate_uuid() -> String:
	# Kein get_ticks_usec() (Kollisionsgefahr bei gleichzeitigen Clients).
	# Tier 1 (kein Peer gesetzt): Guard ist immer true → verhält sich wie bisher.
	# Tier 2/3: nur die Autorität darf UUIDs vergeben (Phase 4 verdrahtet den RPC-Rückweg).
	# FIX (2026-10-12, IT-03 rot / Issue #5): assert() ersetzt. Clients spawnen
	# Welt-Entities (Bäume/Erze/Tiere via ChunkEntitySpawner) BEWUSST lokal aus
	# dem synchronisierten world_seed — _generate_uuid() läuft dadurch regulär
	# auf Nicht-Autoritäten. Das assert brach die Funktion ab → jede Client-
	# Entity bekam uuid='' (alle kollidierten im _entities-Dict auf dem Key ''),
	# zusätzlich hunderte SCRIPT ERRORs pro Chunk-Load im CI-Log. Ein assert ist
	# hier schlicht falsch: lokales World-Gen auf Clients ist Design (siehe
	# spawn_entity()-Namens-Kommentar "jeder Peer spawnt ... unabhängig lokal").
	# Die UUID einer Client-Entity ist rein lokal (nur die Autorität persistiert
	# world_state, siehe WorldService.configure()-Guard) — Warnung einmal pro
	# Lauf statt assert, danach normal weiterlaufen lassen.
	if is_instance_valid(multiplayer) and multiplayer.has_multiplayer_peer() \
			and not multiplayer.is_server():
		if not _warned_local_uuid:
			_warned_local_uuid = true
			AppLogger.log_warn(
				"_generate_uuid() auf Nicht-Autorität (Client-World-Gen) — lokale UUID erzeugt; nur die Autorität vergibt netzweit gültige UUIDs.",
				LOG_CAT
			)
	var a := randi()
	var b := randi()
	var c := randi()
	var d := randi()
	# Version-Bits setzen: version=4 (0100xxxx), variant=10xx (RFC 4122)
	c = (c & 0x0FFF) | 0x4000        # version 4
	d = (d & 0x3FFFFFFF) | 0x80000000  # variant 10xx
	return "%08x-%04x-%04x-%04x-%04x%08x" % [
		a,
		(b >> 16) & 0xFFFF,
		c & 0xFFFF,
		(c >> 16) & 0xFFFF,
		d & 0xFFFF,
		d >> 16
	]
