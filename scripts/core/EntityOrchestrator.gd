extends Node
class_name EntityOrchestrator

## EntityOrchestrator — Zuständig für Entity-Lifecycle und Gruppen-Management.
##
## LEBT ALS CHILD VON WorldService (nicht als Autoload).
## Entities (NPCs, Ressourcen, Truhen) haben anderen Lebenszyklus als Services.
##
## Verantwortung:
##   - Spawn/Despawn von World-Entities per type_id
##   - Object Pooling (max. POOL_SIZE pro Typ) für Performance
##   - UUID-basiertes Entity-Tracking
##   - on_world_unloaded() für sauberes Cleanup bei Szenenwechsel
##
## Anti-Pattern das VERMIEDEN wird:
##   - KEIN set_script() auf bereits erstellten Nodes (doppeltes _ready())
##   - Stattdessen: GDScript.new() oder PackedScene.instantiate()
##
## Verwendung (von WorldService.on_world_scene_ready() aufgerufen):
##   entity_orchestrator.initialize(world_root)
##   entity_orchestrator.spawn_entity("oak_tree", Vector3(5, 0, 5))

const LOG_CAT := "EntityOrchestrator"
const POOL_SIZE := 10

## Referenz auf die aktuelle Welt-Szene (wird bei Szenenwechsel ersetzt)
var _world_root: Node3D = null

## Registry der aktiven Entities: { uuid: Node3D }
var _entities: Dictionary = {}

## Entity-Definitionen: { type_id: { "path": "res://...", "group": "trees" } }
var _definitions: Dictionary = {}

## Object Pool: { type_id: Array[Node3D] }
## Entities die despawnt wurden aber noch valid sind bleiben hier bis wiederverwendet
var _pool: Dictionary = {}

## Statistiken für Debug-Ausgaben
var _stats: Dictionary = {
	"total_spawned": 0,
	"total_despawned": 0,
	"pool_hits": 0,
	"pool_misses": 0,
}


# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────


func _ready() -> void:
	Logger.log_info("EntityOrchestrator bereit (child von WorldService).", LOG_CAT)


## Initialisiert den Orchestrator für eine neue Welt-Szene.
## Muss aufgerufen werden bevor spawn_entity() nutzbar ist.
## Sicher mehrfach aufrufbar (idempotent) — räumt alte Zustand-Referenzen auf.
func initialize(world_root: Node3D) -> void:
	if not is_instance_valid(world_root):
		Logger.log_error("initialize() fehlgeschlagen: world_root ist null oder invalid.", LOG_CAT)
		return

	# Alte Welt aufräumen falls vorhanden
	if _world_root != null:
		Logger.log_warn(
			"initialize() erneut aufgerufen — vorheriger world_root '%s' wird ersetzt."
			% (_world_root.name if is_instance_valid(_world_root) else "<freigegeben>"),
			LOG_CAT
		)
		_entities.clear()

	_world_root = world_root
	Logger.log_info(
		"Initialisiert für World '%s'. Definitionen: %d." % [world_root.name, _definitions.size()],
		LOG_CAT
	)


## Wird von WorldService aufgerufen BEVOR die Welt-Szene entladen wird.
## Ruft on_despawn() auf Entities auf (State-Sicherung), leert dann die Tracking-Map.
## Entities selbst werden vom SceneTree beim Entladen der Szene freigegeben.
func on_world_unloaded() -> void:
	var count := _entities.size()
	Logger.log_info(
		"World-Unload: %d aktive Entities werden bereinigt." % count, LOG_CAT
	)

	for uuid in _entities.keys():
		var entity := _entities[uuid] as Node3D
		if is_instance_valid(entity):
			var type_id: String = entity.get_meta("entity_type", "")
			Logger.log_debug(
				"on_despawn() → '%s' (uuid: %s)" % [type_id, uuid], LOG_CAT
			)
			if entity.has_method("on_despawn"):
				entity.on_despawn()
		else:
			Logger.log_debug("Entity '%s' bereits freigegeben." % uuid, LOG_CAT)

	_entities.clear()
	_world_root = null

	# Pool-Nodes die noch nicht im Tree sind aufräumen
	var pool_freed := 0
	for type_id in _pool.keys():
		for pooled in _pool[type_id]:
			if is_instance_valid(pooled) and not pooled.is_inside_tree():
				pooled.queue_free()
				pool_freed += 1
	_pool.clear()

	Logger.log_info(
		"EntityOrchestrator zurückgesetzt. Aktive: 0, Pool freigegeben: %d." % pool_freed,
		LOG_CAT
	)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


## Registriert eine Entity-Definition.
## MUSS vor spawn_entity() aufgerufen werden.
func register_definition(type_id: String, script_path: String, group: String = "") -> void:
	if type_id.is_empty():
		Logger.log_error("register_definition(): type_id darf nicht leer sein!", LOG_CAT)
		return
	if script_path.is_empty():
		Logger.log_error("register_definition('%s'): script_path leer!" % type_id, LOG_CAT)
		return
	if not ResourceLoader.exists(script_path):
		Logger.log_error(
			"register_definition('%s'): Pfad nicht gefunden: '%s'" % [type_id, script_path],
			LOG_CAT
		)
		return

	_definitions[type_id] = {"path": script_path, "group": group}
	Logger.log_debug(
		"Definition registriert: '%s' → '%s' [group: '%s']" % [type_id, script_path, group],
		LOG_CAT
	)


## Instanziiert eine Entity anhand ihrer type_id.
## config: optionale Konfiguration die an on_spawn() übergeben wird.
## Gibt die Entity zurück oder null bei Fehler.
func spawn_entity(type_id: String, position: Vector3, config: Dictionary = {}) -> Node3D:
	if not is_instance_valid(_world_root):
		Logger.log_error(
			"spawn_entity('%s') fehlgeschlagen: Kein world_root. initialize() aufgerufen?"
			% type_id,
			LOG_CAT
		)
		return null

	var def: Dictionary = _definitions.get(type_id, {})
	if def.is_empty():
		Logger.log_error(
			"Unbekannte Entity-Type: '%s'. Prüfe register_definition() Aufrufe." % type_id,
			LOG_CAT
		)
		return null

	var entity := _create_or_pool(type_id, def)
	if not is_instance_valid(entity):
		Logger.log_error(
			"spawn_entity('%s'): Instanziierung fehlgeschlagen." % type_id, LOG_CAT
		)
		return null

	# Position setzen BEVOR add_child damit _ready() korrekte globale Position sieht
	entity.position = position

	var uuid := _generate_uuid()
	entity.set_meta("entity_uuid", uuid)
	entity.set_meta("entity_type", type_id)

	_world_root.add_child(entity)  # ← _ready() feuert hier
	_entities[uuid] = entity

	# on_spawn NACH add_child (Entity ist jetzt im Tree)
	if entity.has_method("on_spawn"):
		entity.on_spawn(config)

	_stats["total_spawned"] += 1

	EventBus.world.emit_entity_spawned(type_id, entity, position)

	Logger.log_info(
		"Entity gespawnt: type='%s' uuid='%s' pos=%s" % [type_id, uuid, str(position)],
		LOG_CAT
	)
	return entity


## Despawnt eine Entity anhand ihrer UUID. Gibt sie in den Pool zurück wenn möglich.
func despawn_entity(uuid: String) -> void:
	if uuid.is_empty():
		Logger.log_warn("despawn_entity(): UUID ist leer!", LOG_CAT)
		return

	if not _entities.has(uuid):
		Logger.log_warn("despawn_entity('%s'): UUID nicht in aktiven Entities." % uuid, LOG_CAT)
		return

	var entity := _entities[uuid] as Node3D
	var type_id: String = entity.get_meta("entity_type", "") if is_instance_valid(entity) else ""

	_entities.erase(uuid)
	_stats["total_despawned"] += 1

	if not is_instance_valid(entity):
		Logger.log_debug("Entity '%s' war bereits freigegeben." % uuid, LOG_CAT)
		EventBus.world.emit_entity_despawned(type_id, uuid)
		return

	if entity.has_method("on_despawn"):
		entity.on_despawn()

	if _try_return_to_pool(type_id, entity):
		Logger.log_debug("Entity '%s' (%s) → Pool zurückgegeben." % [uuid, type_id], LOG_CAT)
	else:
		entity.queue_free()
		Logger.log_debug("Entity '%s' (%s) → queue_free()." % [uuid, type_id], LOG_CAT)

	EventBus.world.emit_entity_despawned(type_id, uuid)


## Gibt alle aktiven Entities einer bestimmten Gruppe zurück.
func get_entities_in_group(group: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for uuid in _entities:
		var entity := _entities[uuid] as Node3D
		if is_instance_valid(entity) and entity.is_in_group(group):
			result.append(entity)
	return result


## Gibt die Anzahl der aktiven Entities zurück.
func get_entity_count() -> int:
	return _entities.size()


## Gibt die Entity mit einer bestimmten UUID zurück, oder null.
func get_entity(uuid: String) -> Node3D:
	return _entities.get(uuid)


## Gibt Debug-Statistiken zurück für SimpleTerminal.
func get_debug_info() -> Dictionary:
	var pool_sizes: Dictionary = {}
	for type_id in _pool:
		pool_sizes[type_id] = _pool[type_id].size()
	return {
		"world_root": _world_root.name if is_instance_valid(_world_root) else "<null>",
		"active_entities": _entities.size(),
		"definitions": _definitions.keys(),
		"pool_sizes": pool_sizes,
		"stats": _stats.duplicate(),
	}


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _create_or_pool(type_id: String, def: Dictionary) -> Node3D:
	# Pool-Check: wiederverwendbare Instanz nehmen wenn vorhanden
	if _pool.has(type_id) and not _pool[type_id].is_empty():
		var pooled := _pool[type_id].pop_back() as Node3D
		if is_instance_valid(pooled):
			_stats["pool_hits"] += 1
			Logger.log_debug("Pool-Hit: '%s' (Pool noch: %d)" % [type_id, _pool[type_id].size()], LOG_CAT)
			return pooled
		Logger.log_debug("Pool-Eintrag für '%s' war invalid — übersprungen." % type_id, LOG_CAT)

	_stats["pool_misses"] += 1

	# Neu instanziieren — KEIN set_script() nach new()!
	# set_script() auf einem bereits erstellten Node triggert _ready() doppelt.
	# Stattdessen: direkt das Script laden und .new() aufrufen.
	var path: String = def.get("path", "")
	if path.is_empty() or not ResourceLoader.exists(path):
		Logger.log_error("Entity-Pfad fehlt oder nicht vorhanden: '%s'" % path, LOG_CAT)
		return null

	var loaded := load(path)
	if loaded == null:
		Logger.log_error("Entity-Resource konnte nicht geladen werden: '%s'" % path, LOG_CAT)
		return null

	var instance: Node3D
	if loaded is PackedScene:
		instance = (loaded as PackedScene).instantiate() as Node3D
		Logger.log_debug("Entity aus PackedScene: '%s'" % type_id, LOG_CAT)
	elif loaded is GDScript:
		instance = (loaded as GDScript).new() as Node3D
		Logger.log_debug("Entity aus GDScript.new(): '%s'" % type_id, LOG_CAT)
	else:
		Logger.log_error(
			"Unbekannter Ressource-Typ für '%s': %s" % [type_id, loaded.get_class()], LOG_CAT
		)
		return null

	if instance == null:
		Logger.log_error("GDScript.new() für '%s' gab null zurück (extends Node3D?)." % type_id, LOG_CAT)
		return null

	# Gruppe setzen VOR add_to_tree (wird in _ready() evtl. gebraucht)
	var group: String = def.get("group", "")
	if not group.is_empty():
		instance.add_to_group(group)

	return instance


func _try_return_to_pool(type_id: String, entity: Node3D) -> bool:
	if type_id.is_empty():
		return false
	if not _definitions.has(type_id):
		return false  # Unbekannte Type → kein Pool

	if not _pool.has(type_id):
		_pool[type_id] = []

	if _pool[type_id].size() >= POOL_SIZE:
		Logger.log_debug("Pool voll für '%s' (max: %d) → queue_free." % [type_id, POOL_SIZE], LOG_CAT)
		return false

	# Aus dem Tree entfernen bevor im Pool lagern
	if entity.is_inside_tree() and is_instance_valid(entity.get_parent()):
		entity.get_parent().remove_child(entity)

	_pool[type_id].append(entity)
	return true


func _generate_uuid() -> String:
	## Erzeugt eine UUID-ähnliche ID für Entity-Tracking.
	## Format: XXXXXXXXXXXXXXXX-XXXXXXXX (Zeit-basiert + Random)
	## Für Multiplayer: durch eine kryptografisch sichere UUID-Bibliothek ersetzen.
	var time := Time.get_ticks_usec()
	var rand := randi()
	return "%016x-%08x" % [time, rand]
