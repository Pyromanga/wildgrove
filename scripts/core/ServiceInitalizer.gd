class_name ServiceInitializer extends RefCounted

## ServiceInitializer — Phase 4 + 5 der Boot-Pipeline.
##
## Phase 4: run()          → ruft init() auf jedem Service auf
## Phase 5: run_on_ready() → ruft on_ready() auf jedem Service auf
##
## Services ohne die jeweilige Methode werden übersprungen (nur Warnung).
## Beide Phasen laufen in der aufgelösten Dep-Reihenfolge.

const LOG_CAT := "ServiceInitializer"

# ─────────────────────────────────────────────
# Phase 4 — init()
# ─────────────────────────────────────────────

# res://scripts/core/pipeline/ServiceInitializer.gd

func run(ordered: Array[String], registry: ServiceRegistry) -> void:
    for service_name in ordered:
        var svc := registry.get_service(service_name)
        var definition := registry.get_definition(service_name)
        
        if svc == null or definition == null:
            Logger.log_error("Kritischer Fehler: '%s' nicht in Registry gefunden!" % service_name, LOG_CAT)
            continue

        # Dependency Injection Paket schnüren
        var dependencies := {}
        for dep_name in definition.deps:
            var dep_svc = registry.get_service(dep_name)
            if dep_svc:
                dependencies[dep_name] = dep_svc
            else:
                Logger.log_warn("Abhängigkeit '%s' für '%s' ist NULL!" % [dep_name, service_name], LOG_CAT)
            
        if svc.has_method("init"):
            Logger.log_debug("init(deps) -> '%s'" % service_name, LOG_CAT)
            svc.init(dependencies)
        else:
            Logger.log_warn("'%s' hat keine init()-Methode." % service_name, LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5 — on_ready()
# FIX: Neue Methode — wird von ServiceOrchestrator in Phase 5 aufgerufen.
# Ersetzt den fehlenden ServiceActivator.
# ─────────────────────────────────────────────

func run_on_ready(ordered: Array[String], registry: ServiceRegistry) -> void:
	for service_name in ordered:
		var svc := registry.get_service(service_name)
		if svc == null:
			continue

		if not svc.has_method("on_ready"):
			continue  # on_ready ist optional — kein Warn-Log nötig

		Logger.log_debug("on_ready() → '%s'" % service_name, LOG_CAT)
		svc.on_ready()