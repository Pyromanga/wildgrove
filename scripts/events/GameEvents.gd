extends ServiceNode
class_name GameEvents

## GameEvents — Dünner Orchestrator, registriert alle Event-Namespaces.
## Neuen Namespace hinzufügen:
##   1. NeuesEvents.gd in res://scripts/events/ anlegen
##   2. Hier eine Zeile eintragen — das war's.

const LOG_CAT := "Events"

var player: PlayerEvents
var world:  WorldEvents
var system: SystemEvents
var ui:     UIEvents

func _ready() -> void:
	player = PlayerEvents.new()
	world  = WorldEvents.new()
	system = SystemEvents.new()
	ui     = UIEvents.new()
	Logger.log_debug("Namespaces bereit: player, world, system, ui", LOG_CAT)
	super._ready()

func init() -> void:
	super.init()

func on_ready() -> void:
	super.on_ready()
	system.emit_services_initialized()
	Logger.log_debug("EventSystem aktiv.", LOG_CAT)