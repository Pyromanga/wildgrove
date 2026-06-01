extends ServiceNode
class_name SkillSystem

signal level_up(skill_name: String, new_level: int)

var skills = {
    "woodcutting": {"xp": 0, "level": 1},
    "mining":      {"xp": 0, "level": 1},
    "farming":     {"xp": 0, "level": 1}
}

func init() -> void:
    super.init()
    # Verbindung zum Event-Bus (da du den Kernel nutzt)
    var events = Kernel.get_service("events")
    if events:
        events.player.xp_gained.connect(add_xp)

func add_xp(skill_name: String, amount: int) -> void:
    if not skills.has(skill_name):
        return
    skills[skill_name]["xp"] += amount
    _check_level_up(skill_name)
    Logger.log_debug("XP: +%d %s" % [amount, skill_name], "SkillSystem")

func _check_level_up(skill_name: String) -> void:
    var xp: int = skills[skill_name]["xp"]
    var lvl: int = skills[skill_name]["level"]
    
    # Formel jetzt lokal im Service!
    if xp >= _calculate_required_xp(lvl + 1):
        skills[skill_name]["level"] += 1
        var new_lvl = skills[skill_name]["level"]
        Logger.log_debug("LEVEL UP! %s → %d" % [skill_name, new_lvl], "SkillSystem")
        level_up.emit(skill_name, new_lvl)

## Die XP-Formel – jetzt als private Methode hier gekapselt
func _calculate_required_xp(level: int) -> int:
    return int(0.25 * floor(level + 300.0 * pow(2.0, level / 7.0)))