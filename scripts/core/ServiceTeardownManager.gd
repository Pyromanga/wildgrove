class_name ServiceTeardownManager extends RefCounted

## ServiceTeardownManager — Phase 7, Teardown-Pipeline.
##
## Wird vom ServiceOrchestrator in _notification(PREDELETE) aufgerufen.
## Reihenfolge ist bewusst umgekehrt zur Boot-Reihenfolge:
##   1. Services in umgekehrter Dep-Reihenfolge deaktivieren (on_cleanup)
##   2. Registry leeren
##
## Hinweis: Services.clear() wird vom ServiceOrchestrator VOR diesem
## Aufruf erledigt — hier wird nur noch die interne Registry geleert.

const LOG_CAT := "TeardownManager"

func execute(registry: ServiceRegistry) -> void:
	# Services in umgekehrter Reihenfolge aufräumen
	var all_services := registry.get_all()
	all_services.reverse()

	for svc in all_services:
		if not is_instance_valid(svc):
			continue

		if svc.has_method("on_cleanup"):
			var svc_name := _resolve_name(svc)
			Logger.log_debug("on_cleanup() → '%s'" % svc_name, LOG_CAT)
			svc.on_cleanup()

	# Registry leeren
	registry.clear()
	Logger.log_info("Teardown abgeschlossen.", LOG_CAT)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _resolve_name(svc: Object) -> String:
	if svc is Node:
		return (svc as Node).name
	if svc is Service:
		return (svc as Service).service_name
	return svc.get_class()