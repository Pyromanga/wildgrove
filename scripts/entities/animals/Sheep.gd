extends AnimalBase
class_name Sheep

## Sheep — Wunsch "ein paar mehr Tiere einbauen". Ruhiges, kaum flüchtendes Weidetier
## (kleiner _flee_radius/_wander_range, langsam) — bewusster Kontrast zu den scheuen
## Waldtieren (Reh/Hase/Fuchs/Eichhörnchen), passt zu Dorf/Friedhof-Umgebung mit Zäunen.

func _on_ready_extended() -> void:
	name        = "Sheep"
	_color      = Color(0.88, 0.85, 0.78)
	_body_size  = Vector3(0.58, 0.55, 0.62)
	_speed      = 2.4
	_flee_radius = 2.5
	_idle_time  = 3.5
	_wander_range = 4.0
	_ear_style  = AnimalVisualProfile.EarStyle.FLOPPY
	_tail_style = AnimalVisualProfile.TailStyle.STUB
	_body_shape = AnimalVisualProfile.BodyShape.ROUND
	_leg_style  = AnimalVisualProfile.LegStyle.SHORT

func get_inspect_text() -> String:
	return "Ein Schaf. Wolliges Fell, träges Gemüt — läuft höchstens gemächlich weg."
