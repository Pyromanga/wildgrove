class_name SaveSystem extends Service

## SaveSystem — Pure Service (kein Node nötig).
## Provider-Pattern: Jeder Service registriert sich selbst und liefert seine Daten.

const LOG_CAT      := "SaveSystem"
const SAVE_PATH    := "user://savegame.json"
const SAVE_VERSION := 1

var _save_providers: Array = []
var _loaded_state:   Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	super.init()
	Logger.log_info("SaveSystem bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Provider-Registrierung
# ─────────────────────────────────────────────

## Provider muss get_save_key() → String und get_save_data() → Dictionary haben.
func register_save_provider(provider: Object) -> void:
	if not provider.has_method("get_save_key") or not provider.has_method("get_save_data"):
		Logger.log_error("Provider hat kein gültiges Save-Interface!", LOG_CAT)
		return
	if provider in _save_providers:
		Logger.log_warn("Provider bereits registriert.", LOG_CAT)
		return
	_save_providers.append(provider)
	Logger.log_debug("Save-Provider registriert: %s" % provider.get_class(), LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Gibt den zuletzt geladenen State zurück (oder leeres Dict wenn nie geladen).
## Wird von Services in init() genutzt um ihren Zustand wiederherzustellen.
func get_state() -> Dictionary:
	return _loaded_state

## Gibt den State-Teil eines bestimmten Keys zurück.
func get_state_for(key: String) -> Dictionary:
	return _loaded_state.get(key, {})

func save_game() -> bool:
	Logger.log_info("Speichern...", LOG_CAT)
	var full_state: Dictionary = {"version": SAVE_VERSION}

	for provider in _save_providers:
		if not is_instance_valid(provider):
			Logger.log_warn("Provider ist freigegeben — übersprungen.", LOG_CAT)
			continue
		var key: String  = provider.get_save_key()
		var data: Dictionary = provider.get_save_data()
		full_state[key] = data

	var success := _write_to_disk(full_state)
	if success:
		Logger.log_info("Gespeichert.", LOG_CAT)
	else:
		Logger.log_error("Speichern fehlgeschlagen!", LOG_CAT)
	return success

func load_game() -> Dictionary:
	if not has_save():
		Logger.log_info("Kein Spielstand vorhanden.", LOG_CAT)
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		Logger.log_error("Spielstand konnte nicht geöffnet werden.", LOG_CAT)
		return {}

	var text    := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		Logger.log_error("Spielstand ist kein gültiges JSON!", LOG_CAT)
		return {}

	_loaded_state = _migrate_if_needed(parsed)
	Logger.log_info("Spielstand geladen (v%d)." % _loaded_state.get("version", 0), LOG_CAT)
	return _loaded_state

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

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
		# Hier später Migrationslogik
	return state