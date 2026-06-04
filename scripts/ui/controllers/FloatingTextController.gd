class_name FloatingTextController

## FloatingTextController — zeigt XP-Gains und Level-Ups als schwebenden Text.
## Lauscht nur auf PlayerEvents — level_up lebt dort, nicht in SkillSystem.

var _visuals: FloatingTextVisuals


func setup(visuals: FloatingTextVisuals, player_events: PlayerEvents) -> void:
	assert(player_events != null, "FloatingTextController.setup: player_events ist null!")
	_visuals = visuals
	player_events.xp_gained.connect(_on_xp_gained)
	player_events.level_up.connect(_on_level_up)


func _on_xp_gained(skill: String, amount: int) -> void:
	_visuals.spawn_text("+%d %s" % [amount, skill], Color(1.0, 0.9, 0.2), 24, 2.0)


func _on_level_up(skill: String, new_level: int) -> void:
	_visuals.spawn_text("LEVEL UP!\n%s → %d" % [skill, new_level], Color(0.2, 0.8, 1.0), 32, 3.0)
