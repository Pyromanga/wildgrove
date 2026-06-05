extends Node

## Services — Typisierter DependencyContainer.
##
## AutoLoad #4 (nach Logger, EventBus, SimpleTerminal).
## Wird leer gestartet und von ServiceOrchestrator in Phase 7 befüllt.
##
## WICHTIG: Niemals Services.xyz in configure() aufrufen — Services ist zu diesem
## Zeitpunkt noch nicht befüllt. Services.xyz ist erst ab on_ready() sicher.

# ─────────────────────────────────────────────
# Infrastruktur-Services
# ─────────────────────────────────────────────
var ticker: ServiceTicker = null
var scene: SceneManager = null

# ─────────────────────────────────────────────
# Datenhaltung
# ─────────────────────────────────────────────
var save_system: SaveSystem = null
var game_save: GameSaveService = null
var data: DataService = null

# ─────────────────────────────────────────────
# Gameplay-Services
# ─────────────────────────────────────────────
var inventory: InventorySystem = null
var skill_system: SkillSystem = null
var quest: QuestService = null
var player_states: PlayerStateService = null

# ─────────────────────────────────────────────
# World & Entities
# ─────────────────────────────────────────────
var world: WorldService = null
var factory3d: Factory3D = null
var builder: InteractionBuilder = null

# ─────────────────────────────────────────────
# UI
# ─────────────────────────────────────────────
var ui_factory: UIFactory = null
var hud: HUDManager = null

# ─────────────────────────────────────────────
# Game Flow
# ─────────────────────────────────────────────
var game_manager: GameManager = null


# ─────────────────────────────────────────────
# Intern — aufgerufen von ServiceOrchestrator
# ─────────────────────────────────────────────


func populate(registry: ServiceRegistry) -> void:
	var t := Logger.log_begin("Services.populate()", "Services")

	ticker = _resolve(registry, "ticker") as ServiceTicker
	scene = _resolve(registry, "scenemanager") as SceneManager
	save_system = _resolve(registry, "savesystem") as SaveSystem
	game_save = _resolve(registry, "gamesave") as GameSaveService
	data = _resolve(registry, "data") as DataService
	inventory = _resolve(registry, "inventory") as InventorySystem
	skill_system = _resolve(registry, "skill_system") as SkillSystem
	factory3d = _resolve(registry, "factory3d") as Factory3D
	builder = _resolve(registry, "builder") as InteractionBuilder
	world = _resolve(registry, "world") as WorldService
	ui_factory = _resolve(registry, "ui_factory") as UIFactory
	game_manager = _resolve(registry, "gamemanager") as GameManager
	player_states = _resolve(registry, "playerstates") as PlayerStateService
	quest = _resolve(registry, "quest") as QuestService
	hud = _resolve(registry, "hud") as HUDManager

	Logger.log_end("Services.populate()", t, "Services")
	Logger.log_info("DependencyContainer befüllt.", "Services")


func clear() -> void:
	ticker = null
	scene = null
	save_system = null
	game_save = null
	data = null
	inventory = null
	skill_system = null
	factory3d = null
	builder = null
	world = null
	ui_factory = null
	game_manager = null
	player_states = null
	quest = null
	hud = null
	Logger.log_debug("DependencyContainer geleert.", "Services")


# ─────────────────────────────────────────────
# Hilfsfunktionen
# ─────────────────────────────────────────────


func _resolve(registry: ServiceRegistry, key: String) -> Object:
	var svc: Object = registry.get_service(key)
	if svc == null:
		Logger.log_warn("Services.populate: '%s' nicht in Registry." % key, "Services")
	return svc


## Gibt eine lesbare Übersicht aller Services zurück. Für Debug-Commands.
func get_status_report() -> Dictionary:
	return {
		"ticker": is_instance_valid(ticker),
		"scene": is_instance_valid(scene),
		"save_system": is_instance_valid(save_system),
		"game_save": is_instance_valid(game_save),
		"data": is_instance_valid(data),
		"inventory": is_instance_valid(inventory),
		"skill_system": is_instance_valid(skill_system),
		"factory3d": is_instance_valid(factory3d),
		"builder": is_instance_valid(builder),
		"world": is_instance_valid(world),
		"ui_factory": is_instance_valid(ui_factory),
		"game_manager": is_instance_valid(game_manager),
		"player_states": is_instance_valid(player_states),
		"quest": is_instance_valid(quest),
		"hud": is_instance_valid(hud),
	}
