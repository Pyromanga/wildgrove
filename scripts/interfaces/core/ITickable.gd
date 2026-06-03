# res://scripts/interfaces/i_tickable.gd
class_name ITickable

## Wird jeden Frame aufgerufen (wie _process)
func on_tick(delta: float) -> void:
	pass

## Wird für Physik-Updates aufgerufen (wie _physics_process)
func on_physics_tick(delta: float) -> void:
	pass