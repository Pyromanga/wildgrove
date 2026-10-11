extends AnimalBase
class_name Boar

func _on_ready_extended() -> void:
	name        = "Boar"
	_color      = Color(0.28, 0.20, 0.14)
	_body_size  = Vector3(0.65, 0.60, 0.65)
	_speed      = 3.8
	_flee_radius = 3.0   # Wildschweine flüchten nicht so schnell
	_idle_time  = 2.5
	_wander_range = 12.0
	_ear_style      = AnimalVisualProfile.EarStyle.ROUND
	_snout_style    = AnimalVisualProfile.SnoutStyle.LONG
	_headgear_style = AnimalVisualProfile.HeadgearStyle.TUSKS
	_body_shape     = AnimalVisualProfile.BodyShape.STOCKY
	_leg_style      = AnimalVisualProfile.LegStyle.SHORT

func get_inspect_text() -> String:
	return "Ein Wildschwein. Wühlt im Boden nach Eicheln. Besser nicht stören."
