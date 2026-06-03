extends ServiceNode # Geändert zu ServiceNode für den Node-Baum
class_name SaveSystem

const LOG_CAT      := "SaveSystem"
const SAVE_PATH    := "user://savegame.json"
const SAVE_VERSION := 1

var _save_providers: Array = []
var _loaded_state:   Dictionary = {}

# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(_deps: Dictionary) -> void:
	# Wir laden die Datei in den Speicher, bevor die anderen 
	# Services überhaupt nach ihren Daten fragen können.
	if has_save():
		_loaded_state = _read_from_disk()
		Logger.log_info("Spielstand geladen.", LOG_CAT)
	else:
		Logger.log_info("Kein Spielstand vorhanden.", LOG_CAT)

# ─────────────────────────────────────────────
# Provider Management (Das Interface-Pattern)
# ─────────────────────────────────────────────

func register_save_provider(provider: Object) -> void:
	# Wir prüfen zur Laufzeit, ob der Provider das Interface implementiert
	if not provider.has_method("get_save_key") or not provider.has_method("get_save_data"):
		Logger.log_error("Provider %s fehlt Save-Interface!" % provider.get_class(), LOG_CAT)
		return
	
	if not provider in _save_providers:
		_save_providers.append(provider)
		Logger.log_debug("Provider registriert: %s" % provider.get_save_key(), LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func get_state_for(key: String) -> Dictionary:
	# Rückgabe des spezifischen Datensatzes für einen Service
	var sub: Variant = _loaded_state.get(key)
	return sub if sub is Dictionary else {}

func save_game() -> bool:
	Logger.log_info("Speichervorgang gestartet...", LOG_CAT)
	EventBus.system.emit_save_started()
	
	var full_state: Dictionary = {
		"version":   SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	
	# Alle Provider werden abgefragt
	for provider in _save_providers:
		if is_instance_valid(provider):
			full_state[provider.get_save_key()] = provider.get_save_data()

	var success := _write_to_disk(full_state)
	EventBus.system.emit_save_completed(success)
	return success

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _write_to_disk(state: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file: 
		Logger.log_error("Konnte Datei nicht schreiben!", LOG_CAT)
		return false
	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	return true

func _read_from_disk() -> Dictionary:
	if not has_save(): return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return {}
	
	var json_text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		Logger.log_error("JSON Parse-Fehler!", LOG_CAT)
		return {}
		
	return json.data if json.data is Dictionary else {}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)