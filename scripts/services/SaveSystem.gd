extends Service
class_name SaveSystem

## SaveSystem — Pure Service.
## Verarbeitet das Speichern und Laden von JSON-Daten über das Provider-Pattern.

const LOG_CAT      := "SaveSystem"
const SAVE_PATH    := "user://savegame.json"
const SAVE_VERSION := 1

var _save_providers: Array = []
var _loaded_state:   Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	# Hier rufen wir nicht Kernel auf, sondern bereiten nur die Daten vor.
	# Falls wir beim Booten sofort den letzten Spielstand im Speicher haben wollen:
	if has_save():
		_loaded_state = _read_from_disk()
		Logger.log_info("Initialer Spielstand in Speicher geladen.", LOG_CAT)
	
	Logger.log_info("SaveSystem bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Provider-Logik (unverändert, da sie schon sauber ist)
# ─────────────────────────────────────────────

func register_save_provider(provider: Object) -> void:
	# Duck-Typing Check bleibt, da Provider Nodes oder RefCounted sein können
	if not provider.has_method("get_save_key") or not provider.has_method("get_save_data"):
		Logger.log_error("Provider %s erfüllt Save-Interface nicht!" % provider.get_class(), LOG_CAT)
		return
	
	if not provider in _save_providers:
		_save_providers.append(provider)
		Logger.log_debug("Provider registriert: %s" % provider.get_class(), LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func save_game() -> bool:
	# EventBus nutzen, um den Start zu signalisieren (für UI-Overlay etc.)
	EventBus.system.emit_save_started()
	
	var full_state: Dictionary = {"version": SAVE_VERSION, "timestamp": Time.get_datetime_string_from_system()}

	for provider in _save_providers:
		if is_instance_valid(provider):
			full_state[provider.get_save_key()] = provider.get_save_data()

	var success := _write_to_disk(full_state)
	
	# EventBus informiert alle über das Ergebnis
	EventBus.system.emit_save_completed(success)
	return success

func load_game() -> Dictionary:
	EventBus.system.emit_load_started()
	
	var data := _read_from_disk()
	if data.is_empty():
		EventBus.system.emit_load_completed(false)
		return {}

	_loaded_state = _migrate_if_needed(data)
	EventBus.system.emit_load_completed(true)
	return _loaded_state

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _read_from_disk() -> Dictionary:
	if not has_save(): return {}
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return {}
	
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	
	return parsed if parsed is Dictionary else {}

func _write_to_disk(state: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file: return false
	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	return true
    
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func _migrate_if_needed(state: Dictionary) -> Dictionary:
	var version: int = state.get("version", 0)
	if version < SAVE_VERSION:
		Logger.log_warn("Spielstand v%d → migriere zu v%d." % [version, SAVE_VERSION], LOG_CAT)
		# Hier später Migrationslogik
	return state