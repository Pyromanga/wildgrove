extends AnimalBase
class_name Squirrel

## Squirrel — Wunsch "ein paar mehr Tiere einbauen". Klein, sehr flink, extrem schreckhaft
## (kleiner _flee_radius reicht trotzdem, weil auch der _wander_range klein bleibt — ein
## Eichhörnchen soll nicht wie ein Reh quer über den Chunk flüchten). Ikonisch großer
## Schwanz über tail_scale, ohne ein eigenes TailStyle-Enum-Mitglied zu brauchen.

func _on_ready_extended() -> void:
	name        = "Squirrel"
	_color      = Color(0.55, 0.34, 0.20)
	_body_size  = Vector3(0.20, 0.24, 0.20)
	_speed      = 4.6
	_flee_radius = 4.0
	_idle_time  = 1.2
	_wander_range = 4.0
	_ear_style   = AnimalVisualProfile.EarStyle.POINTY
	_tail_style  = AnimalVisualProfile.TailStyle.BUSHY
	_tail_scale  = 1.6

func get_inspect_text() -> String:
	return "Ein Eichhörnchen. Huscht in Sekundenbruchteilen den nächsten Stamm hoch."
