extends AnimalBase
class_name Fox

## Fox — Wunsch "ein paar mehr Tiere einbauen". Wendig, aufmerksam, flieht früh (großer
## _flee_radius) — anders als Boar/Deer aber genauso ungefährlich, kein Gegner.

func _on_ready_extended() -> void:
	name        = "Fox"
	_color      = Color(0.72, 0.32, 0.14)
	_body_size  = Vector3(0.34, 0.45, 0.34)
	_speed      = 5.2
	_flee_radius = 6.5
	_idle_time  = 2.0
	_wander_range = 9.0
	_ear_style   = AnimalVisualProfile.EarStyle.POINTY
	_tail_style  = AnimalVisualProfile.TailStyle.BUSHY
	_snout_style = AnimalVisualProfile.SnoutStyle.LONG
	_body_shape  = AnimalVisualProfile.BodyShape.SLENDER
	_leg_style   = AnimalVisualProfile.LegStyle.THIN

func get_inspect_text() -> String:
	return "Ein Fuchs. Wachsam und schnell — bei der kleinsten Bewegung ist er weg."
