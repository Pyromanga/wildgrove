extends AnimalBase
class_name Bee

## Bee — Wunsch "mehr Körper für Tiere einbauen: Insekten ...". Erstes Tier mit
## BodyPlan.INSECT (siehe AnimalVisualProfile.BodyPlan-Kommentar) statt des
## Standard-Vierbeiners. Bleibt bewegungstechnisch ein ganz normales AnimalBase-Tier
## (läuft/fliegt NICHT wirklich über dem Boden — bewusst keine eigene Flug-KI, das wäre
## eine deutlich größere Änderung an _physics_process() als hier gewünscht), nur optisch
## ein Insekt: klein, schnell, sehr schreckhaft.

func _on_ready_extended() -> void:
	name        = "Bee"
	_color      = Color(0.95, 0.78, 0.12)
	_body_size  = Vector3(0.16, 0.14, 0.16)
	_speed      = 4.2
	_flee_radius = 5.0
	_idle_time  = 0.8
	_wander_range = 5.0
	_body_plan  = AnimalVisualProfile.BodyPlan.INSECT
	_wing_style = AnimalVisualProfile.WingStyle.TRANSLUCENT

func get_inspect_text() -> String:
	return "Eine Biene. Summt aufgeregt von Blüte zu Blüte."
