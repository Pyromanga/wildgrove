extends AnimalBase
class_name Spider

## Spider — Wunsch "mehr Körper für Tiere einbauen: ... Spinnen ...". BodyPlan.SPIDER
## (8 Beine, Cephalothorax + Hinterleib, siehe AnimalVisualBuilder._build_spider()).
## Flieht kaum (kleiner _flee_radius) und wandert nur wenig — Spinnen wirken bodenständiger
## als die flinken Waldtiere, kein Gegner, kein Kampfverhalten.

func _on_ready_extended() -> void:
	name        = "Spider"
	_color      = Color(0.16, 0.13, 0.11)
	_body_size  = Vector3(0.22, 0.14, 0.22)
	_speed      = 2.6
	_flee_radius = 2.2
	_idle_time  = 1.6
	_wander_range = 3.0
	_body_plan  = AnimalVisualProfile.BodyPlan.SPIDER

func get_inspect_text() -> String:
	return "Eine Spinne. Acht Beine, null Interesse an dir — solange du ihr fernbleibst."
