# res://scripts/services/SaveSystem.gd
class_name SaveSystem extends Service

const SAVE_PATH    := "user://savegame.json"
const SAVE_VERSION := 1

var _cached_state: Dictionary = {}

func init() -> void:
    super.init()
    _load_from_disk()
    Logger.log_info("SaveSystem initialisiert.", _log_cat())

# --- Öffentliche API ---

func get_state() -> Dictionary:
    return _cached_state.duplicate(true)

func save_state(state: Dictionary) -> bool:
    if state.is_empty(): 
        Logger.log_warn("Versuch, leeren State zu speichern.", _log_cat())
        return false
    
    state["version"] = SAVE_VERSION
    if _write_to_disk(state):
        _cached_state = state.duplicate(true)
        return true
    return false

# --- Private Logik ---

func _load_from_disk() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        Logger.log_info("Kein Savegame gefunden, lade Default.", _log_cat())
        _cached_state = {"version": SAVE_VERSION} # Oder dein DEFAULT_STATE
        return

    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if not file:
        Logger.log_error("Konnte Savegame nicht zum Lesen öffnen.", _log_cat())
        return

    var raw := file.get_as_text()
    var parsed = JSON.parse_string(raw)
    
    if parsed is Dictionary:
        _cached_state = _migrate_if_needed(parsed)
        Logger.log_info("Savegame erfolgreich geladen.", _log_cat())
    else:
        Logger.log_error("Savegame defekt (kein JSON-Dictionary).", _log_cat())

func _write_to_disk(state: Dictionary) -> bool:
    var json_string := JSON.stringify(state, "\t")
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    
    if not file:
        Logger.log_error("Konnte Savegame nicht zum Schreiben öffnen.", _log_cat())
        return false

    file.store_string(json_string)
    file.close()
    return true

func _migrate_if_needed(state: Dictionary) -> Dictionary:
    # Hier baust du sukzessive die Migrationskette auf (v1 -> v2 -> v3)
    var version := int(state.get("version", 0))
    if version < SAVE_VERSION:
        Logger.log_info("Migriere Savegame von v%d auf v%d" % [version, SAVE_VERSION], _log_cat())
        # Hier könntest du eine Kette von Migrations-Methoden aufrufen
    return state