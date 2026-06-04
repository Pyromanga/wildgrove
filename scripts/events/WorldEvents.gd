class_name WorldEvents extends BaseEvents

## WorldEvents.gd
## Alle weltbezogenen Signals.

signal interaction_started(label: String, duration: float)
signal interaction_finished(label: String)
signal interaction_cancelled(label: String)
signal chunk_loaded(chunk_id: Vector2i)
signal chunk_unloaded(chunk_id: Vector2i)
signal time_of_day_changed(hour: int)


func _init() -> void:
	super._init("Events/World")


func emit_interaction_started(label: String, duration: float) -> void:
	_log("Interaktion gestartet: '%s' (%.1fs)" % [label, duration])
	interaction_started.emit(label, duration)


func emit_interaction_finished(label: String) -> void:
	_log("Interaktion beendet: '%s'" % label)
	interaction_finished.emit(label)


func emit_interaction_cancelled(label: String) -> void:
	_log_warn("Interaktion abgebrochen: '%s'" % label)
	interaction_cancelled.emit(label)


func emit_chunk_loaded(chunk_id: Vector2i) -> void:
	_log("Chunk geladen: %s" % str(chunk_id))
	chunk_loaded.emit(chunk_id)


func emit_chunk_unloaded(chunk_id: Vector2i) -> void:
	_log("Chunk entladen: %s" % str(chunk_id))
	chunk_unloaded.emit(chunk_id)


func emit_time_of_day_changed(hour: int) -> void:
	_log("Tageszeit: %02d:00" % hour)
	time_of_day_changed.emit(hour)
