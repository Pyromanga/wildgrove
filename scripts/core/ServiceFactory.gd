class_name ServiceFactory extends RefCounted

## ServiceFactory — Instanziiert Services aus ServiceDefinition-Einträgen.
## Unterscheidet zwischen Node-Services (ServiceNode) und Pure Services (Service).
## Node-Services werden in den Baum gehängt → _ready() registriert sie im Kernel.
## Pure Services werden direkt erstellt und manuell im Kernel registriert.

const LOG_CAT := "ServiceFactory"

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Erstellt einen Service anhand seiner Definition.
## Gibt das erstellte Objekt zurück oder null bei Fehler.
func create_service(definition: ServiceDefinition, parent: Node) -> Object:
	assert(definition != null, "ServiceFactory.create_service: definition darf nicht null sein!")
	assert(not definition.service_name.is_empty(), "ServiceDefinition.service_name darf nicht leer sein!")
	assert(not definition.path.is_empty(), "ServiceDefinition.path darf nicht leer sein!")

	var loaded = load(definition.path)
	if not loaded:
		Logger.log_error(
			"Ressource nicht ladbar: '%s' (Service: '%s')" % [definition.path, definition.service_name],
			LOG_CAT
		)
		return null

	Logger.log_debug(
		"Erstelle Service '%s' von '%s' (node_service: %s)" % [
			definition.service_name, definition.path, definition.is_node_service
		],
		LOG_CAT
	)

	if loaded is PackedScene:
		return _create_from_scene(loaded, definition, parent)
	elif loaded is GDScript:
		return _create_from_script(loaded, definition, parent)
	else:
		Logger.log_error(
			"Unbekannter Ressourcentyp für '%s': %s" % [definition.service_name, loaded.get_class()],
			LOG_CAT
		)
		return null

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _create_from_scene(scene: PackedScene, definition: ServiceDefinition, parent: Node) -> Node:
	var instance = scene.instantiate()
	if not instance is Node:
		Logger.log_error("PackedScene für '%s' ist kein Node nach instantiate()!" % definition.service_name, LOG_CAT)
		instance.free()
		return null

	instance.name = definition.service_name
	parent.add_child(instance)
	Logger.log_debug("Scene-Service '%s' erstellt und in Baum gehängt." % definition.service_name, LOG_CAT)
	return instance

func _create_from_script(script: GDScript, definition: ServiceDefinition, parent: Node) -> Object:
	var instance = script.new()

	if instance is Node:
		# Node-Service: In den Baum hängen → ServiceNode._ready() registriert ihn selbst.
		instance.name = definition.service_name
		parent.add_child(instance)
		Logger.log_debug("Node-Service '%s' erstellt und in Baum gehängt." % definition.service_name, LOG_CAT)
		return instance

	elif instance is RefCounted:
		# Pure Service: Kernel-Registrierung muss manuell passieren.
		if instance is Service:
			instance.service_name = definition.service_name
		else:
			Logger.log_warn(
				"Pure Service '%s' erbt nicht von Service-Basisklasse. service_name nicht gesetzt!" % definition.service_name,
				LOG_CAT
			)
		Kernel.register_service(instance)
		Logger.log_debug("Pure Service '%s' erstellt und im Kernel registriert." % definition.service_name, LOG_CAT)
		return instance

	else:
		Logger.log_error(
			"Service '%s' ist weder Node noch RefCounted — kann nicht verwaltet werden!" % definition.service_name,
			LOG_CAT
		)
		return null