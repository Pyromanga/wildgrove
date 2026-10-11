class_name EntityRegistry
extends RefCounted

## EntityRegistry — Verwaltet Entity-Definitionen und Instanziierung.
##
## Verantwortung:
##   - Definitionen { type_id: { path, group } } verwalten
##   - Aus Definition eine neue Instanz erstellen (PackedScene oder GDScript)
##   - KEIN set_script() auf bestehende Nodes (triggert _ready() doppelt)
##
## Verwendet von EntityOrchestrator.

const LOG_CAT := "EntityRegistry"

## { type_id: { "path": "res://...", "group": "trees" } }
var _definitions: Dictionary = {}

## Registriert eine Entity-Definition.
func register(type_id: String, script_path: String, group: String = "") -> void:
	if type_id.is_empty():
		AppLogger.log_error("register(): type_id darf nicht leer sein!", LOG_CAT)
		return
	if script_path.is_empty():
		AppLogger.log_error("register('%s'): script_path leer!" % type_id, LOG_CAT)
		return
	if not ResourceLoader.exists(script_path):
		AppLogger.log_error(
			"register('%s'): Pfad nicht gefunden: '%s'" % [type_id, script_path], LOG_CAT
		)
		return

	_definitions[type_id] = {"path": script_path, "group": group}
	AppLogger.log_debug(
		"Definition registriert: '%s' → '%s' [group: '%s']" % [type_id, script_path, group],
		LOG_CAT
	)

## Gibt die Definition für type_id zurück, oder {}.
func get_definition(type_id: String) -> Dictionary:
	return _definitions.get(type_id, {})

## True wenn eine Definition für type_id registriert ist.
func has(type_id: String) -> bool:
	return _definitions.has(type_id)

## Alle registrierten type_ids.
func get_keys() -> Array:
	return _definitions.keys()

## Gibt eine umgekehrte Map { script_path: type_id } zurück.
## Wird von MultiplayerSpawner.spawn_function genutzt um aus einem
## Godot-internen Spawn-Path den type_id zu ermitteln.
func get_path_to_type_map() -> Dictionary:
	var result: Dictionary = {}
	for type_id in _definitions:
		var path: String = _definitions[type_id].get("path", "")
		if not path.is_empty():
			result[path] = type_id
	return result

## Instanziiert eine neue Entity aus ihrer Definition.
## Gibt null zurück bei Fehler.
## Setzt die Gruppe VOR add_child (wird in _ready() evtl. gebraucht).
func instantiate(type_id: String) -> Node3D:
	var def: Dictionary = _definitions.get(type_id, {})
	if def.is_empty():
		AppLogger.log_error(
			"Unbekannte Entity-Type: '%s'. Prüfe register() Aufrufe." % type_id, LOG_CAT
		)
		return null

	var path: String = def.get("path", "")
	if path.is_empty() or not ResourceLoader.exists(path):
		AppLogger.log_error("Entity-Pfad fehlt oder nicht vorhanden: '%s'" % path, LOG_CAT)
		return null

	var loaded := load(path)
	if loaded == null:
		AppLogger.log_error("Entity-Resource konnte nicht geladen werden: '%s'" % path, LOG_CAT)
		return null

	var instance: Node3D
	if loaded is PackedScene:
		instance = (loaded as PackedScene).instantiate() as Node3D
		AppLogger.log_debug("Entity aus PackedScene: '%s'" % type_id, LOG_CAT)
	elif loaded is GDScript:
		instance = (loaded as GDScript).new() as Node3D
		AppLogger.log_debug("Entity aus GDScript.new(): '%s'" % type_id, LOG_CAT)
	else:
		AppLogger.log_error(
			"Unbekannter Ressource-Typ für '%s': %s" % [type_id, loaded.get_class()], LOG_CAT
		)
		return null

	if instance == null:
		AppLogger.log_error(
			"GDScript.new() für '%s' gab null zurück (extends Node3D?)." % type_id, LOG_CAT
		)
		return null

	# Gruppe setzen VOR add_to_tree
	var group: String = def.get("group", "")
	if not group.is_empty():
		instance.add_to_group(group)

	return instance
