extends AnimalBase
class_name Deer

func _on_ready_extended() -> void:
	name        = "Deer"
	_color      = Color(0.62, 0.42, 0.22)
	_body_size  = Vector3(0.55, 0.85, 0.55)
	_speed      = 5.5
	_flee_radius = 7.0
	_idle_time  = 3.0
	_wander_range = 10.0
	_ear_style      = AnimalVisualProfile.EarStyle.LONG
	_snout_style    = AnimalVisualProfile.SnoutStyle.LONG
	_headgear_style = AnimalVisualProfile.HeadgearStyle.ANTLERS
	_body_shape     = AnimalVisualProfile.BodyShape.SLENDER
	_leg_style      = AnimalVisualProfile.LegStyle.LONG

func get_inspect_text() -> String:
	return "Ein Reh. Es äugt misstrauisch in deine Richtung."
