# res://scripts/platform/EntityContext.gd
class_name EntityContext extends IEntityContext

## EntityContext — Produktions-Implementierung von IEntityContext.
##
## Wird von EntityOrchestrator erstellt und in on_spawn() injiziert.
## Hält keine Services selbst — delegiert an die übergebenen Instanzen.
##
## Entities reichen diesen Wert an Service-Aufrufe durch statt player_id selbst
## herzuleiten — Abschirmung gemäß ADR-006 (kein Autoload-Zugriff in Entities).

var _skill_system:    Object = null
var _inventory:       Object = null
var _factory:         Object = null
var _respawn:         Object = null
var _data:            Object = null
var _stat_modifiers:  Object = null
var _combat_system:   Object = null
var _equipment:       Object = null
var _currency:        Object = null
var _trade:            Object = null
var _pvp_death_loss:   Object = null  ## ADR-036
var _aura:             Object = null  ## ADR-036
var _death_loot:       Object = null  ## ADR-037
var _pickpocket:       Object = null  ## ADR-039
var _world:           Object = null
var _interaction_executor: Object = null
var _bus: IEventBus = null
## ADR-021 (R-5): NetworkBridge für report_domain_event() (QuestNPC,
## QuestCustomTrigger — Entities ohne authority-geguardeten Interaktions-Hook).
var _network: Object = null
## Für EntityContext.get_settings() — TouchInput (feste Joystick-Position).
var _settings: Object = null
## AmbientSpawnService — für Gravestone.gd/BuildPiece.gd (Spawner-Grabsteine),
## siehe get_ambient_spawner() Klassenkommentar in IEntityContext.gd.
var _ambient_spawner: Object = null
## ADR-051 Stufe 3: für EntityContext.get_quest_service() (DialogueTreeController
## Bedingungs-Auswertung über fremde Quests, siehe IEntityContext.gd Kommentar).
var _quest_service: Object = null

## peer_id des Spielers, dem diese Entity gehört.
## Default 1 = lokaler Spieler (Tier 1 / Solo-Modus, kein MultiplayerPeer gesetzt).
## In Tier 2/3 wird dieser Wert von EntityOrchestrator.spawn_entity() gesetzt.
var owner_peer_id: int = 1

## ADR-015: peer_id DIESES laufenden Prozesses — nicht zu verwechseln mit
## owner_peer_id oben (das ist "wem gehört DIESE Entity", z.B. 1 für ein
## Weltobjekt egal welcher Spieler gerade damit interagiert). Kommt von
## EntityOrchestrator, das es wiederum von WorldService/SessionManager erhält.
var _local_peer_id: int = 1

## Erstellt einen EntityContext aus injizierten Service-Instanzen.
## Canonical-Pfad: EntityOrchestrator.spawn_entity() nutzt diesen Constructor
## nach EntityOrchestrator.set_entity_services() — kein Services-Locator-Zugriff.
static func from_deps(
	skill_system: SkillSystem,
	inventory: InventorySystem,
	factory: Factory3D,
	respawn: RespawnService,
	data: DataService,
	stat_modifiers: StatModifierService,
	combat_system: CombatSystem,
	equipment: EquipmentService,
	world: WorldService,
	interaction_executor: InteractionExecutor,
	peer_id: int = 1,
	bus: IEventBus = null,
	local_peer_id: int = 1,
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
) -> EntityContext:
	var ctx := EntityContext.new()
	ctx._skill_system         = skill_system
	ctx._inventory            = inventory
	ctx._factory              = factory
	ctx._respawn              = respawn
	ctx._data                 = data
	ctx._stat_modifiers       = stat_modifiers
	ctx._combat_system        = combat_system
	ctx._equipment            = equipment
	ctx._world                = world
	ctx._interaction_executor = interaction_executor
	ctx.owner_peer_id         = peer_id
	ctx._bus                  = bus
	ctx._local_peer_id        = local_peer_id
	ctx._network              = network_bridge
	ctx._currency             = currency
	ctx._trade                = trade
	ctx._pvp_death_loss       = pvp_death_loss
	ctx._aura                 = aura
	ctx._death_loot           = death_loot
	ctx._pickpocket           = pickpocket
	ctx._settings             = settings
	ctx._ambient_spawner    = ambient_spawner
	ctx._quest_service        = quest_service
	return ctx

## Erstellt einen minimalen Kontext für Unit-Tests.
## Felder können danach direkt gesetzt werden:
##   var ctx = EntityContext.for_test()
##   ctx._skill_system = MockSkillSystem.new()
##   ctx.owner_peer_id = 42
static func for_test(peer_id: int = 1) -> EntityContext:
	var ctx := EntityContext.new()
	ctx.owner_peer_id  = peer_id
	ctx._local_peer_id = peer_id
	return ctx

# ─────────────────────────────────────────────
# IEntityContext Overrides
# ─────────────────────────────────────────────

func get_skill_system() -> SkillSystem:
	return _skill_system as SkillSystem

func get_inventory() -> InventorySystem:
	return _inventory as InventorySystem

func get_factory() -> Factory3D:
	return _factory as Factory3D

func get_respawn() -> RespawnService:
	return _respawn as RespawnService

func get_data() -> DataService:
	return _data as DataService

func get_stat_modifiers() -> StatModifierService:
	return _stat_modifiers as StatModifierService

func get_combat_system() -> CombatSystem:
	return _combat_system as CombatSystem

func get_equipment() -> EquipmentService:
	return _equipment as EquipmentService

func get_currency() -> CurrencyService:
	return _currency as CurrencyService

func get_trade_service() -> TradeService:
	return _trade as TradeService

func get_pvp_death_loss() -> PvPDeathLossService:
	return _pvp_death_loss as PvPDeathLossService

func get_aura() -> AuraService:
	return _aura as AuraService

func get_death_loot() -> DeathLootService:
	return _death_loot as DeathLootService

func get_pickpocket() -> PickpocketService:
	return _pickpocket as PickpocketService

func get_network_bridge() -> NetworkBridge:
	return _network as NetworkBridge

func get_world() -> WorldService:
	return _world as WorldService

func get_interaction_executor() -> InteractionExecutor:
	return _interaction_executor as InteractionExecutor

func get_factory3d() -> Factory3D:
	return _factory as Factory3D

func get_event_bus() -> IEventBus:
	return _bus

func get_settings() -> SettingsService:
	return _settings as SettingsService

func get_ambient_spawner() -> AmbientSpawnService:
	return _ambient_spawner as AmbientSpawnService

func get_quest_service() -> QuestService:
	return _quest_service as QuestService

func get_local_peer_id() -> int:
	return _local_peer_id

func get_owner_peer_id() -> int:
	return owner_peer_id
