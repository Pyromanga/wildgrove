class_name ServiceInitializer extends RefCounted

## ServiceInitializer — Phase 4 + 5 der Boot-Pipeline.
##
## Phase 4: run()          → Führt Dependency Injection via configure(deps) aus.
## Phase 5: run_on_ready() → Aktiviert die Services via on_ready().
##
## ADR-017: Es gibt genau einen Weg, eine Scope-Grenze zu überqueren — der
## Aufrufer (BootPipeline) bridged benötigte Cross-Scope-Services VOR run()
## explizit per registry.register_resource() in die Ziel-Registry. Diese
## Klasse selbst kennt nur eine einzige Registry und rät nie in einer zweiten
## nach — kein impliziter Fallback mehr (löst den in AUDIT-05 dokumentierten
## Mechanismus-1/2-Konflikt zugunsten von Mechanismus 2 auf).

const LOG_CAT := "ServiceInitializer"

# ─────────────────────────────────────────────
# Phase 4 — Configuration & Injection
# ─────────────────────────────────────────────

func run(
	ordered: Array[String],
	registry: ServiceRegistry
) -> void:
	AppLogger.log_debug("Phase 4 — configure() für %d Services." % ordered.size(), LOG_CAT)
	for service_name in ordered:
		var svc: Object = registry.get_service(service_name)
		var definition := registry.get_definition(service_name) as ServiceDefinition

		if svc == null or definition == null:
			AppLogger.log_error(
				"Kritischer Fehler: '%s' nicht in Registry gefunden!" % service_name, LOG_CAT
			)
			continue

		# Dependency-Map für diesen Service zusammenstellen. Jede Dependency muss
		# bereits in DIESER Registry stehen — entweder als eigener Service dieses
		# Scopes, oder von BootPipeline vorab aus dem Eltern-Scope gebridged
		# (ADR-017). Kein Nachschlagen in einer zweiten Registry hier.
		var dependencies: Dictionary = {}
		for dep_name in definition.all_deps():
			var dep_svc: Object = registry.get_service(dep_name)
			if dep_svc:
				dependencies[dep_name.to_lower()] = dep_svc
				AppLogger.log_debug(
					"  Dep '%s' → '%s': OK" % [dep_name, dep_svc.get_class()], LOG_CAT
				)
			elif dep_name in definition.required_deps:
				AppLogger.log_warn(
					"Pflicht-Abhängigkeit '%s' für '%s' fehlt!" % [dep_name, service_name], LOG_CAT
				)
			# optionale Dep fehlt: kein Log — das ist der Normalfall (get_optional()
			# im Service-Code degradiert graceful, siehe ServiceDeps.gd).

			# Service/ServiceNode implementieren configure() — kein Tippfehler-Risiko.
		if svc is Service or svc is ServiceNode:
			var t := AppLogger.log_begin("configure '%s'" % service_name, LOG_CAT)
			svc.configure(ServiceDeps.from_dict(dependencies))
			AppLogger.log_end("configure '%s'" % service_name, t, LOG_CAT)
		else:
			AppLogger.log_warn("'%s' ist kein Service/ServiceNode — configure() übersprungen." % service_name, LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5 — Activation
# ─────────────────────────────────────────────

func run_on_ready(
	ordered: Array[String],
	registry: ServiceRegistry
) -> void:
	AppLogger.log_debug("Phase 5 — on_ready() für %d Services." % ordered.size(), LOG_CAT)
	for service_name in ordered:
		var svc: Object = registry.get_service(service_name)
		if svc == null:
			AppLogger.log_warn("'%s' nicht in Registry — on_ready() übersprungen." % service_name, LOG_CAT)
			continue

		if svc is Service or svc is ServiceNode:
			var t := AppLogger.log_begin("on_ready '%s'" % service_name, LOG_CAT)
			svc.on_ready()
			AppLogger.log_end("on_ready '%s'" % service_name, t, LOG_CAT)
		else:
			AppLogger.log_debug("'%s' ist kein Service/ServiceNode — on_ready() übersprungen." % service_name, LOG_CAT)
