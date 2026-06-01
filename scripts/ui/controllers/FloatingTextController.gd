class_name FloatingTextController

var _hud: HUD

func setup(hud: HUD) -> void:
    _hud = hud
    Kernel.events.player.xp_gained.connect(_on_xp_gained)
    Kernel.events.skill_system.level_up.connect(_on_level_up)

func _on_xp_gained(skill: String, amount: int) -> void:
    _hud.show_floating_text("+%d %s" % [amount, skill], Color(1, 0.9, 0.2))

func _on_level_up(skill: String, new_level: int) -> void:
    _hud.show_floating_text("%s Stufe %d!" % [skill, new_level], Color(0.2, 1, 0.2), 36, 3.0)