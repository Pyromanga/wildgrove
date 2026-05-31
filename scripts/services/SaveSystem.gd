extends ServiceBase
class_name SaveSystem

const LOG_CAT        := "SaveSystem"
const SAVE_PATH      := "user://savegame.json"
const SAVE_VERSION   := 1

const DEFAULT_STATE : Dictionary = {
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

func _ready() -> void:
	super._ready()

func init() -> void:
	super.init()
	_cached_state = _load_from_disk()
	_is_loaded = true

func get_state() -> Dictionary:
	if not _is_loaded:
		return {}
	return _cached_state.duplicate(true)

func save_state(state: Dictionary) -> bool:
	if state.is_empty(): return false
	
	state["version"] = SAVE_VERSION
	var success := _write_to_disk(state)
	
	if success:
		_cached_state = state.duplicate(true)
	return success

# ─────────────────────────────────────────────
# Die kritischen Fixes (Disk I/O)
# ─────────────────────────────────────────────

func _load_from_disk() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return DEFAULT_STATE.duplicate(true)

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return DEFAULT_STATE.duplicate(true)

	var raw := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	
	# Hier wurde oft der Typ-Fehler geworfen:
	if parsed is Dictionary:
		return _migrate_if_needed(parsed as Dictionary)
	
	# WICHTIG: Immer ein Return am Ende für alle Code-Pfade!
	return DEFAULT_STATE.duplicate(true)

func _write_to_disk(state: Dictionary) -> bool:
	# FIX Zeile 149: Expliziter Cast auf String
	var json_string: String = JSON.stringify(state, "\t")
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		return false

	file.store_string(json_string)
	file.close()
	return true

# ─────────────────────────────────────────────
# Migration Fixes
# ─────────────────────────────────────────────

func _migrate_if_needed(state: Dictionary) -> Dictionary:
	# Expliziter Cast auf int, damit der Variant-Error verschwindet
	var version := int(state.get("version", 0))

	if version == SAVE_VERSION:
		return state

	if version < 1:
		state = _migrate_v0_to_v1(state)

	# Auch hier: Sicherstellen, dass am Ende IMMER das Dictionary zurückgeht
	return state

func _migrate_v0_to_v1(old: Dictionary) -> Dictionary:
	var migrated := DEFAULT_STATE.duplicate(true)
	if old.has("player"):
		var old_player = old.get("player")
		if old_player is Dictionary:
			migrated["player"].merge(old_player, true)
	migrated["version"] = 1
	return migrated