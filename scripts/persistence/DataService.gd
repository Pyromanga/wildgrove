extends Service
class_name DataService

## DataService — Zentrales Repository für ALLE statischen Spieldaten.
##
###   kein zentrales Repository, kein Caching, inkonsistente Pfade.
##   Jetzt: einziger Ladeort für alle statischen .tres-Ressourcen. InventorySystem
##   und QuestService rufen get_item() / get_quest() auf, statt selbst DirAccess
##   zu öffnen.
##
## Was DataService lädt:
##   - PlayerData.tres       → Spieler-Konfiguration (Speed, Gravity, …)
##   - data/items/*.tres     → ItemDefinition-Ressourcen
##   - data/quests/*.tres    → QuestDefinition-Ressourcen (wenn vorhanden)
##   - data/skills/*.tres    → SkillDefinition-Ressourcen (wenn vorhanden)
##   - data/combat_profiles/*.tres → CombatProfile-Ressourcen (TD-10, ADR-008)
##   - data/achievements/*.tres → AchievementDefinition-Ressourcen (Round 103,
##     ADR-046 "Umsetzungsstand (Round 103)")
##
## Was DataService NICHT tut:
##   - Keinen Laufzeit-State halten (Inventar, Quest-Fortschritt, Skills)
##   - Kein SaveSystem-Provider (statische Daten ändern sich nicht)

const LOG_CAT := "DataService"

const PLAYER_DATA_PATH := "res://config/PlayerData.tres"
# Item/Quest/Skill-Pfade sind jetzt in DataManifest — kein DirAccess mehr nötig.

var player_data: PlayerData

## Repositories — befüllt in configure()
var _items:  Dictionary = {}   # { item_id:  ItemDefinition  }
var _quests: Dictionary = {}   # { quest_id: QuestDefinition }
var _skills: Dictionary = {}   # { skill_id: SkillDefinition } — leer bis SkillDefinition.tres existieren
var _combat_profiles: Dictionary = {}   # { profile_id: CombatProfile } — TD-10
var _loot_tables: Dictionary = {}       # { table_id: LootTable }
var _achievements: Dictionary = {}      # { achievement_id: AchievementDefinition } — Round 103
var _crops: Dictionary = {}             # { crop_id: FarmCropDefinition } — Farming-Feature
var _build_pieces: Dictionary = {}      # { piece_id: BuildPieceDefinition } — Bausystem
var _build_piece_order: Array[String] = []   # Manifest-Reihenfolge (Bau-Menü)
var _house_templates: Dictionary = {}   # { template_id: HouseTemplateDefinition } — komplette Häuser
var _house_template_order: Array[String] = []   # Manifest-Reihenfolge (Bau-Menü)
var _smithing_recipes: Dictionary = {}  # { recipe_id: SmithingRecipe } — Schmelzen & Schmieden
var _smithing_recipe_order: Array[String] = []  # Manifest-Reihenfolge (Reihenfolge im Schmiede-Panel)

# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(_deps: ServiceDeps) -> void:
	var t := AppLogger.log_begin("DataService.configure()", LOG_CAT)
	_load_player_data()
	_load_items()
	_load_quests()
	_load_skills()
	_load_combat_profiles()
	_load_loot_tables()
	_load_achievements()
	_load_crops()
	_load_build_pieces()
	_load_house_templates()
	_load_smithing_recipes()
	AppLogger.log_end("DataService.configure()", t, LOG_CAT)
	AppLogger.log_info(
		"Geladen: %d Items, %d Quests, %d Skills, %d CombatProfiles, %d LootTables, %d Achievements, %d Crops."
		% [_items.size(), _quests.size(), _skills.size(), _combat_profiles.size(), _loot_tables.size(), _achievements.size(), _crops.size()],
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Öffentliche API — PlayerData
# ─────────────────────────────────────────────

## Liest einen numerischen Spieler-Konfigurationswert.
func get_player_stat(stat_name: String, default_val: float = 0.0) -> float:
	if not player_data:
		AppLogger.log_error("Abfrage '%s' fehlgeschlagen: player_data ist NULL!" % stat_name, LOG_CAT)
		return default_val

	var value: Variant = player_data.get(stat_name)
	if value != null:
		return float(value)

	AppLogger.log_warn("Stat '%s' existiert nicht in PlayerData.tres!" % stat_name, LOG_CAT)
	return default_val

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
# Öffentliche API — CombatProfiles (TD-10)
# ─────────────────────────────────────────────

## Gibt das CombatProfile für eine ID zurück, oder ein neutrales Default-Profil
## (keine Resistenz) wenn die ID unbekannt ist — z.B. eine neue Entity-Klasse
## ohne eigenes .tres. Gibt NIEMALS null zurück, damit Call-Sites keinen
## zusätzlichen Null-Check brauchen.
func get_combat_profile(profile_id: String) -> CombatProfile:
	var profile: CombatProfile = _combat_profiles.get(profile_id)
	if profile == null:
		AppLogger.log_warn(
			"CombatProfile '%s' nicht gefunden — nutze Default (keine Resistenz)." % profile_id,
			LOG_CAT
		)
		return CombatProfile.default_profile()
	return profile

## Gibt alle geladenen CombatProfiles zurück.
func get_all_combat_profiles() -> Dictionary:
	return _combat_profiles

# ─────────────────────────────────────────────
# Öffentliche API — Achievements (Round 103, ADR-046 "Umsetzungsstand (Round 103)")
# ─────────────────────────────────────────────

## Gibt die AchievementDefinition für eine ID zurück, oder null.
func get_achievement(achievement_id: String) -> AchievementDefinition:
	return _achievements.get(achievement_id)

## Gibt alle geladenen AchievementDefinitions zurück.
func get_all_achievements() -> Dictionary:
	return _achievements

# ─────────────────────────────────────────────
# Intern — Lader
# ─────────────────────────────────────────────

func _load_player_data() -> void:
	if not ResourceLoader.exists(PLAYER_DATA_PATH):
		AppLogger.log_error("KRITISCH: PlayerData fehlt unter '%s'!" % PLAYER_DATA_PATH, LOG_CAT)
		return
	player_data = load(PLAYER_DATA_PATH) as PlayerData
	if player_data:
		AppLogger.log_debug(
			"PlayerData geladen. Speed=%.1f, Gravity=%.1f." % [player_data.speed, player_data.gravity],
			LOG_CAT
		)
	else:
		AppLogger.log_error(
			"PlayerData Cast fehlgeschlagen — Script-Pfad in PlayerData.tres prüfen! "
			+ "Erwartet: res://scripts/entities/player/PlayerData.gd",
			LOG_CAT
		)

func _load_items() -> void:
	_items = {}
	for path: String in DataManifest.ITEMS:
		var res: Resource = load(path)
		if res == null:
			AppLogger.log_warn("Item nicht ladbar: '%s'" % path, LOG_CAT)
			continue
		if not res is ItemDefinition:
			AppLogger.log_warn("'%s' ist kein ItemDefinition." % path, LOG_CAT)
			continue
		var item := res as ItemDefinition
		_items[item.id] = item
	# Anziehbare Kleidung (cl_*) wird nicht als .tres gepflegt, sondern aus dem Look-Katalog
	# erzeugt (siehe WearableCatalog) — erst NACH den .tres, damit eine Datei Vorrang hätte.
	WearableCatalog.register_into(_items)
	AppLogger.log_debug("Items geladen: %d" % _items.size(), LOG_CAT)

func _load_quests() -> void:
	_quests = {}
	for path: String in DataManifest.QUESTS:
		var res: Resource = load(path)
		if res == null:
			AppLogger.log_warn("Quest nicht ladbar: '%s'" % path, LOG_CAT)
			continue
		if not res is QuestDefinition:
			AppLogger.log_warn("'%s' ist kein QuestDefinition." % path, LOG_CAT)
			continue
		var quest := res as QuestDefinition
		_quests[quest.id] = quest
	AppLogger.log_debug("Quests geladen: %d" % _quests.size(), LOG_CAT)

func _load_skills() -> void:
	_skills = {}
	for path: String in DataManifest.SKILLS:
		var res: Resource = load(path)
		if res == null:
			AppLogger.log_warn("Skill nicht ladbar: '%s'" % path, LOG_CAT)
			continue
		# SkillDefinition ist optional — kein Fehler wenn Klasse noch nicht existiert
		if res.get("id") == null:
			AppLogger.log_warn("'%s' hat kein 'id'-Feld." % path, LOG_CAT)
			continue
		_skills[str(res.get("id"))] = res
	AppLogger.log_debug("Skills geladen: %d" % _skills.size(), LOG_CAT)

func _load_combat_profiles() -> void:
	_combat_profiles = {}
	for path: String in DataManifest.COMBAT_PROFILES:
		var res: Resource = load(path)
		if res == null:
			AppLogger.log_warn("CombatProfile nicht ladbar: '%s'" % path, LOG_CAT)
			continue
		if not res is CombatProfile:
			AppLogger.log_warn("'%s' ist kein CombatProfile." % path, LOG_CAT)
			continue
		var profile := res as CombatProfile
		_combat_profiles[profile.id] = profile
	AppLogger.log_debug("CombatProfiles geladen: %d" % _combat_profiles.size(), LOG_CAT)

func _load_achievements() -> void:
	_achievements = {}
	for path: String in DataManifest.ACHIEVEMENTS:
		var res: Resource = load(path)
		if res == null:
			AppLogger.log_warn("Achievement nicht ladbar: '%s'" % path, LOG_CAT)
			continue
		if not res is AchievementDefinition:
			AppLogger.log_warn("'%s' ist kein AchievementDefinition." % path, LOG_CAT)
			continue
		var achievement := res as AchievementDefinition
		_achievements[achievement.id] = achievement
	AppLogger.log_debug("Achievements geladen: %d" % _achievements.size(), LOG_CAT)

## Farming (Wunsch "Samen pflanzen + ernten"): analog get_combat_profile().
func get_crop_definition(crop_id: String) -> FarmCropDefinition:
	var crop: FarmCropDefinition = _crops.get(crop_id)
	if crop == null:
		AppLogger.log_warn("Unbekannte crop_id '%s'." % crop_id, LOG_CAT)
	return crop

func _load_crops() -> void:
	_crops = {}
	for path: String in DataManifest.CROPS:
		var res: Resource = load(path)
		if res == null:
			AppLogger.log_warn("FarmCropDefinition nicht ladbar: '%s'" % path, LOG_CAT)
			continue
		if not res is FarmCropDefinition:
			AppLogger.log_warn("'%s' ist keine FarmCropDefinition." % path, LOG_CAT)
			continue
		var crop := res as FarmCropDefinition
		_crops[crop.id] = crop
	AppLogger.log_debug("Crops geladen: %d" % _crops.size(), LOG_CAT)

## Bausystem: Definition eines Bauteils (null + Warnung, wenn unbekannt).
func get_build_piece(piece_id: String) -> BuildPieceDefinition:
	var piece: BuildPieceDefinition = _build_pieces.get(piece_id)
	if piece == null:
		AppLogger.log_warn("Unbekannte build_piece_id '%s'." % piece_id, LOG_CAT)
	return piece

## Alle Bauteile in Manifest-Reihenfolge (für das Bau-Menü).
func get_all_build_pieces() -> Array[BuildPieceDefinition]:
	var out: Array[BuildPieceDefinition] = []
	for piece_id in _build_piece_order:
		out.append(_build_pieces[piece_id])
	return out

func _load_build_pieces() -> void:
	_build_pieces = {}
	_build_piece_order = []
	for path: String in DataManifest.BUILD_PIECES:
		var res: Resource = load(path)
		if res == null:
			AppLogger.log_warn("BuildPieceDefinition nicht ladbar: '%s'" % path, LOG_CAT)
			continue
		if not res is BuildPieceDefinition:
			AppLogger.log_warn("'%s' ist keine BuildPieceDefinition." % path, LOG_CAT)
			continue
		var piece := res as BuildPieceDefinition
		_build_pieces[piece.id] = piece
		_build_piece_order.append(piece.id)
	AppLogger.log_debug("Bauteile geladen: %d" % _build_pieces.size(), LOG_CAT)

## Bausystem: komplette Häuser (HouseTemplateDefinition, siehe dortiger Klassenkommentar).
func get_house_template(template_id: String) -> HouseTemplateDefinition:
	var house: HouseTemplateDefinition = _house_templates.get(template_id)
	if house == null:
		AppLogger.log_warn("Unbekannte house_template_id '%s'." % template_id, LOG_CAT)
	return house

## Alle Häuser in Manifest-Reihenfolge (für das Bau-Menü).
func get_all_house_templates() -> Array[HouseTemplateDefinition]:
	var out: Array[HouseTemplateDefinition] = []
	for template_id in _house_template_order:
		out.append(_house_templates[template_id])
	return out

func _load_house_templates() -> void:
	_house_templates = {}
	_house_template_order = []
	for path: String in DataManifest.HOUSE_TEMPLATES:
		var res: Resource = load(path)
		if res == null:
			AppLogger.log_warn("HouseTemplateDefinition nicht ladbar: '%s'" % path, LOG_CAT)
			continue
		if not res is HouseTemplateDefinition:
			AppLogger.log_warn("'%s' ist keine HouseTemplateDefinition." % path, LOG_CAT)
			continue
		var house := res as HouseTemplateDefinition
		_house_templates[house.id] = house
		_house_template_order.append(house.id)
	AppLogger.log_debug("Hausvorlagen geladen: %d" % _house_templates.size(), LOG_CAT)

func get_loot_table(table_id: String) -> LootTable:
	return _loot_tables.get(table_id)

## Round 108 (ADR-049): für WikiPanelController — enumeriert alle geladenen
## Loot-Tabellen als Katalog für die "drops"-Kategorie (unentdeckte Einträge
## werden als "???"-Platzhalter angezeigt, siehe WikiPanelVisuals-
## Klassenkommentar "UNENTDECKT").
func get_all_loot_tables() -> Dictionary:
	return _loot_tables

func _load_loot_tables() -> void:
	_loot_tables = {}
	if DataManifest.LOOT_TABLES.is_empty():
		return
	for path: String in DataManifest.LOOT_TABLES:
		var res: Resource = load(path)
		if res == null:
			AppLogger.log_warn("LootTable nicht ladbar: '%s'" % path, LOG_CAT)
			continue
		if not res is LootTable:
			AppLogger.log_warn("'%s' ist keine LootTable." % path, LOG_CAT)
			continue
		# Tabellenname aus Dateiname ableiten (z.B. goblin_loot.tres → goblin_loot)
		var table_id := path.get_file().get_basename()
		_loot_tables[table_id] = res
	AppLogger.log_debug("LootTables geladen: %d" % _loot_tables.size(), LOG_CAT)

## Schmieden: Rezept per Id (null + Warnung, wenn unbekannt).
func get_smithing_recipe(recipe_id: String) -> SmithingRecipe:
	var recipe: SmithingRecipe = _smithing_recipes.get(recipe_id)
	if recipe == null:
		AppLogger.log_warn("Unbekannte smithing_recipe_id '%s'." % recipe_id, LOG_CAT)
	return recipe

## Alle Schmiede-Rezepte in Manifest-Reihenfolge (für das Schmiede-Panel).
func get_all_smithing_recipes() -> Array[SmithingRecipe]:
	var out: Array[SmithingRecipe] = []
	for recipe_id in _smithing_recipe_order:
		out.append(_smithing_recipes[recipe_id])
	return out

## Die Rezepte EINER Station ("furnace" | "anvil") in Manifest-Reihenfolge.
func get_smithing_recipes_for_station(station_kind: String) -> Array[SmithingRecipe]:
	var out: Array[SmithingRecipe] = []
	for recipe_id in _smithing_recipe_order:
		var recipe: SmithingRecipe = _smithing_recipes[recipe_id]
		if recipe.is_available_at(station_kind):
			out.append(recipe)
	return out

func _load_smithing_recipes() -> void:
	_smithing_recipes = {}
	_smithing_recipe_order = []
	for path: String in DataManifest.SMITHING_RECIPES:
		var res: Resource = load(path)
		if res == null:
			AppLogger.log_warn("SmithingRecipe nicht ladbar: '%s'" % path, LOG_CAT)
			continue
		if not res is SmithingRecipe:
			AppLogger.log_warn("'%s' ist kein SmithingRecipe." % path, LOG_CAT)
			continue
		var recipe := res as SmithingRecipe
		var problems := recipe.validation_errors()
		if not problems.is_empty():
			AppLogger.log_warn("SmithingRecipe '%s' ungültig (%s) — übersprungen." % [path, ", ".join(problems)], LOG_CAT)
			continue
		_smithing_recipes[recipe.id] = recipe
		_smithing_recipe_order.append(recipe.id)
	AppLogger.log_debug("Schmiede-Rezepte geladen: %d" % _smithing_recipes.size(), LOG_CAT)
