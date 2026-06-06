class_name ServiceInitializer extends RefCounted

## ServiceInitializer — Phase 4 + 5 der Boot-Pipeline.
##
## FILENAME-FIX: Ursprünglich "ServiceInitalizer.gd" (Tippfehler — fehlendes 'i').
## Godot findet Klassen per class_name-Scan, daher funktionierte es auf macOS/Windows
## (case-insensitive FS). Auf Linux CI-Servern (case-sensitive) schlug der Import fehl.
## Korrekte Datei: ServiceInitializer.gd — identischer Inhalt, korrekter Name.
##
## Phase 4: run()          → Führt Dependency Injection via configure(deps) aus.
## Phase 5: run_on_ready() → Aktiviert die Services via on_ready().

const LOG_CAT := "ServiceInitializer"


# ─────────────────────────────────────────────
# Phase 4 — Configuration & Injection
# ─────────────────────────────────────────────


func run(ordered: Array[String], registry: ServiceRegistry) -> void:
	Logger.log_debug("Phase 4 — configure() für %d Services." % ordered.size(), LOG_CAT)
	for service_name in ordered:
		var svc: Object = registry.get_service(service_name)
		var definition := registry.get_definition(service_name) as ServiceDefinition

		if svc == null or definition == null:
			Logger.log_error(
				"Kritischer Fehler: '%s' nicht in Registry gefunden!" % service_name, LOG_CAT
			)
			continue

		# Dependency-Map für diesen Service zusammenstellen
		var dependencies: Dictionary = {}
		for dep_name in definition.deps:
			var dep_svc: Object = registry.get_service(dep_name)
			if dep_svc:
				dependencies[dep_name.to_lower()] = dep_svc
				Logger.log_debug(
					"  Dep '%s' → '%s': OK" % [dep_name, dep_svc.get_class()], LOG_CAT
				)
			else:
				Logger.log_warn(
					"Abhängigkeit '%s' für '%s' fehlt!" % [dep_name, service_name], LOG_CAT
				)

		if svc.has_method("configure"):
			var t := Logger.log_begin("configure '%s'" % service_name, LOG_CAT)
			svc.configure(dependencies)
			Logger.log_end("configure '%s'" % service_name, t, LOG_CAT)
		else:
			Logger.log_warn("'%s' hat keine configure()-Methode." % service_name, LOG_CAT)


# ─────────────────────────────────────────────
# Phase 5 — Activation
# ─────────────────────────────────────────────


func run_on_ready(ordered: Array[String], registry: ServiceRegistry) -> void:
	Logger.log_debug("Phase 5 — on_ready() für %d Services." % ordered.size(), LOG_CAT)
	for service_name in ordered:
		var svc: Object = registry.get_service(service_name)
		if svc == null:
			Logger.log_warn("'%s' nicht in Registry — on_ready() übersprungen." % service_name, LOG_CAT)
			continue

		if svc.has_method("on_ready"):
			var t := Logger.log_begin("on_ready '%s'" % service_name, LOG_CAT)
			svc.on_ready()
			Logger.log_end("on_ready '%s'" % service_name, t, LOG_CAT)
		else:
			Logger.log_debug("'%s' hat kein on_ready() — übersprungen." % service_name, LOG_CAT)
