extends ServiceNode
class_name SkillSystem

## SkillSystem — Berechnet XP-Fortschritt und Level-Ups.
## Emittiert level_up über Kernel.events.player (PlayerEvents),
## weil Level-Ups Spieler-Events sind — nicht Service-interne Events.

const LOG_CAT := "SkillSystem"

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
	Logger.log_debug("+%d XP '%s' (gesamt: %d)" % [amount, skill_name, skills[skill_name]["xp"]], LOG_CAT)
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
	if entry["xp"] < _calculate_required_xp(entry["level"] + 1):
		return

	entry["level"] += 1
	Logger.log_info("Level Up! '%s' → %d" % [skill_name, entry["level"]], LOG_CAT)

	# Event über PlayerEvents — level_up gehört dem Spieler, nicht dem Service
	if Kernel.events and Kernel.events.player:
		Kernel.events.player.emit_level_up(skill_name, entry["level"])

	# Mehrfach-Levelup möglich bei sehr viel XP auf einmal
	_check_level_up(skill_name)

func _calculate_required_xp(level: int) -> int:
	return int(0.25 * floor(float(level) + 300.0 * pow(2.0, float(level) / 7.0)))