extends ServiceNode
class_name SkillSystem

## SkillSystem — Berechnet XP-Fortschritt und Level-Ups.
## Abhängigkeiten (deps): ["data"]

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
	Services.save_system.register_save_provider(self)

	# FIX: War `var saved := ...` — gleicher Typfehler wie in WorldService.
	# get_state_for() hat keinen deklarierten Rückgabetyp → := kann nicht ableiten.
	var saved: Dictionary = Services.save_system.get_state_for(SAVE_KEY)
	if not saved.is_empty():
		for skill_name in saved:
			if skills.has(skill_name):
				skills[skill_name] = saved[skill_name]
			else:
				Logger.log_debug("Veralteter Skill im Save: '%s'" % skill_name, LOG_CAT)

	Logger.log_info("Initialisiert.", LOG_CAT)

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
	_check_level_up(skill_name)

func get_level(skill_name: String) -> int:
	return skills.get(skill_name, {"level": 1})["level"]

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
	EventBus.player.emit_level_up(skill_name, entry["level"])
	_check_level_up(skill_name)

func _calculate_required_xp(level: int) -> int:
	# OSRS-Formel
	return int(0.25 * floor(float(level) + 300.0 * pow(2.0, float(level) / 7.0)))