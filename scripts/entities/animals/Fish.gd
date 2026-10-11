extends AnimalBase
class_name Fish

## Fish — Wunsch "mehr Körper für Tiere einbauen: ... Fische ...". BodyPlan.FISH (siehe
## AnimalVisualBuilder._build_fish()) UND _aquatic = true (siehe AnimalBase._aquatic-
## Feldkommentar: keine Schwerkraft, sanftes Auf-und-Ab statt Fallen/Stehen). Wird NICHT
## über ChunkEntitySpawner.ANIMAL_TYPES (Landtiere) gespawnt, sondern über die eigene
## ChunkEntitySpawner._spawn_fish() (siehe dort) an flachen Uferstellen/im Wasser.
## body_size.z ist hier die Länge, body_size.x die Breite, body_size.y die Höhe (siehe
## AnimalVisualProfile-Feldkommentar) — bewusst asymmetrisch, nicht wie beim Vierbeiner.

func _on_ready_extended() -> void:
	name        = "Fish"
	_color      = Color(0.42, 0.58, 0.68)
	_body_size  = Vector3(0.14, 0.22, 0.42)
	_speed      = 2.0
	_flee_radius = 3.0
	_idle_time  = 1.0
	_wander_range = 3.0
	_body_plan  = AnimalVisualProfile.BodyPlan.FISH
	_aquatic    = true

func get_inspect_text() -> String:
	return "Ein Fisch. Gleitet knapp unter der Wasseroberfläche dahin."
