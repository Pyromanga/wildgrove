extends ServiceNode
class_name WorldService

## WorldService — Zentrale Anlaufstelle für Welt-Daten, Generierung und Zeit.
##
## Abhängigkeiten (deps): ["savesystem", "data"]
##
## WICHTIG: Nutzt on_tick() statt _process() — konform mit dem ServiceTicker-Vertrag.
## Welt-Initialisierung: World.gd ruft on_world_scene_ready() aus seinem _ready() auf.
## Das garantiert, dass der SceneTree-Wechsel vollständig abgeschlossen ist
## bevor wir Kinder in die Szene einfügen.

const LOG_CAT := "World"
const SAVE_KEY := "world_state"

var _save_system: SaveSystem

var data: WorldData
var factory: WorldFactory

var day_time: float = 6.0
var day_count: int = 1
@export var time_speed: float = 0.05


# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(deps: Dictionary) -> void:
	_save_system = deps.get("savesystem") as SaveSystem

	data = WorldData.new()
	factory = WorldFactory.new()

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Dictionary = _save_system.get_state_for(SAVE_KEY)
		if not saved.is_empty():
			_restore_world(saved)
	else:
		Logger.log_error("SaveSystem fehlt in den Dependencies!", LOG_CAT)

	Logger.log_info(
		"WorldService konfiguriert (Tag %d, %02d:00)." % [day_count, int(day_time)], LOG_CAT
	)


# ─────────────────────────────────────────────
# Phase 5: on_ready
# ─────────────────────────────────────────────
func on_ready() -> void:
	# Ticker registrieren damit on_tick() aufgerufen wird
	if Services.ticker:
		Services.ticker.register_service(self)
	Logger.log_info("WorldService bereit.", LOG_CAT)


# ─────────────────────────────────────────────
# Tick (via ServiceTicker — kein direktes _process())
# ─────────────────────────────────────────────
func on_tick(delta: float) -> void:
	if is_instance_valid(Services.game_manager) and Services.game_manager.is_playing():
		_update_time(delta)


# ─────────────────────────────────────────────
# Welt-Initialisierung (von World.gd._ready() aufgerufen)
# ─────────────────────────────────────────────


## Wird von World.gd._ready() aufgerufen.
## Zu diesem Zeitpunkt ist die Szene garantiert im SceneTree —
## kein call_deferred / Frame-Warten nötig.
func on_world_scene_ready(world_root: Node3D) -> void:
	Logger.log_info("World-Init gestartet.", LOG_CAT)

	var generated_world: Node3D = factory.create_world()
	# Kinder aus dem temporären Node in die echte Szene verschieben
	for child in generated_world.get_children():
		generated_world.remove_child(child)
		world_root.add_child(child)
	generated_world.queue_free()

	Logger.log_info("Welt prozedural in World.tscn eingefügt.", LOG_CAT)

	# HUD in die World-Szene einbinden.
	# WARUM HIER: HUDManager ist ein ServiceNode (Kind des ServiceOrchestrator).
	# change_scene_to_file() ersetzt die Root-Szene — alle ihre Kinder-Nodes inklusive
	# ServiceOrchestrator ÜBERLEBEN (weil er ein Autoload ist).
	# Das HUD-CanvasLayer-Node wird als Kind von world_root eingehängt.
	if is_instance_valid(Services.hud):
		Services.hud.attach_to_scene(world_root)
	else:
		Logger.log_error("HUDManager nicht verfügbar — HUD wird nicht angezeigt.", LOG_CAT)


# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────


func get_save_key() -> String:
	return SAVE_KEY


func get_save_data() -> Dictionary:
	return {
		"day_time": day_time,
		"day_count": day_count,
		"tree_positions": var_to_str(data.tree_positions),
		"player_pos": var_to_str(data.player_position),
		"harvested": var_to_str(data.harvested_objects),
	}


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func get_formatted_time() -> String:
	var hours: int = int(day_time)
	var minutes: int = int((day_time - hours) * 60)
	return "%02d:%02d" % [hours, minutes]


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _update_time(delta: float) -> void:
	day_time += delta * time_speed
	if day_time >= 24.0:
		day_time = fmod(day_time, 24.0)
		day_count += 1
		EventBus.world.emit_time_of_day_changed(0)
		Logger.log_info("Ein neuer Tag bricht an: Tag %d" % day_count, LOG_CAT)


func _restore_world(state: Dictionary) -> void:
	day_time = state.get("day_time", 6.0)
	day_count = state.get("day_count", 1)
	data.tree_positions = str_to_var(state.get("tree_positions", "[]"))
	data.player_position = str_to_var(state.get("player_pos", "Vector3(0,0,0)"))
	data.harvested_objects = str_to_var(state.get("harvested", "{}"))
	Logger.log_debug("Welt-Zustand aus Save wiederhergestellt.", LOG_CAT)
