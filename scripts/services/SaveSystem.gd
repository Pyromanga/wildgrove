# res://scripts/services/SaveSystem.gd
class_name SaveSystem extends Service

const SAVE_PATH    := "user://savegame.json"
const SAVE_VERSION := 1

# Hier speichern wir alle Objekte, die uns beim Speichern Daten liefern
var _save_providers: Array = []

func init() -> void:
	super.init()
	Logger.log_info("SaveSystem initialisiert.", _log_cat())

## Registriert einen Service, der Daten beisteuern will
func register_save_provider(provider: Object) -> void:
	if not provider.has_method("get_save_data") or not provider.has_method("get_save_key"):
		Logger.log_error("Provider implementiert Interface nicht!", _log_cat())
		return
	_save_providers.append(provider)

## Führt den Speichervorgang aus (automatisch über alle Provider)
func save_game() -> bool:
	var full_state := { "version": SAVE_VERSION }
	
	for provider in _save_providers:
		var key = provider.get_save_key()
		var data = provider.get_save_data()
		full_state[key] = data
		
	return _write_to_disk(full_state)

## Lädt den State und gibt ihn zurück (Services müssen sich selbst beim Init aktualisieren)
func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	
	if parsed is Dictionary:
		return _migrate_if_needed(parsed)
	return {}

# --- Interne Hilfen ---

func _write_to_disk(state: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file: return false
	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	return true

func _migrate_if_needed(state: Dictionary) -> Dictionary:
	# Hier später Migrationslogik einbauen
	return state