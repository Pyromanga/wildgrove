extends AnimalBase
class_name Snake

## Snake — Wunsch "mehr Körper für Tiere einbauen: ... Schlangen ...". BodyPlan.SNAKE
## (segmentierte S-Kurve statt Rumpf+Beine, siehe AnimalVisualBuilder._build_snake()).
## body_size.z ist hier die GESAMTLÄNGE, nicht wie beim Vierbeiner nur ein Beinversatz
## (siehe AnimalVisualProfile-Feldkommentar) — deshalb der ungewöhnlich große z-Wert
## unten trotz insgesamt kleinem Tier.

func _on_ready_extended() -> void:
	name        = "Snake"
	_color      = Color(0.30, 0.42, 0.18)
	_body_size  = Vector3(0.14, 0.10, 1.1)
	_speed      = 2.2
	_flee_radius = 3.0
	_idle_time  = 2.2
	_wander_range = 4.0
	_body_plan  = AnimalVisualProfile.BodyPlan.SNAKE

func get_inspect_text() -> String:
	return "Eine Schlange. Schlängelt sich lautlos durchs Unterholz."
