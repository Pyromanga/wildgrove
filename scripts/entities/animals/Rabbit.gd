extends AnimalBase
class_name Rabbit

func _on_ready_extended() -> void:
	name        = "Rabbit"
	_color      = Color(0.80, 0.75, 0.68)
	_body_size  = Vector3(0.22, 0.28, 0.22)
	_speed      = 4.0
	_flee_radius = 4.5
	_idle_time  = 1.5
	_wander_range = 5.0
	_ear_style   = AnimalVisualProfile.EarStyle.LONG
	_tail_style  = AnimalVisualProfile.TailStyle.FLUFFY
	_tail_scale  = 0.8
	_leg_style   = AnimalVisualProfile.LegStyle.SHORT

func get_inspect_text() -> String:
	return "Ein Hase. Flauschig, schnell — und sehr scheu."
