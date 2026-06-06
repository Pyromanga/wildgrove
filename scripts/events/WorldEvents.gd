class_name WorldEvents extends BaseEvents

## WorldEvents.gd
## Alle weltbezogenen Signals.
##
## Namenskonvention: emit_*() Methoden für jeden Event.
## Controller/Services connecten auf die raw signals.

## REFACTOR (Session 4): interaction_started/finished/cancelled erhalten jetzt action_id
## zusätzlich zum label. InteractableComponent matcht per id (eindeutig pro Entity-Typ),
## nicht per label (doppelte "Eiche fällen"-Labels würden alle Bars gleichzeitig zeigen).
signal interaction_started(action_id: String, label: String, duration: float)
signal interaction_finished(action_id: String, label: String)
signal interaction_cancelled(action_id: String, label: String)
signal chunk_loaded(chunk_id: Vector2i)
signal chunk_unloaded(chunk_id: Vector2i)
signal time_of_day_changed(hour: int)

## Wird von WorldService emittiert sobald die Spielwelt-Szene vollständig im Tree ist.
signal world_scene_ready(world_root: Node)

## Wird von WorldService emittiert wenn die Welt entladen wird (Szenenwechsel).
signal world_scene_unloaded

## Wird von InteractableComponent nach jeder abgeschlossenen Aktion emittiert.
signal loot_collected(item_id: String, quantity: int)

## Wird von InteractableComponent emittiert wenn ein inspect_text vorliegt.
signal interaction_reward_text(text: String)

## Wird von InteractableComponent emittiert wenn sich das nächste Interagierbare ändert.
## InteractionButtonController lauscht hier statt in _process() zu pollen.
signal proximity_changed(target: Node3D, in_range: bool)

## Entity-Lifecycle-Events (von EntityOrchestrator emittiert).
signal entity_spawned(type_id: String, entity: Node3D, position: Vector3)
signal entity_despawned(type_id: String, uuid: String)


func _init() -> void:
	super._init("Events/World")


func emit_interaction_started(action_id: String, label: String, duration: float) -> void:
	_log("Interaktion gestartet: '%s' / id='%s' (%.1fs)" % [label, action_id, duration])
	interaction_started.emit(action_id, label, duration)


func emit_interaction_finished(action_id: String, label: String) -> void:
	_log("Interaktion beendet: '%s' / id='%s'" % [label, action_id])
	interaction_finished.emit(action_id, label)


func emit_interaction_cancelled(action_id: String, label: String) -> void:
	_log_warn("Interaktion abgebrochen: '%s' / id='%s'" % [label, action_id])
	interaction_cancelled.emit(action_id, label)


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


func emit_world_scene_unloaded() -> void:
	_log_info("World-Szene entladen.")
	world_scene_unloaded.emit()


func emit_loot_collected(item_id: String, quantity: int) -> void:
	_log("Loot: %dx '%s'" % [quantity, item_id])
	loot_collected.emit(item_id, quantity)


func emit_interaction_reward_text(text: String) -> void:
	_log("Belohnungstext: '%s'" % text)
	interaction_reward_text.emit(text)


func emit_proximity_changed(target: Node3D, in_range: bool) -> void:
	if is_instance_valid(target):
		if in_range:
			_log("Nähe erkannt: '%s'" % target.name)
		else:
			_log("Nähe verlassen: '%s'" % target.name)
	proximity_changed.emit(target, in_range)


func emit_entity_spawned(type_id: String, entity: Node3D, position: Vector3) -> void:
	_log("Entity gespawnt: type='%s' pos=%s" % [type_id, str(position)])
	entity_spawned.emit(type_id, entity, position)


func emit_entity_despawned(type_id: String, uuid: String) -> void:
	_log("Entity despawnt: type='%s' uuid='%s'" % [type_id, uuid])
	entity_despawned.emit(type_id, uuid)
