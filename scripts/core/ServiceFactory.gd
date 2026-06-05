class_name ServiceFactory extends RefCounted

## ServiceFactory — Phase 3 der Boot-Pipeline.
## Instanziiert Services und verknüpft sie in der Registry mit ihren Definitionen.

const LOG_CAT := "ServiceFactory"


func instantiate_all(
	defs: Array[ServiceDefinition], registry: ServiceRegistry, parent: Node
) -> bool:
	var ok := 0
	for def in defs:
		if _create_service(def, registry, parent) != null:
			ok += 1
	return ok == defs.size()


func _create_service(def: ServiceDefinition, registry: ServiceRegistry, parent: Node) -> Object:
	var loaded = load(def.path)
	if not loaded:
		Logger.log_error("Pfad nicht ladbar: %s" % def.path, LOG_CAT)
		return null

	if loaded is PackedScene:
		return _from_scene(loaded, def, registry, parent)
	elif loaded is GDScript:
		return _from_script(loaded, def, registry, parent)
	return null


func _from_scene(
	scene: PackedScene, def: ServiceDefinition, registry: ServiceRegistry, parent: Node
) -> Node:
	var instance: Node = scene.instantiate()
	instance.name = def.service_name

	# WICHTIG: Wir geben die Definition mit!
	registry.register(instance, def)

	parent.add_child(instance)
	return instance


func _from_script(
	script: GDScript, def: ServiceDefinition, registry: ServiceRegistry, parent: Node
) -> Object:
	var instance: Object = script.new()

	if instance is Node:
		instance.name = def.service_name
		registry.register(instance, def)  # WICHTIG: Hier auch
		parent.add_child(instance)
	else:
		if instance is Service:
			instance.service_name = def.service_name
		registry.register(instance, def)  # WICHTIG: Und hier

	return instance
