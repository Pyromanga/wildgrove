extends ServiceBase
class_name GameEvents

## GameEvents.gd
## Zentrales Event-System. Namespace-Struktur verhindert Signal-Kollisionen.
## Zugriff: Kernel.get_service("events").player.xp_gained.connect(...)

const LOG_CAT := "Events"

var player := PlayerEvents.new()
var world  := WorldEvents.new()
var system := SystemEvents.new()

func _ready() -> void:
	Logger.log_debug("GameEvents._ready() — rufe super._ready() auf...", LOG_CAT)
	super._ready()  # ServiceBase registriert uns beim Kernel
	Logger.log_debug("GameEvents bereit. Namespaces: player, world, system", LOG_CAT)

func init() -> void:
	super.init()
	Logger.log_debug("init() — keine Abhängigkeiten nötig.", LOG_CAT)

func on_ready() -> void:
	super.on_ready()
	Logger.log_debug("on_ready() — EventSystem vollständig aktiv.", LOG_CAT)

# ─────────────────────────────────────────────

class PlayerEvents extends RefCounted:
	const LOG_CAT := "Events/Player"

	signal xp_gained(skill: String, amount: int)
	signal level_up(skill: String, new_level: int)
	signal movement_interrupted()
	signal player_died()
	signal player_respawned()

	func emit_xp(skill: String, amount: int) -> void:
		Logger.log_debug("XP: +%d in '%s'" % [amount, skill], LOG_CAT)
		xp_gained.emit(skill, amount)

	func emit_level_up(skill: String, new_level: int) -> void:
		Logger.log_info("Level Up: '%s' → Level %d" % [skill, new_level], LOG_CAT)
		level_up.emit(skill, new_level)

	func emit_movement_interrupted() -> void:
		Logger.log_debug("Bewegung während Aktion unterbrochen.", LOG_CAT)
		movement_interrupted.emit()

	func emit_player_died() -> void:
		Logger.log_warn("Spieler gestorben.", LOG_CAT)
		player_died.emit()

	func emit_player_respawned() -> void:
		Logger.log_info("Spieler respawned.", LOG_CAT)
		player_respawned.emit()

# ─────────────────────────────────────────────

class WorldEvents extends RefCounted:
	const LOG_CAT := "Events/World"

	signal interaction_started(label: String, duration: float)
	signal interaction_finished(label: String)
	signal interaction_cancelled(label: String)
	signal chunk_loaded(chunk_id: Vector2i)
	signal chunk_unloaded(chunk_id: Vector2i)
	signal time_of_day_changed(hour: int)

	func emit_interaction_started(label: String, duration: float) -> void:
		Logger.log_debug("Interaktion gestartet: '%s' (%.1fs)" % [label, duration], LOG_CAT)
		interaction_started.emit(label, duration)

	func emit_interaction_finished(label: String) -> void:
		Logger.log_debug("Interaktion beendet: '%s'" % label, LOG_CAT)
		interaction_finished.emit(label)

	func emit_interaction_cancelled(label: String) -> void:
		Logger.log_debug("Interaktion abgebrochen: '%s'" % label, LOG_CAT)
		interaction_cancelled.emit(label)

	func emit_chunk_loaded(chunk_id: Vector2i) -> void:
		Logger.log_debug("Chunk geladen: %s" % str(chunk_id), LOG_CAT)
		chunk_loaded.emit(chunk_id)

	func emit_chunk_unloaded(chunk_id: Vector2i) -> void:
		Logger.log_debug("Chunk entladen: %s" % str(chunk_id), LOG_CAT)
		chunk_unloaded.emit(chunk_id)

	func emit_time_of_day_changed(hour: int) -> void:
		Logger.log_debug("Tageszeit: %02d:00" % hour, LOG_CAT)
		time_of_day_changed.emit(hour)

# ─────────────────────────────────────────────

class SystemEvents extends RefCounted:
	const LOG_CAT := "Events/System"

	# Enum hier referenzieren geht nicht direkt in einer Inner Class —
	# SystemEvents.emit_state_changed nimmt int entgegen, GameManager
	# übergibt GameManager.GameState. Typsicherheit via GameManager-Aufruf.
	signal state_changed(state: int)
	signal setting_changed(key: String, value: Variant)
	signal save_started()
	signal save_completed(success: bool)
	signal load_started()
	signal load_completed(success: bool)

	func emit_state_changed(state: int) -> void:
		Logger.log_info("GameState geändert → %d" % state, LOG_CAT)
		state_changed.emit(state)

	func emit_setting_changed(key: String, value: Variant) -> void:
		Logger.log_debug("Setting geändert: '%s' = %s" % [key, str(value)], LOG_CAT)
		setting_changed.emit(key, value)

	func emit_save_started() -> void:
		Logger.log_info("Speichervorgang gestartet...", LOG_CAT)
		save_started.emit()

	func emit_save_completed(success: bool) -> void:
		if success:
			Logger.log_info("Speichervorgang erfolgreich abgeschlossen.", LOG_CAT)
		else:
			Logger.log_error("Speichervorgang fehlgeschlagen!", LOG_CAT)
		save_completed.emit(success)

	func emit_load_started() -> void:
		Logger.log_info("Ladevorgang gestartet...", LOG_CAT)
		load_started.emit()

	func emit_load_completed(success: bool) -> void:
		if success:
			Logger.log_info("Ladevorgang erfolgreich abgeschlossen.", LOG_CAT)
		else:
			Logger.log_error("Ladevorgang fehlgeschlagen!", LOG_CAT)
		load_completed.emit(success)