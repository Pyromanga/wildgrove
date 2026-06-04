# res://scripts/ui/HUDManager.gd
extends ServiceNode
class_name HUDManager

## HUDManager — Zentrale Steuerung des in-game HUD.
##
## Als ServiceNode lebt er für die gesamte Laufzeit in der Service-Pipeline.
## Das HUD-CanvasLayer-Node selbst wird via attach_to_scene() in die jeweilige
## Spielwelt-Szene eingehängt, damit es change_scene_to_file()-Wechsel überlebt.
##
## Lifecycle:
##   configure()       → DI: erhält InventorySystem + PlayerStateService
##   on_ready()        → Wartet auf attach_to_scene()-Aufruf
##   attach_to_scene() → Von WorldService.on_world_scene_ready() aufgerufen
##   on_cleanup()      → Gibt HUD frei

const LOG_CAT := "HUD"

var hud: HUD = null
var controllers: Dictionary = {}

## Abhängigkeiten via DI
var _inventory: InventorySystem
var _player_states: PlayerStateService


# ─────────────────────────────────────────────
# Phase 4: Configure (Enterprise DI)
# ─────────────────────────────────────────────
func configure(deps: Dictionary) -> void:
	_inventory = deps.get("inventory") as InventorySystem
	_player_states = deps.get("playerstates") as PlayerStateService

	if not is_instance_valid(_inventory):
		Logger.log_warn("Abhängigkeit 'inventory' fehlt in HUDManager.configure()!", LOG_CAT)
	if not is_instance_valid(_player_states):
		Logger.log_warn("Abhängigkeit 'playerstates' fehlt in HUDManager.configure()!", LOG_CAT)

	# HUD-Node im Speicher vorbereiten, aber NOCH NICHT in den Tree einhängen.
	# Das passiert erst in attach_to_scene(), wenn die Ziel-Szene bereit ist.
	if hud == null:
		hud = HUD.new()
		hud.name = "GameHUD"
		Logger.log_debug("HUD-Node im Speicher erstellt (noch nicht im Tree).", LOG_CAT)
	else:
		Logger.log_warn("configure() erneut aufgerufen — HUD-Node bereits vorhanden.", LOG_CAT)


# ─────────────────────────────────────────────
# Phase 5: on_ready
# ─────────────────────────────────────────────
func on_ready() -> void:
	# HUDManager selbst ist ein Autoload-Service (ServiceOrchestrator hängt ihn ein).
	# Das HUD wird NICHT hier eingefügt — es wartet auf attach_to_scene().
	Logger.log_info("HUDManager bereit. HUD-Node wartet auf attach_to_scene()-Aufruf.", LOG_CAT)


# ─────────────────────────────────────────────
# Phase 7: Cleanup
# ─────────────────────────────────────────────
func on_cleanup() -> void:
	if is_instance_valid(hud) and hud.is_inside_tree():
		hud.queue_free()
	hud = null
	controllers.clear()
	Logger.log_debug("HUDManager bereinigt.", LOG_CAT)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


## Hängt das HUD-Node als CanvasLayer in die übergebene Szene ein und initialisiert
## alle Controller. Wird von WorldService.on_world_scene_ready() aufgerufen,
## nachdem World.tscn vollständig im SceneTree ist.
func attach_to_scene(scene_root: Node) -> void:
	if not is_instance_valid(hud):
		Logger.log_error("attach_to_scene() fehlgeschlagen: HUD-Node ist null!", LOG_CAT)
		return

	if hud.is_inside_tree():
		var parent_name: String = hud.get_parent().name
		Logger.log_warn(
			"attach_to_scene() aufgerufen, HUD bereits im Tree (%s). Übersprungen." % parent_name,
			LOG_CAT
		)
		return

	scene_root.add_child(hud)
	Logger.log_debug("HUD-Node in Szene '%s' eingehängt." % scene_root.name, LOG_CAT)

	_setup_controllers()
	Logger.log_info("HUD-System aktiv. %d Controller initialisiert." % controllers.size(), LOG_CAT)


## Gibt einen registrierten Controller zurück (oder null wenn nicht vorhanden).
func get_controller(key: String) -> Object:
	return controllers.get(key)


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _setup_controllers() -> void:
	var context := {"inventory": _inventory, "player_states": _player_states}
	Logger.log_debug("Baue HUD-Controller mit Kontext...", LOG_CAT)
	controllers = HUDBuilder.build_all(hud, context)
	Logger.log_debug("HUD-Controller gebaut: %d Einheiten." % controllers.size(), LOG_CAT)


## Falls das HUD auf Ticks reagieren muss (z.B. für Animationen oder Timer).
func on_tick(_delta: float) -> void:
	pass
