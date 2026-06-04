extends Node
class_name EntityOrchestrator

## EntityOrchestrator — Zuständig für Entity-Lifecycle und Gruppen-Management.
##
## Trennung der Verantwortlichkeiten:
##   ServiceOrchestrator  →  Services (singletons, laufen die gesamte Spielzeit)
##   EntityOrchestrator   →  Entities (Instanzen, leben nur in einer Szene/Welt)
##
## Entities sind spielweltspezifische Objekte wie NPCs, Gegner, Ressourcen,
## Truhen, Türen — alles was instanziiert, konfiguriert und wieder zerstört wird.
##
## Vorteile:
##   - Services bleiben schlank: kein Entity-Tracking-Code im ServiceOrchestrator
##   - Entities werden sauber aufgeräumt bei Szenenwechsel (queue_free der Welt)
##   - Zukünftige Features (Chunk-Loading, Multiplayer-Spawn, Object Pooling)
##     haben einen zentralen Anlaufpunkt
##
## Verwendung (von WorldService.on_world_scene_ready() aufgerufen):
##   var eo: EntityOrchestrator = EntityOrchestrator.new()
##   eo.initialize(world_root)
##   eo.spawn_entity("oak_tree", Vector3(5, 0, 5))

const LOG_CAT := "EntityOrchestrator"

## Referenz auf die aktuelle Welt-Szene (wird bei Szenenwechsel ersetzt)
var _world_root: Node3D = null

## Registry der aktiven Entities: { uuid: Node3D }
var _entities: Dictionary = {}

## Entity-Definitionen: { type_id: { "path": "res://...", "group": "trees" } }
## Wird aus einer zukünftigen EntityRegistry.tres befüllt
var _definitions: Dictionary = {}

## Object Pool: { type_id: Array[Node3D] }
var _pool: Dictionary = {}
const POOL_SIZE := 10


# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────


## Initialisiert den Orchestrator für eine neue Welt-Szene.
## Muss aufgerufen werden bevor spawn_entity() nutzbar ist.
func initialize(world_root: Node3D) -> void:
	_world_root = world_root
	_entities.clear()
	Logger.log_info("EntityOrchestrator initialisiert für '%s'." % world_root.name, LOG_CAT)


## Wird von der aktuellen Welt aufgerufen bevor sie destroyed wird.
## Sichert Entity-States und räumt Referenzen auf.
func on_world_unloaded() -> void:
	Logger.log_info("World-Unload: %d Entities werden bereinigt." % _entities.size(), LOG_CAT)
	for uuid in _entities.keys():
		var entity := _entities[uuid] as Node3D
		if is_instance_valid(entity) and entity.has_method("on_despawn"):
			entity.on_despawn()
	_entities.clear()
	_world_root = null
	Logger.log_debug("EntityOrchestrator zurückgesetzt.", LOG_CAT)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


## Instanziiert eine Entity anhand ihrer type_id aus der Definition.
## Gibt die Entity zurück oder null bei Fehler.
func spawn_entity(type_id: String, position: Vector3, config: Dictionary = {}) -> Node3D:
	if not is_instance_valid(_world_root):
		Logger.log_error("spawn_entity('%s') fehlgeschlagen: Kein world_root." % type_id, LOG_CAT)
		return null

	var def: Dictionary = _definitions.get(type_id, {})
	if def.is_empty():
		Logger.log_warn("Unbekannte Entity-Type: '%s'. Prüfe EntityOrchestrator._definitions." % type_id, LOG_CAT)
		return null

	var entity := _create_or_pool(type_id, def)
	if not is_instance_valid(entity):
		return null

	entity.global_position = position

	var uuid := _generate_uuid()
	entity.set_meta("entity_uuid", uuid)
	entity.set_meta("entity_type", type_id)
	_entities[uuid] = entity

	_world_root.add_child(entity)

	if entity.has_method("on_spawn"):
		entity.on_spawn(config)

	Logger.log_debug(
		"Entity gespawnt: type='%s' uuid='%s' pos=%s" % [type_id, uuid, str(position)], LOG_CAT
	)
	return entity


## Despawnt eine Entity anhand ihrer UUID. Gibt sie in den Pool zurück wenn möglich.
func despawn_entity(uuid: String) -> void:
	if not _entities.has(uuid):
		Logger.log_warn("despawn_entity('%s'): UUID nicht gefunden." % uuid, LOG_CAT)
		return

	var entity := _entities[uuid] as Node3D
	_entities.erase(uuid)

	if not is_instance_valid(entity):
		return

	var type_id: String = entity.get_meta("entity_type", "")
	if entity.has_method("on_despawn"):
		entity.on_despawn()

	if _try_return_to_pool(type_id, entity):
		Logger.log_debug("Entity '%s' in Pool zurückgegeben." % uuid, LOG_CAT)
	else:
		entity.queue_free()
		Logger.log_debug("Entity '%s' freigegeben (queue_free)." % uuid, LOG_CAT)


## Registriert eine Entity-Definition. Ersetzt zukünftig eine .tres-basierte Definition.
func register_definition(type_id: String, script_path: String, group: String = "") -> void:
	_definitions[type_id] = {"path": script_path, "group": group}
	Logger.log_debug("Entity-Definition registriert: '%s'" % type_id, LOG_CAT)


## Gibt alle aktiven Entities einer bestimmten Gruppe zurück.
func get_entities_in_group(group: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for uuid in _entities:
		var entity := _entities[uuid] as Node3D
		if is_instance_valid(entity) and entity.is_in_group(group):
			result.append(entity)
	return result


## Gibt die Anzahl der aktiven Entities zurück. Nützlich für Debug-Logging.
func get_entity_count() -> int:
	return _entities.size()


## Gibt die Entity mit einer bestimmten UUID zurück, oder null.
func get_entity(uuid: String) -> Node3D:
	return _entities.get(uuid)


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _create_or_pool(type_id: String, def: Dictionary) -> Node3D:
	# Pool-Check
	if _pool.has(type_id) and not _pool[type_id].is_empty():
		var pooled := _pool[type_id].pop_back() as Node3D
		if is_instance_valid(pooled):
			Logger.log_debug("Entity aus Pool: '%s'" % type_id, LOG_CAT)
			return pooled

	# Neu instanziieren
	var path: String = def.get("path", "")
	if path.is_empty() or not ResourceLoader.exists(path):
		Logger.log_error("Entity-Pfad fehlt oder nicht vorhanden: '%s'" % path, LOG_CAT)
		return null

	var loaded = load(path)
	if loaded == null:
		Logger.log_error("Entity-Script konnte nicht geladen werden: '%s'" % path, LOG_CAT)
		return null

	var instance: Node3D
	if loaded is PackedScene:
		instance = loaded.instantiate() as Node3D
	elif loaded is GDScript:
		instance = loaded.new() as Node3D
	else:
		Logger.log_error("Ungültiger Typ für Entity '%s': %s" % [type_id, loaded.get_class()], LOG_CAT)
		return null

	var group: String = def.get("group", "")
	if not group.is_empty():
		instance.add_to_group(group)

	return instance


func _try_return_to_pool(type_id: String, entity: Node3D) -> bool:
	if type_id.is_empty():
		return false

	if not _pool.has(type_id):
		_pool[type_id] = []

	if _pool[type_id].size() < POOL_SIZE:
		if entity.is_inside_tree() and is_instance_valid(entity.get_parent()):
			entity.get_parent().remove_child(entity)
		_pool[type_id].append(entity)
		return true

	return false


func _generate_uuid() -> String:
	# Einfaches UUID-ähnliches Format für Entity-Tracking
	# Für Multiplayer: durch echte UUID-Bibliothek ersetzen
	var time := Time.get_ticks_usec()
	var rand := randi()
	return "%016x-%08x" % [time, rand]
