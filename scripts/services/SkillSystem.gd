extends ServiceNode
class_name SkillSystem

## SkillSystem — Berechnet XP-Fortschritt und Level-Ups.
## Abhängigkeiten (deps): ["data", "savesystem"]
##
## REFACTOR (Session 4):
##   VORHER: Hardkodiertes Dictionary { "woodcutting": {...}, ... }
##           → neuer Skill = Code-Änderung
##   NACHHER: Initialisiert sich aus DataService.get_all_skills()
##            → neuer Skill = neue res://data/skills/<id>.tres
##   Fallback auf drei Basis-Skills wenn DataService keine liefert (Dev-Modus).

const LOG_CAT := "SkillSystem"
const SAVE_KEY := "skills"

var _data_service: DataService
var _save_system:  SaveSystem
var _definitions:  Dictionary = {}   # { skill_id: SkillDefinition }

## Laufzeit-State: { skill_id: { "xp": int, "level": int } }
var skills: Dictionary = {}


# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────


func configure(deps: Dictionary) -> void:
	_data_service = deps.get("data")      as DataService
	_save_system  = deps.get("savesystem") as SaveSystem

	_init_skills_from_definitions()

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Dictionary = _save_system.get_state_for(SAVE_KEY)
		if not saved.is_empty():
			_restore_from_save(saved)

	Logger.log_info(
		"Initialisiert. %d Skills registriert." % skills.size(), LOG_CAT
	)


# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────


func on_ready() -> void:
	EventBus.player.xp_gained.connect(add_xp)
	Logger.log_info("SkillSystem mit EventBus verbunden.", LOG_CAT)


# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────


func get_save_key() -> String:
	return SAVE_KEY


func get_save_data() -> Dictionary:
	return skills.duplicate(true)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func add_xp(skill_name: String, amount: int) -> void:
	if not skills.has(skill_name):
		Logger.log_warn("Unbekannter Skill: '%s'" % skill_name, LOG_CAT)
		return
	skills[skill_name]["xp"] += amount
	Logger.log_debug("+%d XP in '%s' (gesamt: %d)" % [amount, skill_name, skills[skill_name]["xp"]], LOG_CAT)
	_check_level_up(skill_name)


func get_level(skill_name: String) -> int:
	return skills.get(skill_name, {"level": 1})["level"]


func get_xp(skill_name: String) -> int:
	return skills.get(skill_name, {"xp": 0})["xp"]


func get_xp_to_next_level(skill_name: String) -> int:
	var def: SkillDefinition = _definitions.get(skill_name)
	if not def:
		return 100  # Fallback
	return def.get_xp_required(get_level(skill_name))


func has_skill(skill_name: String) -> bool:
	return skills.has(skill_name)


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _init_skills_from_definitions() -> void:
	if is_instance_valid(_data_service):
		_definitions = _data_service.get_all_skills()

	if not _definitions.is_empty():
		for skill_id in _definitions:
			skills[skill_id] = {"xp": 0, "level": 1}
		Logger.log_debug(
			"Skills aus DataService geladen: %s" % str(_definitions.keys()), LOG_CAT
		)
	else:
		# Fallback-Skills wenn noch keine .tres-Dateien existieren
		_definitions = {}
		skills = {
			"woodcutting": {"xp": 0, "level": 1},
			"mining":       {"xp": 0, "level": 1},
			"farming":      {"xp": 0, "level": 1},
		}
		Logger.log_debug(
			"Keine SkillDefinitions in DataService — nutze Fallback-Skills.", LOG_CAT
		)


func _check_level_up(skill_name: String) -> void:
	var entry: Dictionary = skills[skill_name]
	var def:   SkillDefinition = _definitions.get(skill_name)

	# XP-Schwelle bestimmen
	var xp_needed: int
	if def:
		xp_needed = def.get_xp_required(entry["level"])
		if def.max_level >= 0 and entry["level"] >= def.max_level:
			return  # MaxLevel erreicht
	else:
		# Fallback-Formel wenn keine Definition vorhanden
		xp_needed = entry["level"] * 100

	if entry["xp"] >= xp_needed:
		entry["xp"]   -= xp_needed
		entry["level"] += 1
		Logger.log_info(
			"LEVEL UP! '%s' ist jetzt Level %d." % [skill_name, entry["level"]], LOG_CAT
		)
		EventBus.player.emit_level_up(skill_name, entry["level"])
		# Rekursiv prüfen für Kaskaden-Level-Ups
		_check_level_up(skill_name)


func _restore_from_save(saved: Dictionary) -> void:
	for skill_name in saved:
		if skills.has(skill_name):
			skills[skill_name] = saved[skill_name]
		else:
			Logger.log_debug("Veralteter Skill im Save: '%s' — übersprungen." % skill_name, LOG_CAT)
