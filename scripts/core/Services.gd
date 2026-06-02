# res://scripts/core/Services.gd
extends Node

## Services — Typisierter DependencyContainer.
##
## AutoLoad #5 (nach Logger, EventBus, SceneManager, GameSettings).
## Wird leer gestartet und von ServiceInstaller in Phase 6 befüllt.
##
## Gameplay-Code greift NUR über diesen Container auf Services zu:
##   Services.inventory.add_item(...)
##   Services.world.get_chunk(pos)
##
## NICHT für Bootstrap-Code — der nutzt direkt die ServiceRegistry
## über den Orchestrator.
##
## Neuen Service hinzufügen:
##   1. Property hier eintragen (typisiert, Standardwert null)
##   2. In populate() die Zeile ergänzen
##   3. In clear() auf null setzen

# ─────────────────────────────────────────────
# Typisierte Service-Shortcuts
# Null bis Phase 6 (install) abgeschlossen ist.
# ─────────────────────────────────────────────

var save_system:    SaveSystem         = null
var data:          DataService         = null
var inventory:     InventorySystem     = null
var skill_system:  SkillSystem         = null
var factory3d:     Factory3D           = null
var builder:       InteractionBuilder  = null
var world:         WorldService        = null
var ui_factory:    UIFactory           = null
var game_manager:  GameManager         = null

## player_states separat — häufig gebraucht, eigener Typ
var player_states: PlayerStateService  = null

# ─────────────────────────────────────────────
# Intern — aufgerufen von ServiceInstaller
# ─────────────────────────────────────────────

## Befüllt alle Shortcuts aus der Registry.
## Fehlende Services erzeugen nur einen Warn-Log, kein Crash.
func populate(registry: ServiceRegistry) -> void:
	save_system   = _get(registry, "savesystem")
	data          = _get(registry, "data")
	inventory     = _get(registry, "inventory")
	skill_system  = _get(registry, "skill_system")
	factory3d     = _get(registry, "factory3d")
	builder       = _get(registry, "builder")
	world         = _get(registry, "world")
	ui_factory    = _get(registry, "ui_factory")
	game_manager  = _get(registry, "gamemanager")
	player_states = _get(registry, "playerstates")

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

func _get(registry: ServiceRegistry, key: String) -> Object:
	var svc := registry.get_service(key)
	if svc == null:
		Logger.log_warn("Services.populate: '%s' nicht in Registry." % key, "Services")
	return svc