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
        var definition := registry.get_definition(service_name) # Wir brauchen die Metadaten
        
        # Wir bauen ein passgenaues Paket nur mit den benötigten Services
        var dependencies := {}
        for dep_name in definition.deps:
            dependencies[dep_name] = registry.get_service(dep_name)
            
        Logger.log_debug("Injecting deps into -> '%s'" % service_name, LOG_CAT)
        svc.init(dependencies) # Nur das Nötigste!

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