extends Node

## Services — Typisierter DependencyContainer.
##
## AutoLoad #4 (nach Logger, EventBus, SimpleTerminal).
## Wird leer gestartet und von ServiceOrchestrator in Phase 6 befüllt.

# ─────────────────────────────────────────────
# Typisierte Service-Shortcuts
# ─────────────────────────────────────────────
var ticker: ServiceTicker = null
var scene: SceneManager = null
var save_system: SaveSystem = null
var game_save: GameSaveService = null
var data: DataService = null
var inventory: InventorySystem = null
var skill_system: SkillSystem = null
var factory3d: Factory3D = null
var builder: InteractionBuilder = null
var world: WorldService = null
var ui_factory: UIFactory = null
var game_manager: GameManager = null
var player_states: PlayerStateService = null
var quest: QuestService = null
var hud: HUDManager = null


# ─────────────────────────────────────────────
# Intern — aufgerufen von ServiceOrchestrator
# ─────────────────────────────────────────────

func populate(registry: ServiceRegistry) -> void:
	ticker       = _resolve(registry, "ticker")       as ServiceTicker
	scene        = _resolve(registry, "scenemanager") as SceneManager
	save_system  = _resolve(registry, "savesystem")   as SaveSystem
	game_save    = _resolve(registry, "gamesave")     as GameSaveService
	data         = _resolve(registry, "data")         as DataService
	inventory    = _resolve(registry, "inventory")    as InventorySystem
	skill_system = _resolve(registry, "skill_system") as SkillSystem
	factory3d    = _resolve(registry, "factory3d")    as Factory3D
	builder      = _resolve(registry, "builder")      as InteractionBuilder
	world        = _resolve(registry, "world")        as WorldService
	ui_factory   = _resolve(registry, "ui_factory")   as UIFactory
	game_manager = _resolve(registry, "gamemanager")  as GameManager
	player_states = _resolve(registry, "playerstates") as PlayerStateService
	quest        = _resolve(registry, "quest")        as QuestService
	hud          = _resolve(registry, "hud")          as HUDManager
	Logger.log_info("DependencyContainer befüllt.", "Services")


func clear() -> void:
	ticker       = null
	scene        = null
	save_system  = null
	game_save    = null
	data         = null
	inventory    = null
	skill_system = null
	factory3d    = null
	builder      = null
	world        = null
	ui_factory   = null
	game_manager = null
	player_states = null
	quest        = null
	hud          = null
	Logger.log_debug("DependencyContainer geleert.", "Services")


# ─────────────────────────────────────────────
# Hilfsfunktion
# ─────────────────────────────────────────────

func _resolve(registry: ServiceRegistry, key: String) -> Object:
	var svc: Object = registry.get_service(key)
	if svc == null:
		Logger.log_warn("Services.populate: '%s' nicht in Registry." % key, "Services")
	return svc
