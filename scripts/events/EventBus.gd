# res://scripts/events/EventBus.gd
extends Node

## EventBus — Globale Signal-Infrastruktur.
##
## AutoLoad #2 (nach Logger, vor allen Services).
## Existiert für die gesamte Laufzeit des Spiels, unabhängig vom Service-Lifecycle.
##
## Verwendung:
##   EventBus.player.health_changed.emit(new_health)
##   EventBus.world.day_started.connect(_on_day_started)
##   EventBus.system.services_initialized.connect(_on_ready)
##
## Neuen Namespace hinzufügen:
##   1. NeuesEvents.gd in res://scripts/events/ anlegen (extends BaseEvents)
##   2. Hier eine @onready-Zeile eintragen — fertig.

# ─────────────────────────────────────────────
# Namespaces
# ─────────────────────────────────────────────

## Alle player-bezogenen Signale (Health, XP, Level, Input …)
var player: PlayerEvents

## Alle world-bezogenen Signale (Tag/Nacht, Wetter, Chunk-Load …)
var world: WorldEvents

## System-Signale (Boot, Teardown, Szenen-Wechsel …)
var system: SystemEvents

## UI-Signale (Menü öffnen/schließen, HUD-Updates …)
var ui: UIEvents

#Quests
var quest: QuestEvents

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	player = PlayerEvents.new()
	world  = WorldEvents.new()
	system = SystemEvents.new()
	ui     = UIEvents.new()
	quest = QuestEvents.new()
	Logger.log_info("EventBus bereit. Namespaces: player, world, system, ui", "EventBus")

# ─────────────────────────────────────────────
# Debug-Hilfe
# ─────────────────────────────────────────────

## Gibt alle verfügbaren Namespace-Namen zurück.
## Nützlich für den SimpleTerminal / Laufzeit-Inspektion.
func get_namespaces() -> Array[String]:
	return ["player", "world", "system", "ui"]