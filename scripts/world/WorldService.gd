extends ServiceNode
class_name WorldService

## WorldService — Zentrale Anlaufstelle für Welt-Daten, Generierung und Zeit.
## Abhängigkeiten (deps): ["savesystem", "data"]

const LOG_CAT := "World"
const SAVE_KEY := "world_state"

var data:    WorldData
var factory: WorldFactory

var day_time:  float = 6.0
var day_count: int   = 1
@export var time_speed: float = 0.05

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	data    = WorldData.new()
	factory = WorldFactory.new()

	Services.save_system.register_save_provider(self)

	# FIX: War `var saved := ...` — get_state_for() gibt Dictionary zurück,
	# aber := kann den Typ aus einem ungetypten Rückgabewert nicht ableiten.
	var saved: Dictionary = Services.save_system.get_state_for(SAVE_KEY)
	if not saved.is_empty():
		_restore_world(saved)

	Logger.log_info("WorldService initialisiert (Tag %d, %02d:00)." % [day_count, int(day_time)], LOG_CAT)

func on_ready() -> void:
	Logger.log_info("WorldService bereit.", LOG_CAT)

func _process(delta: float) -> void:
	if is_instance_valid(Services.game_manager) and Services.game_manager.is_playing():
		_update_time(delta)

# ─────────────────────────────────────────────
# Save-Interface
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
# Öffentliche API
# ─────────────────────────────────────────────

func create_world() -> Node3D:
	Logger.log_info("Starte Welt-Generierung...", LOG_CAT)
	var world_root: Node3D = factory.create_world()
	Logger.log_info("Welt erfolgreich erstellt.", LOG_CAT)
	return world_root

func get_formatted_time() -> String:
	var hours:   int = int(day_time)
	var minutes: int = int((day_time - hours) * 60)
	return "%02d:%02d" % [hours, minutes]

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _update_time(delta: float) -> void:
	day_time += delta * time_speed
	if day_time >= 24.0:
		day_time   = fmod(day_time, 24.0)
		day_count += 1
		# FIX: day_passed existiert nicht in SystemEvents — nutze time_of_day_changed
		# auf WorldEvents oder füge day_passed zu SystemEvents hinzu.
		# Hier: WorldEvents.time_of_day_changed als nächste passende Alternative.
		EventBus.world.emit_time_of_day_changed(0)  # Mitternacht = Tageswechsel
		Logger.log_info("Ein neuer Tag bricht an: Tag %d" % day_count, LOG_CAT)

func _restore_world(state: Dictionary) -> void:
	day_time  = state.get("day_time",  6.0)
	day_count = state.get("day_count", 1)

	var tree_data: String = state.get("tree_positions", "[]")
	data.tree_positions   = str_to_var(tree_data)

	var pos_data: String  = state.get("player_pos", "Vector3(0,0,0)")
	data.player_position  = str_to_var(pos_data)

	Logger.log_debug("Welt-Zustand aus Save wiederhergestellt.", LOG_CAT)