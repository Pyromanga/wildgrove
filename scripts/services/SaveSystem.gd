extends Service
class_name SaveSystem

## SaveSystem — Pure Service.
## Verarbeitet das Speichern und Laden von JSON-Daten über das Provider-Pattern.

const LOG_CAT      := "SaveSystem"
const SAVE_PATH    := "user://savegame.json"
const SAVE_VERSION := 1

var _save_providers: Array  = []
var _loaded_state:   Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	if has_save():
		_loaded_state = _read_from_disk()
		Logger.log_info("Initialer Spielstand in Speicher geladen.", LOG_CAT)
	Logger.log_info("SaveSystem bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Provider-Logik
# ─────────────────────────────────────────────

func register_save_provider(provider: Object) -> void:
	if not provider.has_method("get_save_key") or not provider.has_method("get_save_data"):
		Logger.log_error("Provider %s erfüllt Save-Interface nicht!" % provider.get_class(), LOG_CAT)
		return
	if not provider in _save_providers:
		_save_providers.append(provider)
		Logger.log_debug("Provider registriert: %s" % provider.get_class(), LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## FIX: Diese Methode fehlte komplett — wird von WorldService, SkillSystem,
## InventorySystem in ihrer init() aufgerufen.
## Gibt den gespeicherten Sub-State für einen bestimmten Schlüssel zurück,
## oder ein leeres Dictionary wenn kein Save existiert oder der Key fehlt.
func get_state_for(key: String) -> Dictionary:
	var sub: Variant = _loaded_state.get(key)
	if sub is Dictionary:
		return sub
	return {}

func save_game() -> bool:
	EventBus.system.emit_save_started()

	var full_state: Dictionary = {
		"version":   SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	for provider in _save_providers:
		if is_instance_valid(provider):
			full_state[provider.get_save_key()] = provider.get_save_data()

	var success := _write_to_disk(full_state)
	EventBus.system.emit_save_completed(success)
	return success

func load_game() -> Dictionary:
	EventBus.system.emit_load_started()

	var data: Dictionary = _read_from_disk()
	if data.is_empty():
		EventBus.system.emit_load_completed(false)
		return {}

	_loaded_state = _migrate_if_needed(data)
	EventBus.system.emit_load_completed(true)
	return _loaded_state

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _read_from_disk() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _write_to_disk(state: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	return true

func _migrate_if_needed(state: Dictionary) -> Dictionary:
	var version: int = state.get("version", 0)
	if version < SAVE_VERSION:
		Logger.log_warn("Spielstand v%d → migriere zu v%d." % [version, SAVE_VERSION], LOG_CAT)
	return state