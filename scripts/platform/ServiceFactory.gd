# res://scripts/platform/ServiceFactory.gd
class_name ServiceFactory extends RefCounted

## ServiceFactory — Phase 3 der Boot-Pipeline.
## Instanziiert Services aus GDScript oder PackedScene und registriert sie.
##
## FIX: script.new() kann null zurückgeben wenn das Script Parse-Fehler hat.
##      Vorher: is-Check auf null crashte ohne Log.
##      Jetzt:  explizite null-Prüfung mit präzisem Fehlertext.
##
## REFACTOR: NodeMounter-Injektion.
##      Vorher: _from_scene() / _from_script() riefen parent.add_child() direkt auf.
##      Jetzt:  mounter.mount(node, parent) — austauschbar in Tests ohne SceneTree.
##      Produktion:  ServiceFactory.new()                  → echter NodeMounter
##      Unit-Tests:  factory.mounter = NullNodeMounter.new() → kein add_child()

const LOG_CAT := "ServiceFactory"

## Injizierbarer Mounter. In Produktion: NodeMounter (echter add_child).
## In Tests: NullNodeMounter oder SpyNodeMounter (kein/spy add_child).
var mounter: NodeMounter = NodeMounter.new()

func instantiate_all(
	defs: Array[ServiceDefinition], registry: ServiceRegistry, parent: Node
) -> bool:
	var failed: Array[String] = []
	for def in defs:
		if _create_service(def, registry, parent) == null:
			failed.append(def.service_name)

	if not failed.is_empty():
		AppLogger.log_error(
			"Instanziierung fehlgeschlagen für: [%s]" % ", ".join(failed), LOG_CAT
		)
		AppLogger.log_error(
			"Häufige Ursachen: (1) Pfad falsch in BootstrapConfig.tres  "
			+ "(2) GDScript Parse-Fehler in der .gd-Datei  "
			+ "(3) class_name fehlt oder doppelt vergeben.",
			LOG_CAT
		)
		return false

	AppLogger.log_info("%d Services erfolgreich instanziiert." % defs.size(), LOG_CAT)
	return true

func _create_service(def: ServiceDefinition, registry: ServiceRegistry, parent: Node) -> Object:
	if not ResourceLoader.exists(def.path):
		AppLogger.log_error("Pfad existiert nicht: '%s' (Service: '%s')" % [def.path, def.service_name], LOG_CAT)
		return null

	var loaded = load(def.path)
	if loaded == null:
		AppLogger.log_error("load() fehlgeschlagen: '%s' — Datei korrupt oder Parse-Fehler?" % def.path, LOG_CAT)
		return null

	if loaded is PackedScene:
		return _from_scene(loaded, def, registry, parent)
	elif loaded is GDScript:
		return _from_script(loaded, def, registry, parent)

	AppLogger.log_error(
		"Unbekannter Ressourcentyp für '%s': %s" % [def.service_name, loaded.get_class()], LOG_CAT
	)
	return null

func _from_scene(
	scene: PackedScene, def: ServiceDefinition, registry: ServiceRegistry, parent: Node
) -> Node:
	var instance: Node = scene.instantiate()
	if instance == null:
		AppLogger.log_error("PackedScene.instantiate() gab null zurück: '%s'" % def.service_name, LOG_CAT)
		return null
	instance.name = def.service_name
	registry.register(instance, def)
	mounter.mount(instance, parent)
	return instance

func _from_script(
	script: GDScript, def: ServiceDefinition, registry: ServiceRegistry, parent: Node
) -> Object:
	var instance: Object = script.new()

	# KRITISCH: script.new() gibt null zurück wenn das Script Parse-Fehler hat.
	# In Godot 4 gibt es keine Exception — es ist stilles null.
	if instance == null:
		AppLogger.log_error(
			"script.new() gab null zurück für '%s' ('%s').\n"
			+ "  → Öffne die Datei in Godot um den Parse-Fehler zu sehen." % [def.service_name, def.path],
			LOG_CAT
		)
		return null

	if instance is Node:
		instance.name = def.service_name
		registry.register(instance, def)
		mounter.mount(instance, parent)
	else:
		if "service_name" in instance:
			instance.service_name = def.service_name
		registry.register(instance, def)

	return instance
