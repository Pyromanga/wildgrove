extends ServiceBase
# class_name SkillSystem  <-- Nur behalten, wenn es KEIN Autoload ist. 
# Falls es ein Service ist, der über den Kernel registriert wird, ist class_name okay.

var skills = {
	"woodcutting": {"xp": 0, "level": 1},
	"mining":      {"xp": 0, "level": 1},
	"farming":     {"xp": 0, "level": 1}
}

func _ready() -> void:
	super._ready()
	Kernel.events.player.xp_gained.connect(add_xp)

func add_xp(skill_name: String, amount: int) -> void:
	if not skills.has(skill_name):
		return
	skills[skill_name]["xp"] += amount
	_check_level_up(skill_name)
	Logger.log_debug("XP: +%d %s" % [amount, skill_name], "SkillSystem")

func _check_level_up(skill_name: String) -> void:
	# FIX: Explizite Typen statt Inferenz (:=) aus dem Dictionary
	var xp: int = skills[skill_name]["xp"]
	var lvl: int = skills[skill_name]["level"]
	
	if xp >= Kernel.utils.get_xp_for_level(lvl + 1):
		skills[skill_name]["level"] += 1
		Logger.log_debug("LEVEL UP! %s → %d" % [skill_name, skills[skill_name]["level"]], "SkillSystem")