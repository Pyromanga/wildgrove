extends Service
class_name GameEvents

## GameEvents — Container für alle Event-Namespaces.
## Erbt von Service (RefCounted) — kein Node nötig, keine Szenen-Präsenz.
## Erbt NICHT von BaseEvents — es ist kein Namespace, sondern ein Orchestrator.
##
## Neuen Namespace hinzufügen:
##   1. NeuesEvents.gd in res://scripts/events/ anlegen (extends BaseEvents)
##   2. Hier eine Property + Zeile in init() eintragen — das war's.

const LOG_CAT := "Events"

var player: PlayerEvents
var world:  WorldEvents
var system: SystemEvents
var ui:     UIEvents

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	super.init()
	# Namespaces hier erstellen — init() ist Phase 2, alle Autoloads längst bereit
	player = PlayerEvents.new()
	world  = WorldEvents.new()
	system = SystemEvents.new()
	ui     = UIEvents.new()
	Logger.log_debug("Namespaces bereit: player, world, system, ui", LOG_CAT)

func on_ready() -> void:
	super.on_ready()
	# Signal für Main._on_services_ready() — feuert als letzter Service in Phase 3
	system.emit_services_initialized()
	Logger.log_info("EventSystem aktiv.", LOG_CAT)