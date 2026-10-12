# res://scripts/interfaces/core/ITickable.gd
# class_name entfernt (Legacy-Duplikat, Repo-Cleanup 2026-10-12 — Klassen-Registry-Konflikt s. Issue #5)


## Wird jeden Frame aufgerufen (wie _process)
func on_tick(delta: float) -> void:
	pass


## Wird für Physik-Updates aufgerufen (wie _physics_process)
func on_physics_tick(delta: float) -> void:
	pass
