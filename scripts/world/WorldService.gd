extends ServiceNode
class_name WorldService

## WorldService — Zentrale Anlaufstelle für Welt-Daten, Generierung und Zeit.
## Abhängigkeiten (deps): ["savesystem", "data"]

const LOG_CAT := "World"
const SAVE_KEY := "world_state"

# Diese Variablen werden jetzt via configure() befüllt
var _save_system: SaveSystem

var data:    WorldData
var factory: WorldFactory

var day_time:  float = 6.0
var day_count: int   = 1
@export var time_speed: float = 0.05

# ─────────────────────────────────────────────
# Lifecycle (Enterprise DI)
# ─────────────────────────────────────────────

## Schritt 1: Konfiguration & Injection
func configure(deps: Dictionary) -> void:
	# Wir holen uns das SaveSystem direkt aus dem Paket
	_save_system = deps.get("savesystem") as SaveSystem
	
	# Interne Objekte erstellen
	data    = WorldData.new()
	factory = WorldFactory.new()

	if _save_system:
		# Wir registrieren uns beim SaveSystem
		_save_system.register_save_provider(self)
		
		# Wir laden den Zustand direkt hier
		var saved: Dictionary = _save_system.get_state_for(SAVE_KEY)
		if not saved.is_empty():
			_restore_world(saved)
	else:
		Logger.log_error("SaveSystem fehlt in den Dependencies!", LOG_CAT)

	Logger.log_info("WorldService konfiguriert (Tag %d, %02d:00)." % [day_count, int(day_time)], LOG_CAT)

## Schritt 2: Aktivierung
func on_ready() -> void:
	Logger.log_info("WorldService bereit.", LOG_CAT)

func _process(delta: float) -> void:
	# WICHTIG: Im Prozess nutzen wir Services.game_manager, 
	# da der Bootvorgang hier längst abgeschlossen ist.
	if is_instance_valid(Services.game_manager) and Services.game_manager.is_playing():
		_update_time(delta)

# ─────────────────────────────────────────────
# Save-Interface (Unverändert)
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return {
		"day_time":       day_time,
		"day_count":      day_count,
		"tree_positions": var_to_str(data.tree_positions),
		"player_pos":     var_to_str(data.player_position),
	}

# ─────────────────────────────────────────────
# Öffentliche API & Intern (Unverändert)
# ─────────────────────────────────────────────

func create_world() -> Node3D:
	return factory.create_world()

func get_formatted_time() -> String:
	var hours:   int = int(day_time)
	var minutes: int = int((day_time - hours) * 60)
	return "%02d:%02d" % [hours, minutes]

func _update_time(delta: float) -> void:
	day_time += delta * time_speed
	if day_time >= 24.0:
		day_time   = fmod(day_time, 24.0)
		day_count += 1
		EventBus.world.emit_time_of_day_changed(0) 
		Logger.log_info("Ein neuer Tag bricht an: Tag %d" % day_count, LOG_CAT)

func _restore_world(state: Dictionary) -> void:
	day_time  = state.get("day_time",  6.0)
	day_count = state.get("day_count", 1)
	data.tree_positions   = str_to_var(state.get("tree_positions", "[]"))
	data.player_position  = str_to_var(state.get("player_pos", "Vector3(0,0,0)"))
	Logger.log_debug("Welt-Zustand aus Save wiederhergestellt.", LOG_CAT)