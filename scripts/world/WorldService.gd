extends ServiceNode
class_name WorldService

## WorldService — Zentrale Anlaufstelle für Welt-Daten, Generierung und Zeit.
## Abhängigkeiten (deps): ["savesystem", "factory3d"]

const LOG_CAT := "World"
const SAVE_KEY := "world_state"

# --- Komponenten ---
var data: WorldData
var factory: WorldFactory

# --- Zeit-System ---
var day_time: float = 6.0  # Start um 6 Uhr morgens
var day_count: int = 1
@export var time_speed: float = 0.05 # Justierbar im Inspector

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	# 1. Daten-Container und Factory erstellen
	data = WorldData.new()
	factory = WorldFactory.new()
	
	# 2. Beim SaveSystem registrieren
	Services.save_system.register_save_provider(self)
	
	# 3. Daten-Restore aus dem RAM-Cache des SaveSystems
	var saved := Services.save_system.get_state_for(SAVE_KEY)
	if not saved.is_empty():
		_restore_world(saved)
	
	Logger.log_info("WorldService initialisiert (Tag %d, %02d:00)." % [day_count, int(day_time)], LOG_CAT)

func on_ready() -> void:
	# Hier könnte der GameManager später create_world() triggern
	Logger.log_info("WorldService bereit.", LOG_CAT)

func _process(delta: float) -> void:
	# Zeit läuft nur, wenn wir wirklich im Spiel sind
	if Services.game_manager.is_playing():
		_update_time(delta)

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	# Wir speichern Zeit, Tag und die Positionen
	return {
		"day_time": day_time,
		"day_count": day_count,
		"tree_positions": var_to_str(data.tree_positions),
		"player_pos": var_to_str(data.player_position)
	}

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Erstellt die komplette Welt-Instanz
func create_world() -> Node3D:
	Logger.log_info("Starte Welt-Generierung...", LOG_CAT)
	
	# Die Factory baut die Nodes zusammen
	var world_root = factory.create_world()
	
	# Falls die Baumpositionen aus dem Save kamen, könnten wir sie hier 
	# an die Factory übergeben (falls diese das unterstützt)
	
	Logger.log_info("Welt erfolgreich erstellt.", LOG_CAT)
	return world_root

func get_formatted_time() -> String:
	var hours := int(day_time)
	var minutes := int((day_time - hours) * 60)
	return "%02d:%02d" % [hours, minutes]

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _update_time(delta: float) -> void:
	day_time += delta * time_speed
	
	if day_time >= 24.0:
		day_time = 0.0
		day_count += 1
		EventBus.system.day_passed.emit(day_count)
		Logger.log_info("Ein neuer Tag bricht an: Tag %d" % day_count, LOG_CAT)

func _restore_world(state: Dictionary) -> void:
	day_time = state.get("day_time", 6.0)
	day_count = state.get("day_count", 1)
	
	# Komplexe Typen via var_to_str / str_to_var
	var tree_data = state.get("tree_positions", "[]")
	data.tree_positions = str_to_var(tree_data)
	
	var pos_data = state.get("player_pos", "Vector3(0,0,0)")
	data.player_position = str_to_var(pos_data)
	
	Logger.log_debug("Welt-Zustand aus Save wiederhergestellt.", LOG_CAT)