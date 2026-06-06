extends Node

## Services — Typisierter Service-Locator / Dependency-Container.
##
## AutoLoad #4 (nach Logger, EventBus, SimpleTerminal).
## Wird leer gestartet und von ServiceOrchestrator in Phase 7 befüllt.
##
## WICHTIG: Niemals Services.xyz in configure() aufrufen — Services ist zu diesem
## Zeitpunkt noch nicht befüllt. Services.xyz ist erst ab on_ready() sicher.
##
## REFACTOR (Session 4):
##   factory3d entfernt → lebt jetzt als Services.world.factory3d
##   ui_canvas entfernt → UICanvasService war dead code (nie aufgerufen)
##   reward_dispatcher hinzugefügt (neuer Service)

# ─────────────────────────────────────────────
# Infrastruktur-Services
# ─────────────────────────────────────────────
var ticker: ServiceTicker = null
var scene: SceneManager   = null

# ─────────────────────────────────────────────
# Datenhaltung
# ─────────────────────────────────────────────
var save_system: SaveSystem      = null
var game_save:   GameSaveService = null
var data:        DataService     = null

# ─────────────────────────────────────────────
# Gameplay-Services
# ─────────────────────────────────────────────
var inventory:    InventorySystem    = null
var skill_system: SkillSystem        = null
var quest:        QuestService       = null
var player_states: PlayerStateService = null
var reward_dispatcher: RewardDispatcher = null

# ─────────────────────────────────────────────
# World & Entities
# ─────────────────────────────────────────────

## WorldService hält factory3d als Instanz-Variable.
## Zugriff: Services.world.factory3d
var world:                WorldService        = null
var interaction_executor: InteractionExecutor = null

# ─────────────────────────────────────────────
# UI
# ─────────────────────────────────────────────
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

	ticker               = _resolve(registry, "ticker")               as ServiceTicker
	scene                = _resolve(registry, "scenemanager")         as SceneManager
	save_system          = _resolve(registry, "savesystem")           as SaveSystem
	game_save            = _resolve(registry, "gamesave")             as GameSaveService
	data                 = _resolve(registry, "data")                 as DataService
	inventory            = _resolve(registry, "inventory")            as InventorySystem
	skill_system         = _resolve(registry, "skill_system")         as SkillSystem
	interaction_executor = _resolve(registry, "interaction_executor") as InteractionExecutor
	world                = _resolve(registry, "world")                as WorldService
	game_manager         = _resolve(registry, "gamemanager")          as GameManager
	player_states        = _resolve(registry, "playerstates")         as PlayerStateService
	quest                = _resolve(registry, "quest")                as QuestService
	hud                  = _resolve(registry, "hud")                  as HUDManager
	reward_dispatcher    = _resolve(registry, "reward_dispatcher")    as RewardDispatcher

	Logger.log_end("Services.populate()", t, "Services")
	Logger.log_info("DependencyContainer befüllt.", "Services")


func clear() -> void:
	ticker             = null
	scene              = null
	save_system        = null
	game_save          = null
	data               = null
	inventory          = null
	skill_system       = null
	interaction_executor = null
	world              = null
	game_manager       = null
	player_states      = null
	quest              = null
	hud                = null
	reward_dispatcher  = null
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
		"ticker":             is_instance_valid(ticker),
		"scene":              is_instance_valid(scene),
		"save_system":        is_instance_valid(save_system),
		"game_save":          is_instance_valid(game_save),
		"data":               is_instance_valid(data),
		"inventory":          is_instance_valid(inventory),
		"skill_system":       is_instance_valid(skill_system),
		"interaction_executor": is_instance_valid(interaction_executor),
		"world":              is_instance_valid(world),
		"world.factory3d":    is_instance_valid(world) and is_instance_valid(world.factory3d),
		"game_manager":       is_instance_valid(game_manager),
		"player_states":      is_instance_valid(player_states),
		"quest":              is_instance_valid(quest),
		"hud":                is_instance_valid(hud),
		"reward_dispatcher":  is_instance_valid(reward_dispatcher),
	}
