extends Node
## SkillSystem.gd — Der Manager für Fortschritt

var skills = {
	"woodcutting": {"xp": 0, "level": 1},
	"mining": {"xp": 0, "level": 1},
	"farming": {"xp": 0, "level": 1}
}

func _ready() -> void:
	Kernel.events.xp_gained.connect(add_xp)

func add_xp(skill_name: String, amount: int) -> void:
	if not skills.has(skill_name):
		return
	skills[skill_name]["xp"] += amount
	_check_level_up(skill_name)
	Kernel.events.log("XP erhalten: +%d %s" % [amount, skill_name])

func _check_level_up(skill_name: String) -> void:
	var current_xp = skills[skill_name]["xp"]
	var current_lvl = skills[skill_name]["level"]
	var next_level_xp = Kernel.utils.get_xp_for_level(current_lvl + 1)
	if current_xp >= next_level_xp:
		skills[skill_name]["level"] += 1
		Kernel.events.log("LEVEL UP! %s ist jetzt Level %d" % [skill_name, skills[skill_name]["level"]])