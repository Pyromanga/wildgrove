extends ServiceNode
class_name DataService

## DataService — Zentrales Repository für ALLE statischen Spieldaten.
##
## REFACTOR (Session 4):
##   VORHER: Lud nur PlayerData.tres. Item-DB lebte in InventorySystem,
##           Quest-Definitionen in QuestService. Drei Services luden unabhängig
##           Daten — kein zentrales Repository, kein Caching, inkonsistente Pfade.
##   NACHHER: Einziger Ladeort für alle statischen .tres-Ressourcen.
##            InventorySystem und QuestService rufen get_item() / get_quest() auf,
##            statt selbst DirAccess zu öffnen.
##
## Was DataService lädt:
##   - PlayerData.tres       → Spieler-Konfiguration (Speed, Gravity, …)
##   - data/items/*.tres     → ItemDefinition-Ressourcen
##   - data/quests/*.tres    → QuestDefinition-Ressourcen (wenn vorhanden)
##   - data/skills/*.tres    → SkillDefinition-Ressourcen (wenn vorhanden)
##
## Was DataService NICHT tut:
##   - Keinen Laufzeit-State halten (Inventar, Quest-Fortschritt, Skills)
##   - Kein SaveSystem-Provider (statische Daten ändern sich nicht)

const LOG_CAT := "DataService"

const PLAYER_DATA_PATH  := "res://config/PlayerData.tres"
const ITEMS_PATH        := "res://data/items/"
const QUESTS_PATH       := "res://data/quests/"
const SKILLS_PATH       := "res://data/skills/"

var player_data: PlayerData

## Repositories — befüllt in configure()
var _items:  Dictionary = {}   # { item_id:  ItemDefinition  }
var _quests: Dictionary = {}   # { quest_id: QuestDefinition }
var _skills: Dictionary = {}   # { skill_id: SkillDefinition } — leer bis SkillDefinition.tres existieren


# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(_deps: Dictionary) -> void:
	var t := Logger.log_begin("DataService.configure()", LOG_CAT)
	_load_player_data()
	_load_items()
	_load_quests()
	_load_skills()
	Logger.log_end("DataService.configure()", t, LOG_CAT)
	Logger.log_info(
		"Geladen: %d Items, %d Quests, %d Skills."
		% [_items.size(), _quests.size(), _skills.size()],
		LOG_CAT
	)


# ─────────────────────────────────────────────
# Öffentliche API — PlayerData
# ─────────────────────────────────────────────


## Liest einen numerischen Spieler-Konfigurationswert.
func get_player_stat(stat_name: String, default_val: float = 0.0) -> float:
	if not player_data:
		Logger.log_error("Abfrage '%s' fehlgeschlagen: player_data ist NULL!" % stat_name, LOG_CAT)
		return default_val

	var value: Variant = player_data.get(stat_name)
	if value != null:
		return float(value)

	Logger.log_warn("Stat '%s' existiert nicht in PlayerData.tres!" % stat_name, LOG_CAT)
	return default_val


## Setzt einen Stat im Speicher (nicht persistiert — nur für Runtime-Tweaks).
func set_player_stat(stat_name: String, value: float) -> void:
	if player_data:
		if stat_name in player_data:
			player_data.set(stat_name, value)
		else:
			Logger.log_warn("Versuch unbekannten Stat zu setzen: %s" % stat_name, LOG_CAT)


# ─────────────────────────────────────────────
# Öffentliche API — Items
# ─────────────────────────────────────────────


## Gibt die ItemDefinition für eine ID zurück, oder null.
func get_item(item_id: String) -> ItemDefinition:
	return _items.get(item_id)


## Gibt alle geladenen Items zurück (für InventorySystem-Initialisierung).
func get_all_items() -> Dictionary:
	return _items


# ─────────────────────────────────────────────
# Öffentliche API — Quests
# ─────────────────────────────────────────────


## Gibt die QuestDefinition für eine ID zurück, oder null.
func get_quest(quest_id: String) -> QuestDefinition:
	return _quests.get(quest_id)


## Gibt alle geladenen Quest-Definitionen zurück.
func get_all_quests() -> Dictionary:
	return _quests


## Gibt alle Quest-IDs mit auto_start=true zurück (für QuestService-Initialisierung).
func get_auto_start_quests() -> Array[String]:
	var result: Array[String] = []
	for id in _quests:
		var q: QuestDefinition = _quests[id]
		if q.auto_start:
			result.append(id)
	return result


# ─────────────────────────────────────────────
# Öffentliche API — Skills
# ─────────────────────────────────────────────


## Gibt alle geladenen SkillDefinitions zurück.
## Leer bis res://data/skills/*.tres Dateien existieren.
func get_all_skills() -> Dictionary:
	return _skills


# ─────────────────────────────────────────────
# Intern — Lader
# ─────────────────────────────────────────────


func _load_player_data() -> void:
	if not ResourceLoader.exists(PLAYER_DATA_PATH):
		Logger.log_error("KRITISCH: PlayerData fehlt unter '%s'!" % PLAYER_DATA_PATH, LOG_CAT)
		return
	player_data = load(PLAYER_DATA_PATH) as PlayerData
	if player_data:
		Logger.log_debug("PlayerData geladen.", LOG_CAT)
	else:
		Logger.log_error("PlayerData konnte nicht gecastet werden!", LOG_CAT)


func _load_items() -> void:
	_items = _load_resources_from_dir(ITEMS_PATH, ItemDefinition, "id")
	Logger.log_debug("Items geladen: %d" % _items.size(), LOG_CAT)


func _load_quests() -> void:
	_quests = _load_resources_from_dir(QUESTS_PATH, QuestDefinition, "id")
	if _quests.is_empty():
		Logger.log_debug("Keine Quest-Definitionen in '%s' — noch nicht erstellt." % QUESTS_PATH, LOG_CAT)
	else:
		Logger.log_debug("Quests geladen: %d" % _quests.size(), LOG_CAT)


func _load_skills() -> void:
	# SkillDefinition.tres-Dateien werden in einem späteren Schritt erstellt.
	# Bis dahin bleibt das Dictionary leer — kein Fehler.
	if DirAccess.dir_exists_absolute(SKILLS_PATH):
		_skills = _load_resources_from_dir(SKILLS_PATH, null, "id")
		Logger.log_debug("Skills geladen: %d" % _skills.size(), LOG_CAT)
	else:
		Logger.log_debug("Skills-Pfad '%s' noch nicht vorhanden." % SKILLS_PATH, LOG_CAT)


## Generischer Ressourcen-Lader für ein Verzeichnis.
## key_field: Feldname der als Dictionary-Key verwendet wird (typisch "id").
## expected_class: Wenn nicht null, wird ein Typ-Check gemacht.
func _load_resources_from_dir(path: String, expected_class: Variant, key_field: String) -> Dictionary:
	var result: Dictionary = {}

	if not DirAccess.dir_exists_absolute(path):
		return result

	var dir := DirAccess.open(path)
	if not dir:
		Logger.log_warn("Konnte Verzeichnis '%s' nicht öffnen." % path, LOG_CAT)
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var full_path := path + file_name
			var res: Resource = load(full_path)

			if res == null:
				Logger.log_warn("Resource konnte nicht geladen werden: '%s'" % full_path, LOG_CAT)
				file_name = dir.get_next()
				continue

			# Type-Check wenn expected_class angegeben
			if expected_class != null and not is_instance_of(res, expected_class):
				Logger.log_warn(
					"'%s' ist kein %s — übersprungen." % [file_name, str(expected_class)], LOG_CAT
				)
				file_name = dir.get_next()
				continue

			var key: Variant = res.get(key_field)
			if key == null or (key is String and (key as String).is_empty()):
				Logger.log_warn("Resource '%s': Feld '%s' fehlt oder leer." % [file_name, key_field], LOG_CAT)
				file_name = dir.get_next()
				continue

			result[str(key)] = res

		file_name = dir.get_next()

	dir.list_dir_end()
	return result
