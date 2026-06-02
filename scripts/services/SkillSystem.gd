extends ServiceNode
class_name SkillSystem

## SkillSystem — Verwaltet XP und Levels aller Skills.
## Lauscht auf player.xp_gained über den Event-Bus.

signal level_up(skill_name: String, new_level: int)

const LOG_CAT := "SkillSystem"

## Alle Skills mit ihren Startwerten.
## Erweiterbar ohne Code-Änderung — einfach neuen Key hinzufügen.
var skills: Dictionary = {
	"woodcutting": {"xp": 0, "level": 1},
	"mining":      {"xp": 0, "level": 1},
	"farming":     {"xp": 0, "level": 1},
}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	super._ready()

func init() -> void:
	super.init()

func on_ready() -> void:
	super.on_ready()
	if Kernel.events and Kernel.events.player:
		Kernel.events.player.xp_gained.connect(add_xp)
		Logger.log_info("SkillSystem bereit.", LOG_CAT)
	else:
		Logger.log_warn("Events nicht verfügbar — XP-Gains werden nicht empfangen.", LOG_CAT)

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

func get_xp_for_next_level(skill_name: String) -> int:
	var current_level := get_level(skill_name)
	return _calculate_required_xp(current_level + 1)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _check_level_up(skill_name: String) -> void:
	var entry: Dictionary = skills[skill_name]
	var xp:    int        = entry["xp"]
	var lvl:   int        = entry["level"]

	if xp >= _calculate_required_xp(lvl + 1):
		entry["level"] += 1
		Logger.log_info("Level Up! '%s' → Level %d" % [skill_name, entry["level"]], LOG_CAT)
		level_up.emit(skill_name, entry["level"])

		# Sofort weiteres Level-Up prüfen (Mehrfach-Levelup durch viel XP möglich)
		_check_level_up(skill_name)

## Runescape-inspirierte XP-Formel.
func _calculate_required_xp(level: int) -> int:
	return int(0.25 * floor(float(level) + 300.0 * pow(2.0, float(level) / 7.0)))