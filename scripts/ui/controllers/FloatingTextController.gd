class_name FloatingTextController

var _visuals: FloatingTextVisuals

func setup(visuals: FloatingTextVisuals) -> void:
    _visuals = visuals
    Kernel.events.player.xp_gained.connect(_on_xp_gained)
    Kernel.events.skill_system.level_up.connect(_on_level_up)

func _on_xp_gained(skill: String, amount: int) -> void:
    _visuals.spawn_text("+%d %s" % [amount, skill], Color(1, 0.9, 0.2), 24, 2.0)