extends GutTest

var _validator: ServiceValidator
var _resolver: ServiceDependencyResolver

func before_each() -> void:
	_validator = ServiceValidator.new()
	_resolver = ServiceDependencyResolver.new()

func test_app_services_resolve_without_missing_dependency() -> void:
	var defs := _validator.validate()
	assert_gt(defs.size(), 0, "global_services muss ladbar sein")

	var cfg := _validator.get_loaded_config()
	var resource_names: Array[String] = []
	for r in cfg.global_resources:
		resource_names.append(r.registry_key.to_lower())

	var external_names := resource_names.duplicate()
	external_names.append(ServiceKeys.EVENT_BUS)
	var ordered := _resolver.resolve(defs, external_names)

	assert_eq(ordered.size(), defs.size(), "alle App-Services müssen auflösbar sein")

func test_app_resolution_fails_loudly_if_event_bus_dep_not_declared_external() -> void:
	var defs := _validator.validate()
	var cfg := _validator.get_loaded_config()
	var resource_names: Array[String] = []
	for r in cfg.global_resources:
		resource_names.append(r.registry_key.to_lower())

	var has_event_bus_dep := false
	for d in defs:
		if ServiceKeys.EVENT_BUS in d.all_deps():
			has_event_bus_dep = true
			break
	assert_true(has_event_bus_dep, "mindestens ein Service muss event_bus als Dep deklarieren")

	var ordered := _resolver.resolve(defs, resource_names)
	assert_eq(ordered.size(), 0, "ohne event_bus in external_names muss die Auflösung scheitern")

func test_session_services_resolve_without_missing_dependency() -> void:
	var app_defs := _validator.validate()
	var app_names: Array[String] = []
	for d in app_defs:
		app_names.append(d.service_name.to_lower())

	var session_defs := _validator.validate_session(app_names)
	assert_gt(session_defs.size(), 0, "session_services muss ladbar sein")

	var external_names := app_names.duplicate()
	external_names.append(ServiceKeys.EVENT_BUS)
	var ordered := _resolver.resolve(session_defs, external_names)

	assert_eq(ordered.size(), session_defs.size(), "alle Session-Services müssen auflösbar sein")

## Regression: ein '#'-Kommentar in BootstrapConfig.tres (statt ';' — .tres ist
## INI-artig, '#' ist kein gültiges Kommentarzeichen) hat die Parser-Zuordnung der
## folgenden 'deps'-Property zerstört, sodass WorldService.deps still auf []
## zurückfiel. Der Resolver hat das nicht bemerkt (weniger Deps = leichter
## auflösbar) — nur eine direkte Prüfung der geladenen Werte fängt das ab.
func test_world_service_deps_are_fully_declared() -> void:
	var app_defs := _validator.validate()
	var app_names: Array[String] = []
	for d in app_defs:
		app_names.append(d.service_name.to_lower())

	var session_defs := _validator.validate_session(app_names)
	var world_def: ServiceDefinition = null
	for d in session_defs:
		if d.service_name.to_lower() == "world":
			world_def = d
			break

	assert_not_null(world_def, "ServiceDefinition für 'world' muss existieren")
	# required_deps/optional_deps-Migration: WorldService behandelt AUSNAHMSLOS
	# alle seine Deps via get_optional() (siehe WorldService.configure()) — die
	# komplette Liste liegt daher in optional_deps, required_deps ist leer.
	# all_deps() bleibt der richtige Check für diese Regression (Zeilenkommentar
	# oben): der ursprüngliche Bug war ein kaputter Parser, der ALLE Deps auf []
	# zurückfallen ließ — das gilt unabhängig von required/optional.
	assert_true(
		"event_bus" in world_def.all_deps(),
		"WorldService.all_deps() muss 'event_bus' enthalten (get_optional() in configure())"
	)
	assert_true("savesystem" in world_def.all_deps(), "WorldService.all_deps() muss 'savesystem' enthalten")
	assert_true("world_gen" in world_def.all_deps(), "WorldService.all_deps() muss 'world_gen' enthalten")
	assert_gt(world_def.all_deps().size(), 10, "WorldService.all_deps() sollte alle 15 deklarierten Einträge laden, nicht [])")

func test_full_dependency_graph_has_no_unresolvable_service() -> void:
	var app_defs := _validator.validate()
	var cfg := _validator.get_loaded_config()
	var resource_names: Array[String] = []
	for r in cfg.global_resources:
		resource_names.append(r.registry_key.to_lower())

	var app_external := resource_names.duplicate()
	app_external.append(ServiceKeys.EVENT_BUS)
	var app_ordered := _resolver.resolve(app_defs, app_external)
	assert_eq(app_ordered.size(), app_defs.size(), "App-Graph muss vollständig auflösbar sein")

	var app_names: Array[String] = []
	for d in app_defs:
		app_names.append(d.service_name.to_lower())

	var session_defs := _validator.validate_session(app_names)
	var session_external := app_names.duplicate()
	session_external.append(ServiceKeys.EVENT_BUS)
	var session_ordered := _resolver.resolve(session_defs, session_external)

	assert_eq(session_ordered.size(), session_defs.size(), "Session-Graph muss vollständig auflösbar sein")
