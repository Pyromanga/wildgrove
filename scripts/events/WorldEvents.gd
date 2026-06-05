class_name WorldEvents extends BaseEvents

## WorldEvents.gd
## Alle weltbezogenen Signals.
##
## Neu hinzugefügte Signale:
##   world_scene_ready   — World.tscn vollständig geladen; HUDManager lauscht hier.
##   loot_collected      — InteractableComponent meldet Drops; InventorySystem lauscht.
##   interaction_reward_text — Belohnungstext nach Interaktion; NotificationController lauscht.

signal interaction_started(label: String, duration: float)
signal interaction_finished(label: String)
signal interaction_cancelled(label: String)
signal chunk_loaded(chunk_id: Vector2i)
signal chunk_unloaded(chunk_id: Vector2i)
signal time_of_day_changed(hour: int)

## Wird von WorldService emittiert sobald die Spielwelt-Szene vollständig im Tree ist.
## HUDManager reagiert darauf und hängt das HUD-Canvas ein.
signal world_scene_ready(world_root: Node)

## Wird von InteractableComponent nach jeder abgeschlossenen Aktion emittiert.
## InventorySystem horcht hier und fügt Items hinzu — statt direkter Service-Kopplung.
signal loot_collected(item_id: String, quantity: int)

## Wird von InteractableComponent emittiert wenn ein inspect_text vorliegt.
## NotificationController horcht hier und zeigt den Text im HUD.
signal interaction_reward_text(text: String)


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


func emit_world_scene_ready(world_root: Node) -> void:
	_log_info("World-Szene bereit: %s" % world_root.name)
	world_scene_ready.emit(world_root)


func emit_loot_collected(item_id: String, quantity: int) -> void:
	_log("Loot: %dx '%s'" % [quantity, item_id])
	loot_collected.emit(item_id, quantity)


func emit_interaction_reward_text(text: String) -> void:
	_log("Belohnungstext: '%s'" % text)
	interaction_reward_text.emit(text)
