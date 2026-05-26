extends Node

var levels = {"woodcutting": 1, "mining": 1}
var xp = {"woodcutting": 0, "mining": 0}

func _ready() -> void:
	add_to_group("skill_system")
	# Wir hören auf den globalen Bus!
	GameEvents.xp_gained.connect(add_xp)

func add_xp(skill: String, amount: int) -> void:
	xp[skill] += amount
	GameEvents.log("+ %d XP in %s" % [amount, skill])
	# Hier könnte Logik für Level-Up stehen