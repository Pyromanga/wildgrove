class_name ServiceInitializer extends RefCounted

## ServiceInitializer — Phase 4 + 5 der Boot-Pipeline.
##
## Phase 4: run()          → Führt Dependency Injection via configure() aus.
## Phase 5: run_on_ready() → Aktiviert die Services via on_ready().

const LOG_CAT := "ServiceInitializer"

# ─────────────────────────────────────────────
# Phase 4 — Configuration & Injection
# ─────────────────────────────────────────────


func run(ordered: Array[String], registry: ServiceRegistry) -> void:
	for service_name in ordered:
		# 1. Service und seinen Bauplan (Definition) holen
		var svc: Object = registry.get_service(service_name)
		var definition := registry.get_definition(service_name) as ServiceDefinition

		if svc == null or definition == null:
			Logger.log_error(
				"Kritischer Fehler: '%s' nicht in Registry gefunden!" % service_name, LOG_CAT
			)
			continue

		# 2. Werkzeugkasten (Dependencies) nur für DIESEN Service packen
		var dependencies := {}
		for dep_name in definition.deps:
			var dep_svc = registry.get_service(dep_name)
			if dep_svc:
				dependencies[dep_name.to_lower()] = dep_svc
			else:
				Logger.log_warn(
					"Abhängigkeit '%s' für '%s' fehlt im Lager!" % [dep_name, service_name], LOG_CAT
				)

		# 3. Injection: Wir legen dem Arbeiter die Werkzeuge auf den Tisch
		# Wir nutzen 'configure', um Godot-interne Namenskonflikte (init) zu vermeiden.
		if svc.has_method("configure"):
			Logger.log_debug("configure(deps) -> '%s'" % service_name, LOG_CAT)
			svc.configure(dependencies)
		else:
			# Enterprise-Check: Ein Service OHNE configure ist verdächtig,
			# es sei denn, er hat absolut keine Abhängigkeiten.
			Logger.log_warn("'%s' hat keine configure()-Methode." % service_name, LOG_CAT)


# ─────────────────────────────────────────────
# Phase 5 — Activation
# ─────────────────────────────────────────────


func run_on_ready(ordered: Array[String], registry: ServiceRegistry) -> void:
	for service_name in ordered:
		var svc: Object = registry.get_service(service_name)
		if svc == null:
			continue

		# on_ready ist der Startschuss für die Logik (nachdem alle konfiguriert sind)
		if svc.has_method("on_ready"):
			Logger.log_debug("on_ready() -> '%s'" % service_name, LOG_CAT)
			svc.on_ready()
