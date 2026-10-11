extends AnimalBase
class_name Bear

## Bear — Wunsch "mehr Körper für Tiere einbauen: ... aber auch große Säugetiere". Bleibt
## anatomisch BodyPlan.QUADRUPED (ein Bär ist ein Vierbeiner, siehe AnimalVisualBuilder.
## build()-Klassenkommentar) — "großes Säugetier" kommt hier rein aus deutlich größerer
## body_size plus BackStyle.HUMP (Schulterbuckel, siehe _add_back_feature()), nicht aus
## einem eigenen Bauplan. Deutlich geringerer _flee_radius/_speed als die Waldtiere: ein
## Bär rennt nicht aufgeregt bei jeder Annäherung weg.

func _on_ready_extended() -> void:
	name        = "Bear"
	_color      = Color(0.24, 0.17, 0.12)
	_body_size  = Vector3(0.95, 1.05, 0.95)
	_speed      = 3.4
	_flee_radius = 2.0
	_idle_time  = 3.0
	_wander_range = 9.0
	_ear_style   = AnimalVisualProfile.EarStyle.ROUND
	_snout_style = AnimalVisualProfile.SnoutStyle.LONG
	_tail_style  = AnimalVisualProfile.TailStyle.STUB
	_tail_scale  = 0.5
	_back_style  = AnimalVisualProfile.BackStyle.HUMP
	_body_shape  = AnimalVisualProfile.BodyShape.STOCKY
	_leg_style   = AnimalVisualProfile.LegStyle.THICK

func get_inspect_text() -> String:
	return "Ein Bär. Massig und ruhig — aber aus der Nähe trotzdem beeindruckend groß."
