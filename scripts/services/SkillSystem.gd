extends ServiceNode
class_name SkillSystem

## SkillSystem — Berechnet XP-Fortschritt und Level-Ups.
## Abhängigkeiten: ["savesystem"] (optional, falls du XP speichern willst)

const LOG_CAT := "SkillSystem"
const SAVE_KEY := "skills"

var skills: Dictionary = {
	"woodcutting": {"xp": 0, "level": 1},
	"mining":      {"xp": 0, "level": 1},
	"farming":     {"xp": 0, "level": 1},
}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	# 1. Beim SaveSystem registrieren
	Services.save_system.register_save_provider(self)
	
	# 2. Daten wiederherstellen (sofort aus dem RAM)
	var saved := Services.save_system.get_state_for(SAVE_KEY)
	if not saved.is_empty():
		for skill_name in saved:
      if skills.has(skill_name):
        skills[skill_name] = saved[skill_name]
      else:
        Logger.log_debug("Veralteter Skill im Save gefunden: %s" % skill_name, LOG_CAT)
		
	Logger.log_info("Initialisiert.", LOG_CAT)

func on_ready() -> void:
	# Hier nutzen wir den EventBus direkt. Er ist ein AutoLoad, 
	# also IMMER da. Keine Null-Checks mehr nötig!
	EventBus.player.xp_gained.connect(add_xp)
	Logger.log_info("SkillSystem mit EventBus verbunden.", LOG_CAT)

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return skills.duplicate(true) # true für deep copy, da nested Dictionaries

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func add_xp(skill_name: String, amount: int) -> void:
	if not skills.has(skill_name):
		Logger.log_warn("Unbekannter Skill: '%s'" % skill_name, LOG_CAT)
		return
		
	skills[skill_name]["xp"] += amount
	_check_level_up(skill_name)

func get_level(skill_name: String) -> int:
	return skills.get(skill_name, {"level": 1})["level"]

func get_xp(skill_name: String) -> int:
	return skills.get(skill_name, {"xp": 0})["xp"]

func get_xp_for_next_level(skill_name: String) -> int:
	return _calculate_required_xp(get_level(skill_name) + 1)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _check_level_up(skill_name: String) -> void:
	var entry: Dictionary = skills[skill_name]
	var req_xp := _calculate_required_xp(entry["level"] + 1)
	
	if entry["xp"] < req_xp:
		return

	entry["level"] += 1
	Logger.log_info("Level Up! '%s' → %d" % [skill_name, entry["level"]], LOG_CAT)

	# Event-Emission über den neuen EventBus
	EventBus.player.emit_level_up(skill_name, entry["level"])

	# Rekursiver Check für Mehrfach-Levelups
	_check_level_up(skill_name)

func _calculate_required_xp(level: int) -> int:
    # Deine RPG-Formel (die übrigens sehr nach Runescape aussieht, nice!)
	return int(0.25 * floor(float(level) + 300.0 * pow(2.0, float(level) / 7.0)))