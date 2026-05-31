extends ServiceBase
class_name SaveSystem

## SaveSystem.gd
## Speichert und lädt den Spielstand als JSON.
## Unterstützt Versionierung für spätere Migrationen.
## Muss vor GameManager initialisiert werden (dep in ServiceLoader).

const LOG_CAT        := "SaveSystem"
const SAVE_PATH      := "user://savegame.json"
const SAVE_VERSION   := 1  # Erhöhen wenn Saveformat sich ändert

# Leerer Default-Stand — GameManager bekommt das wenn kein Save existiert
const DEFAULT_STATE := {
	"version":      SAVE_VERSION,
	"player": {
		"name":     "Abenteurer",
		"level":    1,
		"xp":       {},
		"position": { "x": 0.0, "y": 0.0, "z": 0.0 },
	},
	"world": {
		"day":      1,
		"hour":     6,
		"seed":     0,
	},
	"settings": {
		"music_volume":  1.0,
		"sfx_volume":    1.0,
		"shadow_quality": 1,
	},
	"inventory": [],
}

var _cached_state: Dictionary = {}
var _is_loaded: bool = false

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	Logger.log_debug("SaveSystem._ready()", LOG_CAT)
	super._ready()

func init() -> void:
	super.init()
	Logger.log_info("init() — Lade Spielstand...", LOG_CAT)
	_cached_state = _load_from_disk()
	_is_loaded = true
	Logger.log_info("Spielstand geladen. Version: %d" % _cached_state.get("version", -1), LOG_CAT)

func on_ready() -> void:
	super.on_ready()
	Logger.log_debug("on_ready() — SaveSystem vollständig bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Gibt den geladenen Spielstand zurück.
## Sicher aufzurufen nach init() — gibt DEFAULT_STATE wenn kein Save existiert.
func get_state() -> Dictionary:
	if not _is_loaded:
		Logger.log_warn("get_state() vor init() aufgerufen! Gebe leeres Dict zurück.", LOG_CAT)
		return {}
	return _cached_state.duplicate(true)  # deep copy — niemand soll direkt mutieren

## Speichert einen neuen Zustand auf Disk.
func save_state(state: Dictionary) -> bool:
	Logger.log_info("save_state() aufgerufen...", LOG_CAT)

	if state.is_empty():
		Logger.log_error("Leeres State-Dictionary übergeben — Abbruch.", LOG_CAT)
		return false

	# Version immer aktuell halten
	state["version"] = SAVE_VERSION

	var events := Kernel.get_service("events") as GameEvents
	if events:
		events.system.emit_save_started()

	var success := _write_to_disk(state)

	if success:
		_cached_state = state.duplicate(true)
		Logger.log_info("Spielstand erfolgreich gespeichert.", LOG_CAT)
	else:
		Logger.log_error("Speichern fehlgeschlagen!", LOG_CAT)

	if events:
		events.system.emit_save_completed(success)

	return success

## Löscht den Spielstand (New Game).
func delete_save() -> void:
	Logger.log_warn("delete_save() aufgerufen — Spielstand wird gelöscht!", LOG_CAT)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		Logger.log_info("Spielstand-Datei gelöscht: %s" % SAVE_PATH, LOG_CAT)
	else:
		Logger.log_debug("Keine Spielstand-Datei vorhanden — nichts zu löschen.", LOG_CAT)
	_cached_state = DEFAULT_STATE.duplicate(true)
	_is_loaded = false

func has_save() -> bool:
	var exists := FileAccess.file_exists(SAVE_PATH)
	Logger.log_debug("has_save() → %s" % str(exists), LOG_CAT)
	return exists

# ─────────────────────────────────────────────
# Private: Disk I/O
# ─────────────────────────────────────────────

func _load_from_disk() -> Dictionary:
	Logger.log_debug("_load_from_disk() — Pfad: '%s'" % SAVE_PATH, LOG_CAT)

	if not FileAccess.file_exists(SAVE_PATH):
		Logger.log_info("Kein Spielstand gefunden — verwende DEFAULT_STATE.", LOG_CAT)
		return DEFAULT_STATE.duplicate(true)

	Logger.log_debug("Datei gefunden. Öffne...", LOG_CAT)
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		Logger.log_error("Datei konnte nicht geöffnet werden! Fehler: %d" % FileAccess.get_open_error(), LOG_CAT)
		return DEFAULT_STATE.duplicate(true)

	var raw := file.get_as_text()
	file.close()
	Logger.log_debug("Datei gelesen (%d Zeichen). Parse JSON..." % raw.length(), LOG_CAT)

	var parsed := JSON.parse_string(raw)
	if parsed == null:
		Logger.log_error("JSON-Parse fehlgeschlagen! Inhalt: '%s'" % raw.left(200), LOG_CAT)
		return DEFAULT_STATE.duplicate(true)

	if not parsed is Dictionary:
		Logger.log_error("JSON ist kein Dictionary! Typ: %s" % typeof(parsed), LOG_CAT)
		return DEFAULT_STATE.duplicate(true)

	Logger.log_debug("JSON geparst. Prüfe Version...", LOG_CAT)
	return _migrate_if_needed(parsed)

func _write_to_disk(state: Dictionary) -> bool:
	Logger.log_debug("_write_to_disk() — Pfad: '%s'" % SAVE_PATH, LOG_CAT)

  var json_raw: Variant = JSON.stringify(state, "\t")
  var json_string: String = str(json_raw)
	Logger.log_debug("Serialisiert: %d Zeichen." % json_string.length(), LOG_CAT)

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		Logger.log_error("Datei konnte nicht zum Schreiben geöffnet werden! Fehler: %d" % FileAccess.get_open_error(), LOG_CAT)
		return false

	file.store_string(json_string)
	file.close()
	Logger.log_debug("Datei geschlossen. Schreiben erfolgreich.", LOG_CAT)
	return true

# ─────────────────────────────────────────────
# Migration
# ─────────────────────────────────────────────

func _migrate_if_needed(state: Dictionary) -> Dictionary:
	var version: int = state.get("version", 0)
	Logger.log_debug("Save-Version: %d, aktuelle Version: %d" % [version, SAVE_VERSION], LOG_CAT)

	if version == SAVE_VERSION:
		Logger.log_debug("Keine Migration nötig.", LOG_CAT)
		return state

	Logger.log_warn("Veralteter Spielstand (v%d) — migriere zu v%d..." % [version, SAVE_VERSION], LOG_CAT)

	# Migrations-Chain: v0 → v1 → v2 → ...
	if version < 1:
		state = _migrate_v0_to_v1(state) as Dictionary

	# Hier später weitere Migrationen anfügen:
	# if version < 2:
	#     state = _migrate_v1_to_v2(state) as Dictionary

	Logger.log_info("Migration abgeschlossen. Neuer Stand: v%d" % state.get("version", -1), LOG_CAT)
	return state

func _migrate_v0_to_v1(old: Dictionary) -> Dictionary:
	Logger.log_debug("Migriere v0 → v1...", LOG_CAT)
	# Fehlende Keys mit Defaults auffüllen
	var migrated := DEFAULT_STATE.duplicate(true)
	# Bekannte v0-Felder rüberretten wenn vorhanden
	if old.has("player"):
		migrated["player"].merge(old["player"], true)
	migrated["version"] = 1
	Logger.log_debug("v0 → v1 Migration abgeschlossen.", LOG_CAT)
	return migrated