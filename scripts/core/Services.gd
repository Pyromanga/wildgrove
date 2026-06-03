extends Node

## Services — Typisierter DependencyContainer.
##
## AutoLoad #4 (nach Logger, EventBus, SimpleTerminal).
## Wird leer gestartet und von ServiceOrchestrator in Phase 6 befüllt.
##
## Gameplay-Code greift NUR über diesen Container auf Services zu:
##   Services.inventory.add_item(...)
##   Services.world.get_chunk(pos)

# ─────────────────────────────────────────────
# Typisierte Service-Shortcuts
# ─────────────────────────────────────────────

var save_system:    SaveSystem         = null
var data:           DataService        = null
var inventory:      InventorySystem    = null
var skill_system:   SkillSystem        = null
var factory3d:      Factory3D          = null
var builder:        InteractionBuilder = null
var world:          WorldService       = null
var ui_factory:     UIFactory          = null
var game_manager:   GameManager        = null
var player_states:  PlayerStateService = null

# ─────────────────────────────────────────────
# Intern — aufgerufen von ServiceOrchestrator
# ─────────────────────────────────────────────

## Befüllt alle Shortcuts aus der Registry.
func populate(registry: ServiceRegistry) -> void:
	save_system   = _resolve(registry, "savesystem")
	data          = _resolve(registry, "data")
	inventory     = _resolve(registry, "inventory")
	skill_system  = _resolve(registry, "skill_system")
	factory3d     = _resolve(registry, "factory3d")
	builder       = _resolve(registry, "builder")
	world         = _resolve(registry, "world")
	ui_factory    = _resolve(registry, "ui_factory")
	game_manager  = _resolve(registry, "gamemanager")
	player_states = _resolve(registry, "playerstates")
	Logger.log_info("DependencyContainer befüllt.", "Services")

## Leert alle Shortcuts (aufgerufen beim Teardown).
func clear() -> void:
	save_system   = null
	data          = null
	inventory     = null
	skill_system  = null
	factory3d     = null
	builder       = null
	world         = null
	ui_factory    = null
	game_manager  = null
	player_states = null
	Logger.log_debug("DependencyContainer geleert.", "Services")

# ─────────────────────────────────────────────
# Hilfsfunktion
# ─────────────────────────────────────────────

# FIX: Umbenannt von _get() → _resolve() um den Konflikt mit der
# Node-Built-in-Methode _get(StringName) -> Variant zu vermeiden.
# GDScript erzwingt die Parent-Signatur — eigene Überladung mit
# anderer Parameterliste ist ein Parse Error.
func _resolve(registry: ServiceRegistry, key: String) -> Object:
	var svc: Object = registry.get_service(key)
	if svc == null:
		Logger.log_warn("Services.populate: '%s' nicht in Registry." % key, "Services")
	return svc