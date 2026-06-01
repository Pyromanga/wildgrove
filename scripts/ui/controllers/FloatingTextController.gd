# scripts/ui/controllers/floating_text_controller.gd
class_name FloatingTextController

var _visuals: FloatingTextVisuals

# Wir übergeben jetzt explizit die benötigten Event-Busse
func setup(visuals: FloatingTextVisuals, player_events: Object, skill_events: Object) -> void:
    _visuals = visuals
    player_events.xp_gained.connect(_on_xp_gained)
    skill_events.level_up.connect(_on_level_up)

func _on_xp_gained(skill: String, amount: int) -> void:
    _visuals.spawn_text("+%d %s" % [amount, skill], Color(1, 0.9, 0.2), 24, 2.0)

func _on_level_up(skill: String, level: int) -> void:
    _visuals.spawn_text("LEVEL UP! %s -> %d" % [skill, level], Color(0.2, 0.8, 1.0), 32, 3.0)