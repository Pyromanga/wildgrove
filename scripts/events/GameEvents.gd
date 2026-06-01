extends ServiceBase
class_name GameEvents

## GameEvents.gd
## Dünner Orchestrator — registriert Namespaces, sonst nichts.
## Neuen Namespace hinzufügen:
##   1. NeuesEvents.gd in res://scripts/events/ anlegen
##   2. Hier eine Zeile eintragen
##   Das war's.

const LOG_CAT := "Events"

var player: PlayerEvents
var world:  WorldEvents
var system: SystemEvents
var ui: UIEvents

# var combat: CombatEvents   ← so einfach erweiterbar

func _ready() -> void:
	Logger.log_debug("GameEvents._ready() — initialisiere Namespaces...", LOG_CAT)
	player = PlayerEvents.new()
	world  = WorldEvents.new()
	system = SystemEvents.new()
	ui = UIEvents.new()
	Logger.log_debug("Namespaces bereit: player, world, system, ui", LOG_CAT)
	super._ready()

func init() -> void:
	super.init()
	Logger.log_debug("init() — keine Abhängigkeiten.", LOG_CAT)

func on_ready() -> void:
	super.on_ready()
	Logger.log_debug("on_ready() — EventSystem vollständig aktiv.", LOG_CAT)