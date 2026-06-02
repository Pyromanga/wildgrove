# res://scripts/core/services/ServiceInitializer.gd
class_name ServiceInitializer extends RefCounted

## ServiceInitializer — Phase 4 der Boot-Pipeline.
##
## Ruft init() auf jedem Service in der aufgelösten Dep-Reihenfolge auf.
## Services ohne init()-Methode werden übersprungen (nur Warnung).

const LOG_CAT := "ServiceInitializer"

func run(ordered: Array[String], registry: ServiceRegistry) -> void:
	for service_name in ordered:
		var svc := registry.get_service(service_name)
		if svc == null:
			continue

		if not svc.has_method("init"):
			Logger.log_warn("'%s' hat keine init()-Methode — übersprungen." % service_name, LOG_CAT)
			continue

		Logger.log_debug("init() → '%s'" % service_name, LOG_CAT)
		svc.init()