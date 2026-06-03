class_name ServiceFactory extends RefCounted

## ServiceFactory — Phase 3 der Boot-Pipeline.
##
## Instanziiert alle Services und registriert sie direkt in der Registry.
## Die Factory ist der einzige Ort wo Registrierung stattfindet.
##
## Ablauf für Node-Services:
##   1. instance.name setzen
##   2. registry.register(instance)  ← VOR add_child()
##   3. parent.add_child(instance)   ← _ready() läuft danach
##
## Ablauf für Pure Services (RefCounted):
##   1. instance.service_name setzen (falls extends Service)
##   2. registry.register(instance)

const LOG_CAT := "ServiceFactory"

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func instantiate_all(
	defs: Array[ServiceDefinition],
	registry: ServiceRegistry,
	parent: Node
) -> bool:
	var ok    := 0
	var total := defs.size()

	for def in defs:
		if _create_service(def, registry, parent) != null:
			ok += 1
		else:
			Logger.log_error("Konnte '%s' nicht erstellen!" % def.service_name, LOG_CAT)

	Logger.log_info("%d/%d Services erstellt." % [ok, total], LOG_CAT)
	return ok == total

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _create_service(
	def: ServiceDefinition,
	registry: ServiceRegistry,
	parent: Node
) -> Object:
	assert(def != null,                     "ServiceFactory: def darf nicht null sein!")
	assert(not def.service_name.is_empty(), "ServiceFactory: service_name darf nicht leer sein!")
	assert(not def.path.is_empty(),         "ServiceFactory: path darf nicht leer sein!")

	var loaded = load(def.path)
	if not loaded:
		Logger.log_error(
			"Ressource nicht ladbar: '%s' (Service: '%s')" % [def.path, def.service_name],
			LOG_CAT
		)
		return null

	Logger.log_debug("Erstelle '%s' von '%s'" % [def.service_name, def.path], LOG_CAT)

	if loaded is PackedScene:
		return _from_scene(loaded, def, registry, parent)
	elif loaded is GDScript:
		return _from_script(loaded, def, registry, parent)
	else:
		Logger.log_error(
			"Unbekannter Ressourcentyp für '%s': %s" % [def.service_name, loaded.get_class()],
			LOG_CAT
		)
		return null

func _from_scene(
	scene: PackedScene,
	def: ServiceDefinition,
	registry: ServiceRegistry,
	parent: Node
) -> Node:
	var instance: Node = scene.instantiate()
	if instance == null:
		Logger.log_error("PackedScene für '%s' ergab null nach instantiate()." % def.service_name, LOG_CAT)
		return null

	instance.name = def.service_name
	# Registrierung VOR add_child — Service ist in Registry bevor _ready() läuft
	registry.register(instance)
	parent.add_child(instance)
	Logger.log_debug("Scene-Service '%s' registriert und in Baum gehängt." % def.service_name, LOG_CAT)
	return instance

func _from_script(
	script: GDScript,
	def: ServiceDefinition,
	registry: ServiceRegistry,
	parent: Node
) -> Object:
	var instance: Object = script.new()

	if instance is Node:
		if not instance is ServiceNode:
			Logger.log_warn(
				"'%s' ist ein Node aber kein ServiceNode — lifecycle-Methoden werden nicht aufgerufen!" % def.service_name,
				LOG_CAT
			)
		instance.name = def.service_name
		# Registrierung VOR add_child — gleiche Garantie wie bei PackedScene
		registry.register(instance)
		parent.add_child(instance)
		Logger.log_debug("Node-Service '%s' registriert und in Baum gehängt." % def.service_name, LOG_CAT)
		return instance

	elif instance is RefCounted:
		if instance is Service:
			instance.service_name = def.service_name
		else:
			Logger.log_warn(
				"Pure Service '%s' erbt nicht von Service — service_name nicht gesetzt." % def.service_name,
				LOG_CAT
			)
		registry.register(instance)
		Logger.log_debug("Pure Service '%s' in Registry eingetragen." % def.service_name, LOG_CAT)
		return instance

	else:
		Logger.log_error("Service '%s' ist weder Node noch RefCounted!" % def.service_name, LOG_CAT)
		instance.free()
		return null