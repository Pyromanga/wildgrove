extends Node

## Services — Typisierter DependencyContainer.
##
## AutoLoad #4 (nach Logger, EventBus, SimpleTerminal).
## Wird leer gestartet und von ServiceOrchestrator in Phase 6 befüllt.
##
## HINWEIS: Variablen sind absichtlich untypisiert (= null ohne Typannotation).
## Services.gd ist ein Autoload und wird vor allen Service-Skripten geparst —
## Typannotationen wie "var x: GameManager" erzeugen Forward-Reference-Fehler.
## Die Casts in populate() geben trotzdem Typsicherheit zur Laufzeit.

# ─────────────────────────────────────────────
# Service-Shortcuts (untypisiert — siehe Hinweis oben)
# ─────────────────────────────────────────────
var ticker         = null
var scene          = null
var save_system    = null
var game_save      = null
var data           = null
var inventory      = null
var skill_system   = null
var factory3d      = null
var builder        = null
var world          = null
var ui_factory     = null
var game_manager   = null
var player_states  = null
var quest          = null
var hud            = null


# ─────────────────────────────────────────────
# Intern — aufgerufen von ServiceOrchestrator
# ─────────────────────────────────────────────

func populate(registry: ServiceRegistry) -> void:
	ticker        = registry.get_service("ticker")
	scene         = registry.get_service("scenemanager")
	save_system   = registry.get_service("savesystem")
	game_save     = registry.get_service("gamesave")
	data          = registry.get_service("data")
	inventory     = registry.get_service("inventory")
	skill_system  = registry.get_service("skill_system")
	factory3d     = registry.get_service("factory3d")
	builder       = registry.get_service("builder")
	world         = registry.get_service("world")
	ui_factory    = registry.get_service("ui_factory")
	game_manager  = registry.get_service("gamemanager")
	player_states = registry.get_service("playerstates")
	quest         = registry.get_service("quest")
	hud           = registry.get_service("hud")
	Logger.log_info("DependencyContainer befüllt.", "Services")


func clear() -> void:
	ticker = null; scene = null; save_system = null; game_save = null
	data = null; inventory = null; skill_system = null; factory3d = null
	builder = null; world = null; ui_factory = null; game_manager = null
	player_states = null; quest = null; hud = null
	Logger.log_debug("DependencyContainer geleert.", "Services")
